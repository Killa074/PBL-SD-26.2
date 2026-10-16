#define _POSIX_C_SOURCE 200809L
#define _FILE_OFFSET_BITS 64
#include "mailbox.h"
#include "scene.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <limits.h>
#ifndef _WIN32
#include <sys/mman.h>
#include <sys/file.h>
#include <fcntl.h>
#include <unistd.h>
#include <time.h>
#ifdef __arm__
extern uint32_t gpu_mmio_load32(volatile uint32_t *);
extern void gpu_mmio_store32(volatile uint32_t *,uint32_t);
#endif
static uint32_t ram_read(void *p,unsigned b){volatile uint32_t *a=(volatile uint32_t *)p+b/4;
#ifdef __arm__
 return gpu_mmio_load32(a);
#else
 uint32_t v;__sync_synchronize();v=*a;__sync_synchronize();return v;
#endif
}
static void ram_write(void *p,unsigned b,uint32_t v){volatile uint32_t *a=(volatile uint32_t *)p+b/4;
#ifdef __arm__
 gpu_mmio_store32(a,v);
#else
 __sync_synchronize();*a=v;__sync_synchronize();
#endif
}
static uint64_t now_ms(void *p){struct timespec t;(void)p;clock_gettime(CLOCK_MONOTONIC,&t);return(uint64_t)t.tv_sec*1000+t.tv_nsec/1000000;}
static void pause_ms(void *p){struct timespec t={0,1000000};(void)p;while(nanosleep(&t,&t)&&errno==EINTR){}}
#endif
static void usage(void){puts(
 "Offline: gpuctl --export-demo arquivo.hex\n"
 "Na HPS, SOMENTE depois de configurar o SOF e habilitar a ponte hps2fpga:\n"
 "  sudo ./gpuctl --fpga status | init | demo | present\n"
 "  sudo ./gpuctl --fpga load ../programs/demo.hex\n"
 "  sudo ./gpuctl --fpga scroll X Y\n"
 "  sudo ./gpuctl --fpga tile COL LIN TILE_ID\n"
 "  sudo ./gpuctl --fpga sprite SLOT X Y PADRAO FLAGS\n"
 "  sudo ./gpuctl --fpga rect X0 Y0 X1 Y1 COR\n"
 "  sudo ./gpuctl --fpga triangle X0 Y0 X1 Y1 X2 Y2 COR\n"
 "  sudo ./gpuctl --fpga palette INDICE RGB\n"
 "  sudo ./gpuctl --fpga raw PORTA DADO\n"
 "  sudo ./gpuctl --fpga batch arquivo.cmd\n"
 "  sudo ./gpuctl --fpga animate QUADROS\n"
 "Numeros decimais ou 0xHEX; coordenadas signed16. raw/batch NAO adicionam PRESENT.\n"
 "demo substitui a cena. init reinicia o controle, nao recarrega texturas.\n"
 "Um acesso com ponte desligada pode travar o ARM: --fpga nao habilita pontes.");}
static int number(const char *s,long long low,long long high,uint32_t *v){char *e;long long n;errno=0;n=strtoll(s,&e,0);if(errno||e==s||*e||n<low||n>high)return 0;*v=(uint32_t)n;return 1;}
static int arguments(int argc,char **argv,int expected,uint32_t *v){int i;if(argc!=expected)return 0;for(i=0;i<argc;i++)if(!number(argv[i],-32768,UINT32_MAX,&v[i]))return 0;return 1;}
static int coord(uint32_t x){return (int64_t)(int32_t)x>=-32768 && (int64_t)(int32_t)x<=32767;}
static int present(Mailbox *m,Command *c,size_t n){uint32_t frame;if(!mb_wait_idle(m)||!mb_read(m,GPU_FRAME,&frame))return 0;c[n].port=0xf0;c[n].data=0;return mb_commands(m,c,n+1)&&mb_present_wait(m,frame);}
static int load_hex(const char *path,uint32_t *words,size_t *count){FILE *f=fopen(path,"r");char line[256],extra;unsigned long v;size_t n=0;unsigned lineno=0;if(!f){perror(path);return 0;}while(fgets(line,sizeof line,f)){lineno++;if(line[0]=='#'||line[0]=='\n'||line[0]=='\r')continue;if(sscanf(line,"%lx %c",&v,&extra)!=1||v>UINT32_MAX||n==1024){fprintf(stderr,"HEX invalido linha %u (max 1024 palavras, uma por linha)\n",lineno);fclose(f);return 0;}words[n++]=(uint32_t)v;}if(ferror(f)){fclose(f);return 0;}fclose(f);*count=n;return n!=0;}
static int execute(Mailbox *m,int argc,char **argv){
 Command c[4097];uint32_t v[7],value,frame,words[1024];size_t n=0,i;uint64_t start;
 const char *cmd=argv[0];argc--;argv++;
#define ADD(P,D) do{c[n].port=(P);c[n++].data=(uint32_t)(D);}while(0)
 if(!strcmp(cmd,"status")&&argc==0){
  if(!mb_read(m,GPU_ID,&value))return 0;
  if(value!=0x47505533){snprintf(m->error,sizeof m->error,"GPU_ID incorreto: %08lX",(unsigned long)value);return 0;}
  printf("GPU3 id=%08lX\n",(unsigned long)value);
  {const unsigned offsets[]={4,8,0x14,0x18,0x24,0x38,0x3c,0x40};const char *names[]={"CONTROL","STATUS","PC","IR","OUT_COUNT","FIFO_FREE","FRAME_COUNT","ERROR"};
   for(i=0;i<8;i++){if(!mb_read(m,offsets[i],&value))return 0;printf("%-12s = 0x%08lX (%lu)\n",names[i],(unsigned long)value,(unsigned long)value);}}
  return 1;
 }
 if(!strcmp(cmd,"init")&&argc==0)return mb_prepare(m,1);
 if(!strcmp(cmd,"load")&&argc==1){
  if(!load_hex(argv[0],words,&n)){snprintf(m->error,sizeof m->error,"Arquivo HEX rejeitado");return 0;}
  if(!mb_prepare(m,0)||!mb_call(m,MB_PROGRAM,(unsigned)n,0,0,words,n,NULL)||!mb_write(m,GPU_CONTROL,3))return 0;
  start=m->io.now(m->io.context);
  do {if(!mb_read(m,GPU_STATUS,&value))return 0;if(value&4){snprintf(m->error,sizeof m->error,"CPU/GPU reportou erro durante programa");return 0;}
   if(m->io.now(m->io.context)-start>=m->timeout_ms){snprintf(m->error,sizeof m->error,"Programa nao chegou a HALT no timeout");return 0;}
  }while(!(value&2));
  return mb_wait_idle(m);
 }
 if(!strcmp(cmd,"demo")&&argc==0){
  if(!mb_prepare(m,1)||!mb_read(m,GPU_FRAME,&frame))return 0;
  n=demo_scene(c,4096);return n&&mb_commands(m,c,n)&&mb_present_wait(m,frame);
 }
 if(!strcmp(cmd,"animate")&&arguments(argc,argv,1,v)&&v[0]>=1&&v[0]<=600){
  for(i=0;i<v[0];i++){n=0;ADD(0x10,0);ADD(0x11,16+(i*3)%280);ADD(0x12,144);ADD(0,(i*2)%320);if(!present(m,c,n))return 0;}return 1;
 }
 if(!strcmp(cmd,"batch")&&argc==1){
  FILE *f=fopen(argv[0],"r");char line[256],tail;unsigned long p,d;unsigned lineno=0;if(!f){perror(argv[0]);snprintf(m->error,sizeof m->error,"Nao abriu batch");return 0;}
  while(fgets(line,sizeof line,f)){lineno++;if(line[0]=='#'||line[0]=='\n'||line[0]=='\r')continue;
   if(sscanf(line,"%lx %lx %c",&p,&d,&tail)!=2||p>255||d>UINT32_MAX||n==4096){fclose(f);snprintf(m->error,sizeof m->error,"Batch invalido na linha %u",lineno);return 0;}ADD((uint32_t)p,(uint32_t)d);}
  if(ferror(f)){fclose(f);snprintf(m->error,sizeof m->error,"Erro lendo batch");return 0;}fclose(f);
  return n && mb_commands(m,c,n) && mb_wait_idle(m);
 }
 if(!strcmp(cmd,"present")&&argc==0)return present(m,c,0);
 if(!strcmp(cmd,"scroll")&&arguments(argc,argv,2,v)&&v[0]<320&&v[1]<240){ADD(0,v[0]);ADD(1,v[1]);}
 else if(!strcmp(cmd,"tile")&&arguments(argc,argv,3,v)&&v[0]<40&&v[1]<30&&v[2]<256){ADD(0x20,v[1]*40+v[0]);ADD(0x21,v[2]);}
 else if(!strcmp(cmd,"sprite")&&arguments(argc,argv,5,v)&&v[0]<32&&coord(v[1])&&coord(v[2])&&v[3]<256&&v[4]<512){ADD(0x10,v[0]);ADD(0x11,v[1]&65535);ADD(0x12,v[2]&65535);ADD(0x13,v[3]);ADD(0x14,v[4]);}
 else if(!strcmp(cmd,"rect")&&arguments(argc,argv,5,v)&&coord(v[0])&&coord(v[1])&&coord(v[2])&&coord(v[3])&&v[4]<256){ADD(0x30,0);for(i=0;i<4;i++)ADD(0x31+(unsigned)i,v[i]&65535);ADD(0x37,v[4]);ADD(0x38,3);}
 else if(!strcmp(cmd,"triangle")&&arguments(argc,argv,7,v)&&coord(v[0])&&coord(v[1])&&coord(v[2])&&coord(v[3])&&coord(v[4])&&coord(v[5])&&v[6]<256){ADD(0x30,1);for(i=0;i<6;i++)ADD(0x31+(unsigned)i,v[i]&65535);ADD(0x37,v[6]);ADD(0x38,5);}
 else if(!strcmp(cmd,"palette")&&arguments(argc,argv,2,v)&&v[0]<256&&v[1]<=0xffffff){ADD(0x26,v[0]);ADD(0x27,v[1]);}
 else if(!strcmp(cmd,"raw")&&arguments(argc,argv,2,v)&&v[0]<256){ADD(v[0],v[1]);return mb_commands(m,c,n)&&mb_wait_idle(m);}
 else {snprintf(m->error,sizeof m->error,"Comando/argumentos invalidos; consulte --help");return 0;}
 return present(m,c,n);
#undef ADD
}
int main(int argc,char **argv){
 if(argc==3&&!strcmp(argv[1],"--export-demo")){
  Command c[4096];size_t n=demo_scene(c,4096),i;FILE *f=fopen(argv[2],"w");if(!n||!f){perror("export");return 1;}
  // Count prefix followed by port/data WORDS for the RTL testbench.
  fprintf(f,"%08lX\n",(unsigned long)n);for(i=0;i<n;i++)fprintf(f,"%08lX\n%08lX\n",(unsigned long)c[i].port,(unsigned long)c[i].data);
  if(fclose(f)){perror("close");return 1;}printf("Exportados %lu comandos do MESMO gerador usado na HPS\n",(unsigned long)n);return 0;
 }
 if(argc<3||strcmp(argv[1],"--fpga")){usage();return argc==2&&!strcmp(argv[1],"--help")?0:1;}
#ifdef _WIN32
 (void)execute;fprintf(stderr,"--fpga requer Linux na HPS; este EXE so exporta dados de teste.\n");return 1;
#else
 {int fd,lock,ok;void *mapping;Mailbox m;MailboxIO io;
  lock=open("/tmp/pbl_hps_gpu.lock",O_CREAT|O_RDWR|O_NOFOLLOW,0600);
  if(lock<0||flock(lock,LOCK_EX|LOCK_NB)){perror("Outro processo usa GPU, ou lock indisponivel");if(lock>=0)close(lock);return 1;}
  fd=open("/dev/mem",O_RDWR|O_SYNC);if(fd<0){perror("/dev/mem");close(lock);return 1;}
  mapping=mmap(NULL,65536,PROT_READ|PROT_WRITE,MAP_SHARED,fd,(off_t)0xc0000000ULL);
  if(mapping==MAP_FAILED){perror("mmap RAM HPS2FPGA");close(fd);close(lock);return 1;}
  io.context=mapping;io.read=ram_read;io.write=ram_write;io.now=now_ms;io.sleep=pause_ms;
  ok=mb_open(&m,io,15000)&&execute(&m,argc-2,argv+2);
  if(!ok)fprintf(stderr,"ERRO: %s; processed_ultimo_pedido=%lu. Blocos anteriores podem ter concluido. Nao reenvie cegamente.\n",m.error,(unsigned long)m.processed);
  else puts("OK");
  munmap(mapping,65536);close(fd);close(lock);return ok?0:1;
 }
#endif
}

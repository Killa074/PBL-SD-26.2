// Exercise the actual CLI command implementation using a synchronous mock
// of mailbox/GPU registers. Pixel correctness is checked by the RTL suite.
#define main gpuctl_entry
#include "gpuctl.c"
#undef main
#include <assert.h>
typedef struct {uint32_t ram[16384],regs[17],program[1024];Command trace[10000];size_t used;uint64_t ticks;} Fake;
static void command(Fake *f,uint32_t port,uint32_t data){assert(f->used<10000);f->trace[f->used].port=port;f->trace[f->used++].data=data;
 if(port==0xf0)f->regs[GPU_FRAME/4]++;
 if(port==0xf1)f->regs[GPU_ERROR/4]=0;
 f->regs[0x24/4]++;}
static uint32_t fake_read(void *p,unsigned a){return ((Fake*)p)->ram[a/4];}
static void fake_write(void *p,unsigned a,uint32_t v){Fake *f=p;unsigned i,op,count,reg;f->ram[a/4]=v;if(a!=MB_REQUEST)return;
 op=f->ram[MB_OP/4];count=f->ram[MB_COUNT/4];reg=f->ram[MB_ARG0/4]/4;f->ram[MB_ERROR/4]=0;
 if(op==MB_READ_REG)f->ram[MB_RESULT/4]=f->regs[reg];
 else if(op==MB_WRITE_REG){uint32_t d=f->ram[MB_ARG1/4];
  if(reg==GPU_CONTROL/4){f->regs[reg]=d&5;f->regs[GPU_STATUS/4]=0x10|((d&4)?0x40:0)|((d&1)&&!(d&4)?2:0);}
  else if(reg==GPU_ERROR/4)f->regs[reg]&=~d;
  else if(reg==0x34/4)command(f,f->regs[0x30/4],d);
  else f->regs[reg]=d;
 }else if(op==MB_PROGRAM){assert(count<=1024);for(i=0;i<count;i++)f->program[i]=f->ram[MB_PAYLOAD/4+i];}
 else if(op==MB_COMMANDS){assert(f->regs[GPU_CONTROL/4]==5);for(i=0;i<count;i++)command(f,f->ram[MB_PAYLOAD/4+i*2],f->ram[MB_PAYLOAD/4+i*2+1]);}
 else assert(0);
 f->ram[MB_PROCESSED/4]=count;f->ram[MB_DONE/4]=v;
}
static uint64_t fake_time(void *p){return ((Fake*)p)->ticks++;}
static void fake_sleep(void *p){((Fake*)p)->ticks++;}
int main(int argc,char **argv){static Fake f;Mailbox m;MailboxIO io={&f,fake_read,fake_write,fake_time,fake_sleep};size_t before;
 char *demo[]={"demo"},*sprite[]={"sprite","0","-8","144","1","0x1b"},*tile[]={"tile","5","5","1"};
 char *triangle[]={"triangle","180","160","260","160","220","100","10"};
 char *rect[]={"rect","20","30","50","60","11"},*scroll[]={"scroll","319","239"};
 char *palette[]={"palette","10","0x3366ff"},*animate[]={"animate","3"},*bad[]={"sprite","32","0","0","0","1"};
 char *load[]={"load",argc>1?argv[1]:"../programs/demo.hex"};
 f.ram[MB_MAGIC/4]=0x48505347;f.ram[MB_ABI/4]=1;f.regs[0]=0x47505533;f.regs[GPU_STATUS/4]=0x10;f.regs[GPU_FIFO/4]=64;
 assert(mb_open(&m,io,15000));assert(execute(&m,1,demo));assert(f.used==2085&&f.regs[GPU_FRAME/4]==1);
 before=f.used;assert(execute(&m,6,sprite));assert(f.trace[before+1].data==65528&&f.trace[before+4].data==0x1b);
 assert(execute(&m,4,tile));assert(execute(&m,8,triangle));assert(execute(&m,6,rect));assert(execute(&m,3,scroll));assert(execute(&m,3,palette));
 assert(execute(&m,2,animate));assert(f.regs[GPU_FRAME/4]==10);
 before=f.used;assert(!execute(&m,6,bad)&&f.used==before);
 assert(execute(&m,2,load));assert(f.program[1023]==0xf0000000&&f.regs[GPU_CONTROL/4]==1);
 puts("PASS test_cli: demo, sprite/flip, tile, triangle, rect, scroll, palette, animation, bounds, external program");return 0;
}

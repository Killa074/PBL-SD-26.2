#include "mailbox.h"
#include <stdio.h>
#include <string.h>
static int fail(Mailbox *m,const char *s,uint32_t v){snprintf(m->error,sizeof m->error,"%s (0x%08lX)",s,(unsigned long)v);return 0;}
int mb_open(Mailbox *m,MailboxIO io,unsigned timeout){
 memset(m,0,sizeof *m);m->io=io;m->timeout_ms=timeout?timeout:15000;
 if(!io.read||!io.write||!io.now||!io.sleep)return fail(m,"Transporte incompleto",0);
 if(io.read(io.context,MB_MAGIC)!=0x48505347 || io.read(io.context,MB_ABI)!=1)
  return fail(m,"Mailbox ausente: confirme SOF HPS correto, nao use o SOF antigo",0);
 m->sequence=io.read(io.context,MB_DONE);
 if(io.read(io.context,MB_REQUEST)!=m->sequence||io.read(io.context,MB_BUSY))
  return fail(m,"Operacao anterior pendente; nao sobrescreva o bloco",m->sequence);
 return 1;
}
int mb_call(Mailbox *m,unsigned op,unsigned count,uint32_t a,uint32_t b,const uint32_t *payload,size_t words,uint32_t *result){
 MailboxIO *io=&m->io;uint64_t start;uint32_t seq,err;size_t i;
 if(words>8192 || (words && !payload) || (op==MB_PROGRAM&&(count==0||count>1024||words!=count)) ||
    (op==MB_COMMANDS&&(count==0||count>4096||words!=(size_t)count*2)))return fail(m,"Bloco invalido",count);
 if(io->read(io->context,MB_REQUEST)!=io->read(io->context,MB_DONE)||io->read(io->context,MB_BUSY))
  return fail(m,"Mailbox ocupada; pedido nao enviado",0);
 seq=m->sequence+1;if(!seq)seq=1;
 for(i=0;i<words;i++)io->write(io->context,MB_PAYLOAD+(unsigned)i*4,payload[i]);
 // Readback drains posted writes through the same H2F path before publication.
 if(words && io->read(io->context,MB_PAYLOAD+(unsigned)(words-1)*4)!=payload[words-1])
  return fail(m,"Falha no readback da RAM",0);
 io->write(io->context,MB_OP,op);io->write(io->context,MB_COUNT,count);
 io->write(io->context,MB_ARG0,a);io->write(io->context,MB_ARG1,b);
 if(io->read(io->context,MB_ARG1)!=b)return fail(m,"Falha no descritor",0);
 io->write(io->context,MB_REQUEST,seq);m->sequence=seq;start=io->now(io->context);
 while(io->read(io->context,MB_DONE)!=seq){
  if(io->now(io->context)-start>=m->timeout_ms)return fail(m,"Timeout: NAO reenvie o lote; confira status/reset",seq);
  io->sleep(io->context);
 }
 m->processed=io->read(io->context,MB_PROCESSED);err=io->read(io->context,MB_ERROR);
 if(result)*result=io->read(io->context,MB_RESULT);
 if(err)return fail(m,"FPGA recusou/interrompeu lote; consulte processed e protocolo",err);
 return 1;
}
int mb_read(Mailbox *m,unsigned reg,uint32_t *value){return mb_call(m,MB_READ_REG,0,reg,0,NULL,0,value);}
int mb_write(Mailbox *m,unsigned reg,uint32_t value){return mb_call(m,MB_WRITE_REG,0,reg,value,NULL,0,NULL);}
int mb_wait_idle(Mailbox *m){uint32_t s,e;uint64_t start=m->io.now(m->io.context);for(;;){
 if(!mb_read(m,GPU_STATUS,&s)||!mb_read(m,GPU_ERROR,&e))return 0;
 if(e)return fail(m,"Erro GPU",e);
 if((s&0x19)==0x10)return 1;
 if(m->io.now(m->io.context)-start>=m->timeout_ms)return fail(m,"Timeout aguardando GPU/fila",s);
 m->io.sleep(m->io.context);
}}
int mb_prepare(Mailbox *m,int passive){
 uint32_t mode,s,e;uint64_t start=m->io.now(m->io.context);
 if(!mb_read(m,GPU_CONTROL,&mode)||!mb_write(m,GPU_CONTROL,mode&4))return 0;
 do {if(!mb_read(m,GPU_STATUS,&s))return 0;if(m->io.now(m->io.context)-start>=m->timeout_ms)return fail(m,"CPU/GPU nao parou",s);}while(s&9);
 // Flush pending queue and restart CPU before switching modes.
 if(!mb_write(m,GPU_CONTROL,(mode&4)|2)||!mb_write(m,GPU_CONTROL,4))return 0;
 if(!mb_write(m,0x30,0xf1)||!mb_write(m,0x34,0)||!mb_write(m,GPU_CONTROL,5))return 0;
 do {if(!mb_read(m,GPU_STATUS,&s))return 0;if(m->io.now(m->io.context)-start>=m->timeout_ms)return fail(m,"Nao limpou motor grafico",s);}while((s&0x19)!=0x10);
 if(!mb_write(m,GPU_ERROR,0x7f)||!mb_read(m,GPU_ERROR,&e))return 0;
 if(e)return fail(m,"Erro GPU persistente",e);
 return passive ? 1 : mb_write(m,GPU_CONTROL,0);
}
int mb_commands(Mailbox *m,const Command *c,size_t n){
 uint32_t words[512],e,control;size_t i,j,k;
 if(!mb_read(m,GPU_CONTROL,&control))return 0;
 if(control!=5)return fail(m,"Use demo/init antes de enviar comandos passivos",control);
 for(i=0;i<n;i+=k){k=n-i;if(k>256)k=256;for(j=0;j<k;j++){words[j*2]=c[i+j].port;words[j*2+1]=c[i+j].data;}
  if(!mb_call(m,MB_COMMANDS,(unsigned)k,0,0,words,k*2,NULL)||!mb_read(m,GPU_ERROR,&e))return 0;
  if(e)return fail(m,"Comando grafico invalido",e);
 }return 1;
}
int mb_present_wait(Mailbox *m,uint32_t previous){uint32_t f,e;uint64_t start=m->io.now(m->io.context);for(;;){
 if(!mb_read(m,GPU_FRAME,&f)||!mb_read(m,GPU_ERROR,&e))return 0;
 if(e)return fail(m,"Erro ao apresentar quadro",e);
 if(f!=previous)return mb_wait_idle(m);
 if(m->io.now(m->io.context)-start>=m->timeout_ms)return fail(m,"PRESENT nao concluiu",previous);
 m->io.sleep(m->io.context);
}}

#include "mailbox.h"
#include "scene.h"
#include <stdio.h>
#include <string.h>
#include <assert.h>
typedef struct{uint32_t ram[16384];uint64_t time;unsigned writes,requests;int timeout,corrupt; } Mock;
static uint32_t rd(void *p,unsigned a){Mock *x=p;return x->ram[a/4]^(x->corrupt&&a>=MB_PAYLOAD?1u:0u);}
static void wr(void *p,unsigned a,uint32_t v){Mock *x=p;x->writes++;x->ram[a/4]=v;if(a==MB_REQUEST){x->requests++;
 if(!x->timeout){x->ram[MB_DONE/4]=v;x->ram[MB_RESULT/4]=0x47505533;x->ram[MB_PROCESSED/4]=x->ram[MB_COUNT/4];}}}
static uint64_t now(void *p){return ((Mock*)p)->time;}
static void nap(void *p){((Mock*)p)->time++;}
static void setup(Mock *x,Mailbox *m){MailboxIO io={x,rd,wr,now,nap};memset(x,0,sizeof *x);x->ram[MB_MAGIC/4]=0x48505347;x->ram[MB_ABI/4]=1;assert(mb_open(m,io,10));}
int main(void){Mock x;Mailbox m;uint32_t value,p[4]={0,7,1,9};Command commands[4096];size_t n;
 setup(&x,&m);assert(mb_read(&m,0,&value)&&value==0x47505533);
 assert(mb_call(&m,MB_COMMANDS,2,0,0,p,4,NULL)&&m.processed==2);
 {unsigned old=x.writes;assert(!mb_call(&m,MB_PROGRAM,1025,0,0,p,1025,NULL)&&x.writes==old);}
 setup(&x,&m);x.corrupt=1;assert(!mb_call(&m,MB_PROGRAM,4,0,0,p,4,NULL)&&x.requests==0);
 setup(&x,&m);x.timeout=1;assert(!mb_read(&m,0,&value));assert(x.time==10&&x.requests==1);
 assert(!mb_read(&m,0,&value)&&x.requests==1); // never overwrite/retry an uncertain operation
 setup(&x,&m);x.ram[MB_ERROR/4]=4;assert(!mb_call(&m,MB_COMMANDS,2,0,0,p,4,NULL)&&m.processed==2);
 setup(&x,&m);m.sequence=0xffffffffu;assert(mb_read(&m,0,&value)&&m.sequence==1);
 n=demo_scene(commands,4096);assert(n==2084&&commands[n-1].port==0xf0);assert(demo_scene(commands,1)==0);
 puts("PASS test_mailbox: protocol, limits, readback, timeout, partial error, sequence, C scene");return 0;
}

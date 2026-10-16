#ifndef PBL_MAILBOX_H
#define PBL_MAILBOX_H
#include <stddef.h>
#include <stdint.h>
enum { MB_MAGIC=0x00, MB_ABI=0x04, MB_DONE=0x08, MB_BUSY=0x10,
 MB_ERROR=0x14, MB_RESULT=0x18, MB_PROCESSED=0x1c, MB_GPU_STATUS=0x20,
 MB_GPU_ERROR=0x24, MB_FRAME=0x28, MB_OUT=0x2c, MB_PC=0x30, MB_IR=0x34,
 MB_CONTROL=0x38, MB_REQUEST=0x40, MB_OP=0x48, MB_COUNT=0x4c,
 MB_ARG0=0x50, MB_ARG1=0x54, MB_PAYLOAD=0x100 };
enum { MB_READ_REG=1, MB_WRITE_REG=2, MB_PROGRAM=3, MB_COMMANDS=4 };
enum { GPU_ID=0, GPU_CONTROL=4, GPU_STATUS=8, GPU_FIFO=0x38,
 GPU_FRAME=0x3c, GPU_ERROR=0x40 };
typedef struct { uint32_t port,data; } Command;
typedef struct {
 void *context;
 uint32_t (*read)(void *,unsigned);
 void (*write)(void *,unsigned,uint32_t);
 uint64_t (*now)(void *);
 void (*sleep)(void *);
} MailboxIO;
typedef struct { MailboxIO io; uint32_t sequence,processed; unsigned timeout_ms; char error[200]; } Mailbox;
int mb_open(Mailbox *,MailboxIO,unsigned);
int mb_call(Mailbox *,unsigned,unsigned,uint32_t,uint32_t,const uint32_t *,size_t,uint32_t *);
int mb_read(Mailbox *,unsigned,uint32_t *);
int mb_write(Mailbox *,unsigned,uint32_t);
int mb_prepare(Mailbox *,int passive);
int mb_commands(Mailbox *,const Command *,size_t);
int mb_present_wait(Mailbox *,uint32_t previous);
int mb_wait_idle(Mailbox *);
#endif

#include "scene.h"
// Original lab scene: grass, river, path, two characters and two polygons.
size_t demo_scene(Command *out,size_t capacity){
 static const uint32_t colors[16]={0x101c28,0x285b36,0x4f9142,0x91bc55,
  0x286ca6,0x66bfe3,0xa9b6bf,0x576573,0xd9be7f,0x9c743d,
  0xe35e50,0xffcf62,0xf9edce,0x784899,0xffffff,0x182431};
 size_t n=0;unsigned i,x,y,p,color;
#define CMD(P,D) do{if(n>=capacity)return 0;out[n].port=(P);out[n++].data=(uint32_t)(D);}while(0)
 CMD(0xf1,0);CMD(0,0);CMD(1,0);CMD(2,0);CMD(3,1);
 for(i=0;i<32;i++){CMD(0x10,i);CMD(0x14,0);}
 CMD(0x26,0);for(i=0;i<16;i++)CMD(0x27,colors[i]);
 CMD(0x22,0);
 for(p=0;p<4;p++)for(y=0;y<8;y++)for(x=0;x<8;x++){
  color=p==0?((x*3+y*5)%13==0?3:2):p==1?((y==2||y==6)?5:4):p==2?((x==0||y==0)?7:6):((x+y)%7==0?9:8);
  CMD(0x23,color);
 }
 CMD(0x20,0);
 for(y=0;y<30;y++)for(x=0;x<40;x++){
  p=(x==0||x==39||y==0||y==29)?2:(x>=8&&x<=11)?1:(y>=17&&y<=19)?3:0;CMD(0x21,p);
 }
 CMD(0x24,0);
 for(p=0;p<2;p++)for(y=0;y<16;y++)for(x=0;x<16;x++){
  color=0;
  if(x>=4&&x<=11&&y>=2&&y<=13){color=p?10:13;if(y<6)color=12;if(y==4&&(x==6||x==9))color=15;if(y>10)color=7;}
  CMD(0x25,color);
 }
 CMD(0x10,0);CMD(0x11,136);CMD(0x12,144);CMD(0x13,0);CMD(0x14,0x19);
 CMD(0x10,1);CMD(0x11,248);CMD(0x12,176);CMD(0x13,1);CMD(0x14,0x19);
 CMD(0x30,0);CMD(0x31,192);CMD(0x32,80);CMD(0x33,256);CMD(0x34,128);CMD(0x37,8);CMD(0x38,3);
 CMD(0x30,1);CMD(0x31,184);CMD(0x32,80);CMD(0x33,264);CMD(0x34,80);CMD(0x35,224);CMD(0x36,40);CMD(0x37,10);CMD(0x38,5);
 CMD(0xf0,0);
#undef CMD
 return n;
}

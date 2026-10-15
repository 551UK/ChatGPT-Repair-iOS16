/* 551UK / GPL-3.0. Construct an independent native selection, without editing
 * history JSON or inserting into either HistoryViewModel dictionary.
 * Every private address and layout below is guarded by the framework UUID.
 * Object ownership follows the native 0x36e340 caller's copy/call/destroy path.
 */
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <dlfcn.h>
#import <string.h>
#import <stdint.h>

extern void CG46BridgeString(void *, NSString *, void *);
extern void CG46MakeConversation(void *, void *, void *, void *);
extern void CG46SetString(void *, void *, void *);
extern void CG46GetTitle(void *, void *, void *);
extern void CG46Select(void *, void *, void *);

typedef struct { void *value; uintptr_t state; } CGMeta;
typedef CGMeta (*CGMetaFn)(uintptr_t);
typedef struct {
 void *bufferCopy;
 void (*destroy)(void *, void *);
 void *(*copy)(void *, const void *, void *);
 void *assignCopy;
 void *(*take)(void *, void *, void *);
 void *assignTake;
 unsigned (*getSingleTag)(const void *, unsigned, void *);
 void (*storeSingleTag)(void *, unsigned, unsigned, void *);
 size_t size, stride;
 uint32_t flags, extraInhabitants;
} CGWitness;


static const uint8_t *CG46Image(void) {
 static const uint8_t expected[16]={0xf1,0xcf,0x3b,0x21,0xaa,0xaf,0x3e,0x57,0xbb,0x62,0xce,0x61,0x49,0xaa,0x90,0x40};
 for(uint32_t i=0;i<_dyld_image_count();i++) {
  const char *name=_dyld_get_image_name(i);
  if(!name||!strstr(name,"/ChatGPT.framework/ChatGPT"))continue;
  const struct mach_header_64 *h=(const void *)_dyld_get_image_header(i);
  if(!h||h->magic!=MH_MAGIC_64)return NULL;
  const uint8_t *p=(const void *)(h+1),*end=p+h->sizeofcmds;
  for(uint32_t j=0;j<h->ncmds&&p+sizeof(struct load_command)<=end;j++) {
   const struct load_command *c=(const void *)p;
   if(c->cmdsize<sizeof(*c)||p+c->cmdsize>end)return NULL;
   if(c->cmd==LC_UUID&&c->cmdsize>=sizeof(struct uuid_command))
    return memcmp(((const struct uuid_command *)c)->uuid,expected,16)==0?(const void *)h:NULL;
   p+=c->cmdsize;
  }
 }
 return NULL;
}
static CGWitness *CG46Witness(void *meta) { return meta?((CGWitness **)meta)[-1]:NULL; }
static void *CG46Meta(const uint8_t *b,uintptr_t off) { return ((CGMetaFn)(b+off))(0).value; }
static uint32_t CG46Field(void *meta,unsigned i) { return ((uint32_t *)meta)[4+i]; }
static BOOL CG46Bounds(CGWitness *w) { return w&&w->size>0&&w->size<4096&&(w->flags&255)<16; }

BOOL CG46OpenPin(UIViewController *controller,NSString *identifier,NSString *title) {
 if(!NSThread.isMainThread||![[NSUUID alloc]initWithUUIDString:identifier])return NO;
 const uint8_t *b=CG46Image();
 Class cls=object_getClass(controller);
 Ivar ivar=class_getInstanceVariable(cls,"viewModel");
 id model=ivar?object_getIvar(controller,ivar):nil;
 if(!b||!model||![NSStringFromClass(object_getClass(model)) containsString:@"HistoryViewModel"]) {
  return NO;
 }
 // Field offset used by native HistorySelection dispatch at 0x36e710.
 uintptr_t closureOffset=*(const uintptr_t *)(b+0x2036b88);
 if(closureOffset!=760) {return NO;}
 uintptr_t pair[2];memcpy(pair,(const uint8_t *)(__bridge void *)model+closureOffset,sizeof(pair));
 Dl_info info={0};
 if(!pair[0]||!dladdr((void *)pair[0],&info)||info.dli_fbase!=(const void *)b) {
  return NO;
 }
 void *bridge=dlsym(RTLD_DEFAULT,"$sSS10FoundationE36_unconditionallyBridgeFromObjectiveCySSSo8NSStringCSgFZ");
 void (*enumTag)(void *,void *,unsigned)=dlsym(RTLD_DEFAULT,"swift_storeEnumTagMultiPayload");
 void *(*retain)(void *)=dlsym(RTLD_DEFAULT,"swift_retain");
 void (*release)(void *)=dlsym(RTLD_DEFAULT,"swift_release");
 if(!bridge||!enumTag||!retain||!release){return NO;}
 void *cm=CG46Meta(b,0xd41c38),*hm=CG46Meta(b,0x3729bc);
 void *sm=CG46Meta(b,0x37fa34),*search=CG46Meta(b,0x37ec54);
 void *dm=CG46Meta(b,0x196238c); // imported Foundation.Date metadata thunk
 void *tuple=((void *(*)(const void *))(b+0x33cf1c))(b+0x2036cc0);
 CGWitness *cw=CG46Witness(cm),*hw=CG46Witness(hm),*sw=CG46Witness(sm);
 CGWitness *rw=CG46Witness(search),*dw=CG46Witness(dm);
 if(!CG46Bounds(cw)||!CG46Bounds(hw)||!CG46Bounds(sw)||!CG46Bounds(rw)||!CG46Bounds(dw)||!tuple) {
  return NO;
 }
 size_t co=*(const uintptr_t *)((const uint8_t *)tuple+0x30);
 uint32_t hd=CG46Field(hm,4),hs=CG46Field(hm,5),cd=CG46Field(cm,3);
 if(CG46Field(hm,0)!=0||CG46Field(hm,1)!=16||CG46Field(hm,2)!=32||CG46Field(hm,3)!=49||
    CG46Field(cm,0)!=0||CG46Field(cm,1)!=16||dw->size!=8||hd<50||
    hd+dw->size>hw->size||hs<hd+dw->size||hs+rw->size>hw->size||
    cd+dw->size>cw->size||co<hw->size||co+cw->size>sw->size) {
  return NO;
 }
 uint8_t *selection=calloc(1,sw->stride),*conv=calloc(1,cw->stride);
 if(!selection||!conv){free(selection);free(conv);return NO;}
 // The five configuration fields are optional models/instructions/gizmo + false.
 // All nil representations confirmed by exported default initializers d23534..60.
 uint8_t config[96]={0};uintptr_t words[2];
 CG46BridgeString(bridge,identifier,words);
 CG46MakeConversation((void *)(b+0xd40e28),conv,words,config);
 CG46BridgeString(bridge,identifier,words);
 CG46SetString((void *)(b+0xd41d54),conv,words); // remoteId drives real server load
 CG46BridgeString(bridge,title.length?title:@"Untitled conversation",words);
 CG46SetString((void *)(b+0xd42044),conv,words);
 // Independent HistoryItem with its own owned strings, no borrowed donor state.
 CG46BridgeString(bridge,identifier,selection);
 CG46BridgeString(bridge,identifier,selection+16);
 CG46GetTitle((void *)(b+0xd5cf34),conv,selection+32);
 selection[49]=0; // conversationHasDetails=false; request actual details natively
 dw->copy(selection+hd,conv+cd,dm);
 rw->storeSingleTag(selection+hs,1,1,search); // Optional<HistorySearchResult>.none
 cw->take(selection+co,conv,cm); // move the initialized Conversation into tuple
 free(conv);
 enumTag(selection,sm,1); // HistorySelection.historyItem(item, conversation:)
 if(pair[1])retain((void *)pair[1]);
 
 CG46Select((void *)pair[0],(void *)pair[1],selection);
 if(pair[1])release((void *)pair[1]);
 sw->destroy(selection,sm);
 free(selection);
 
 return YES;
}

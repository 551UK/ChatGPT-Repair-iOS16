"""Validate adapter ABI using synthetic callees, not UIKit/app execution.
Usage: python check_arm64_bridge.py build/DirectPinABI.o
Requires lief and unicorn. Reads the actual compiled machine code.
"""
import sys, struct
import lief
from unicorn import Uc, UC_ARCH_ARM64, UC_MODE_ARM, UC_HOOK_CODE
from unicorn.arm64_const import *
b=lief.MachO.parse(sys.argv[1]).at(0)
s=b.get_section('__text');code=bytes(s.content)
syms={x.name:x.value-s.virtual_address for x in b.symbols if x.name.startswith('_CG46')}
regs=[globals()['UC_ARM64_REG_X'+str(i)] for i in range(29)]
BASE,STUB,DATA,STACK,END=0x100000,0x200000,0x300000,0x400000,0x500000
q=lambda *xs:struct.pack('<'+'Q'*len(xs),*xs)
def run(name,args,expected,returned=(),output=None):
 u=Uc(UC_ARCH_ARM64,UC_MODE_ARM)
 for p in (BASE,STUB,DATA,STACK,END):u.mem_map(p,0x10000)
 u.mem_write(BASE,code);u.mem_write(DATA+0x100,q(0x12345678,0x87654321))
 u.reg_write(UC_ARM64_REG_SP,STACK+0xf000)
 u.reg_write(UC_ARM64_REG_LR,END)
 saved={r:0xa000+i for i,r in enumerate(regs[19:29])}
 for r,v in saved.items():u.reg_write(r,v)
 for i,v in enumerate(args):u.reg_write(regs[i],v)
 called=[]
 def hook(uc,addr,size,user):
  if addr==STUB:
   assert uc.reg_read(UC_ARM64_REG_SP)%16==0,'unaligned stack'
   for r,v in expected.items():assert uc.reg_read(r)==v,(name,r,hex(uc.reg_read(r)),hex(v))
   called.append(1)
   for i,v in enumerate(returned):uc.reg_write(regs[i],v)
   uc.reg_write(UC_ARM64_REG_PC,uc.reg_read(UC_ARM64_REG_LR))
 u.hook_add(UC_HOOK_CODE,hook)
 u.emu_start(BASE+syms[name],END,count=100)
 assert called==[1]
 assert u.reg_read(UC_ARM64_REG_SP)==STACK+0xf000
 assert u.reg_read(UC_ARM64_REG_LR)==END
 for r,v in saved.items():assert u.reg_read(r)==v,(name,'callee-saved',r)
 if output:
  addr,value=output;assert bytes(u.mem_read(addr,len(value)))==value
 print('PASS',name,'arguments, return values, preserved registers, stack')
run('_CG46BridgeString',[STUB,0xaaaa,DATA+0x200],{regs[0]:0xaaaa},[11,22],(DATA+0x200,q(11,22)))
run('_CG46MakeConversation',[STUB,DATA+0x200,DATA+0x100,DATA+0x300],{regs[0]:0x12345678,regs[1]:0x87654321,regs[2]:DATA+0x300,regs[3]:0,regs[4]:0,regs[5]:0,regs[8]:DATA+0x200})
run('_CG46SetString',[STUB,DATA+0x200,DATA+0x100],{regs[0]:0x12345678,regs[1]:0x87654321,regs[20]:DATA+0x200})
run('_CG46GetTitle',[STUB,DATA+0x200,DATA+0x300],{regs[20]:DATA+0x200},[11,22,1],(DATA+0x300,q(11,22)+b'\x01'))
run('_CG46Select',[STUB,0xaaaa,DATA+0x200],{regs[0]:DATA+0x200,regs[20]:0xaaaa})

"""Verify native1 addresses against the user-supplied 1.2024.200 IPA (not bundled)."""
import struct,sys,zipfile
with zipfile.ZipFile(sys.argv[1]) as archive:
    name=next(n for n in archive.namelist() if n.endswith('/ChatGPT.framework/ChatGPT'))
    binary=archive.read(name)
assert struct.unpack_from('<I',binary)[0]==0xfeedfacf
p=32
segments=[]
uuid=None
for _ in range(struct.unpack_from('<I',binary,16)[0]):
    cmd,size=struct.unpack_from('<II',binary,p)
    if cmd==0x1b: uuid=binary[p+8:p+24].hex()
    if cmd==0x19: segments.append(struct.unpack_from('<QQQQ',binary,p+24))
    p+=size
assert uuid=='f1cf3b21aaaf3e57bb62ce6149aa9040'
def data(address,size):
    for va,vs,offset,filesize in segments:
        if va<=address and address+size<=va+filesize:
            return binary[offset+address-va:offset+address-va+size]
    raise AssertionError('address not file-backed')
for address,words in {
    0xd82348:[0xa9ba6ffc,0xa90167fa,0xa9025ff8,0xa90357f6],
    0xd5a628:[0xd10183ff,0xa90357f6,0xa9044ff4,0xa9057bfd],
    0xd5da24:[0xf90016d4,0x90000000,0x9128f000],
}.items():
    assert list(struct.unpack('<'+'I'*len(words),data(address,len(words)*4)))==words
relative,size=struct.unpack('<iI',data(0x207d1c0,8))
assert 0x207d1c0+relative==0xd5da24 and size==160
# Provider calls shared initializer; hooking only the allocating export misses it.
word=struct.unpack('<I',data(0xd8aff8,4))[0]
immediate=word&0x3ffffff
if immediate&0x2000000: immediate-=0x4000000
assert word&0xfc000000==0x94000000 and 0xd8aff8+4*immediate==0xd82348
print('PASS: framework UUID, initializer path, remote-ID getter, async entry/context')

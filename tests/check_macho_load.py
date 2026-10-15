"""Check final signed iOS dylib layout, constructors, and CodeDirectory hashes.
Static validation only: does not simulate iOS dyld, AMFI, or jailbreak injection.
"""
import hashlib, math, struct, sys
from pathlib import Path
import lief

data = Path(sys.argv[1]).read_bytes()
p = lief.parse(sys.argv[1])
page = 0x4000
previous_end = 0
for seg in p.segments:
    assert seg.virtual_address % page == 0, seg.name
    assert seg.file_offset % page == 0, seg.name
    assert seg.virtual_address >= previous_end, seg.name
    assert seg.file_size <= seg.virtual_size, seg.name
    if seg.name != '__LINKEDIT':
        assert seg.virtual_size % page == 0, (seg.name, 'unaligned virtual size')
        assert seg.file_size % page == 0, (seg.name, 'unaligned file size')
    previous_end = seg.virtual_address + seg.virtual_size
text = p.get_section('__text')
assert text.offset >= 32 + p.header.sizeof_cmds
assert p.get_segment('__TEXT').init_protection == 5
init = p.get_section('__mod_init_func')
assert init and init.size == 16
for (addr,) in struct.iter_unpack('<Q', bytes(init.content)):
    assert text.virtual_address <= addr < text.virtual_address + text.size
    assert addr % 4 == 0
print('PASS 16KB segment layout, executable constructor targets, header separation')

sig = bytes(p.code_signature.content)
assert struct.unpack_from('>I', sig)[0] == 0xfade0cc0
directories = 0
for i in range(struct.unpack_from('>I', sig, 8)[0]):
    typ, off = struct.unpack_from('>II', sig, 12 + i * 8)
    if struct.unpack_from('>I', sig, off)[0] != 0xfade0c02:
        continue
    cd = sig[off:]
    hash_off, ident_off, special, count, limit = struct.unpack_from('>IIIII', cd, 16)
    size, algorithm, platform, shift = struct.unpack_from('4B', cd, 36)
    digest = {1: hashlib.sha1, 2: hashlib.sha256}[algorithm]
    assert limit == p.code_signature.data_offset
    assert count == math.ceil(limit / (1 << shift))
    for slot in range(count):
        chunk = data[slot * (1 << shift):min(limit, (slot + 1) * (1 << shift))]
        assert digest(chunk).digest()[:size] == cd[hash_off + slot*size:hash_off + (slot+1)*size], slot
    directories += 1
assert directories
print('PASS every signed code-page hash')

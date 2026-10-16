"""Offline structure checks; device injection and UI still need on-device evidence."""
import hashlib
import pathlib
import struct
import sys

path=pathlib.Path(sys.argv[1])
b=path.read_bytes()
u32=lambda p:struct.unpack_from('<I',b,p)[0]
u64=lambda p:struct.unpack_from('<Q',b,p)[0]
def cstr(p):
    return b[p:b.index(0,p)].decode()
assert u32(0)==0xfeedfacf and u32(4)==0x100000c and u32(12)==6
p=32
sections={}
symbols={}
signature=None
identity=None
for _ in range(u32(16)):
    cmd,size=struct.unpack_from('<II',b,p)
    assert size>=8 and p+size<=len(b)
    if cmd==0x19:
        for i in range(u32(p+64)):
            s=p+72+80*i
            name=b[s:s+16].split(b'\0')[0].decode()
            sections[name]=(u64(s+32),u64(s+40),u32(s+48))
    elif cmd==0xd:
        identity=cstr(p+u32(p+8))
    elif cmd==2:
        offset,count,strings,_=struct.unpack_from('<IIII',b,p+8)
        for i in range(count):
            name,_,_,_,value=struct.unpack_from('<IBBHQ',b,offset+i*16)
            if name:
                symbols[cstr(strings+name)]=value
    elif cmd==0x1d:
        signature=struct.unpack_from('<II',b,p+8)
    elif cmd==0x32:
        assert u32(p+8)==2 and u32(p+12)<=0x110200
    p+=size
assert identity=='@rpath/XAutoTranslate-v13.dylib'
assert signature and '__objc_imageinfo' in sections and '__objc_nlclslist' in sections
assert b'XATAppleBootstrapV13' in b and '_XATScheduleInitialization' in symbols
_,init_size,init_offset=sections['__mod_init_func']
assert init_size>=8
assert symbols['_start'] in [u64(init_offset+i) for i in range(0,init_size,8)]
for forbidden in [b'XADLog', b'XADBootstrap', b'XADStart', b'XATDiagnostic',
                  b'UILongPressGestureRecognizer', b'xadLongPress:',
                  b'UIActivityViewController', b'XAutoTranslate.LogButton.',
                  b'xadOpenLog:', b'XAutoTranslate-bootstrap.log', b'statistics']:
    assert forbidden not in b, forbidden
sigoff,sigsize=signature
sig=b[sigoff:sigoff+sigsize]
assert struct.unpack_from('>I',sig)[0]==0xfade0cc0
verified=0
for i in range(struct.unpack_from('>I',sig,8)[0]):
    _,cd=struct.unpack_from('>II',sig,12+i*8)
    if struct.unpack_from('>I',sig,cd)[0]!=0xfade0c02:
        continue
    hashoff,_,_,pages,limit=struct.unpack_from('>IIIII',sig,cd+16)
    hashsize,hashtype,_,pageexp=struct.unpack_from('>BBBB',sig,cd+36)
    algorithm={1:hashlib.sha1,2:hashlib.sha256,3:hashlib.sha256}[hashtype]
    for page in range(pages):
        data=b[page*(1<<pageexp):min((page+1)*(1<<pageexp),limit)]
        expected=sig[cd+hashoff+page*hashsize:cd+hashoff+(page+1)*hashsize]
        assert algorithm(data).digest()[:hashsize]==expected
    verified+=1
assert verified

assert b'translate.googleapis.com' in b

assert " 已翻译".encode() not in b
assert b"setInfo:for:" in b and b"T1TranslatedStatusViewModel" in b

assert b"getOrCreateInfoFor:" in b

print('PASS arm64/iOS clean dylib: native loaders, signature pages, translation bridge, no translation diagnostics')
print(hashlib.sha256(b).hexdigest(),path.name)

assert b'__xat_payload' not in b and b'__xat_manifest' not in b
assert b'_dlopen' not in symbols and b'dlopen' not in b

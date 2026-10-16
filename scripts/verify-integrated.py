"""Inspect the actual release's embedded signed files without executing them."""
import hashlib,plistlib,struct,sys,zlib
from pathlib import Path

def sections(b):
    assert struct.unpack_from('<I',b)[0]==0xfeedfacf
    assert struct.unpack_from('<I',b,4)[0]==0x100000c
    p=32;out={};commands=[]
    for _ in range(struct.unpack_from('<I',b,16)[0]):
        cmd,size=struct.unpack_from('<II',b,p);commands.append((cmd,p))
        if cmd==0x19:
            for i in range(struct.unpack_from('<I',b,p+64)[0]):
                q=p+72+80*i;name=b[q:q+16].split(b'\0')[0].decode()
                length=struct.unpack_from('<Q',b,q+40)[0];offset=struct.unpack_from('<I',b,q+48)[0]
                out[name]=b[offset:offset+length]
        p+=size
    return out,commands

def signature(b):
    _,commands=sections(b)
    p=next(p for cmd,p in commands if cmd==0x1d)
    offset,length=struct.unpack_from('<II',b,p+8);sig=b[offset:offset+length]
    assert struct.unpack_from('>I',sig)[0]==0xfade0cc0
    checked=0
    for i in range(struct.unpack_from('>I',sig,8)[0]):
        _,cd=struct.unpack_from('>II',sig,12+8*i)
        if struct.unpack_from('>I',sig,cd)[0]!=0xfade0c02:continue
        hashoff,_,_,pages,limit=struct.unpack_from('>IIIII',sig,cd+16)
        hashsize,hashtype,_,pageexp=struct.unpack_from('>BBBB',sig,cd+36)
        algorithm={1:hashlib.sha1,2:hashlib.sha256,3:hashlib.sha256}[hashtype]
        assert limit==offset and pages==(limit+(1<<pageexp)-1)//(1<<pageexp)
        for page in range(pages):
            data=b[page*(1<<pageexp):min((page+1)*(1<<pageexp),limit)]
            assert algorithm(data).digest()[:hashsize]==sig[cd+hashoff+page*hashsize:cd+hashoff+(page+1)*hashsize]
        checked+=1
    assert checked

b=Path(sys.argv[1]).read_bytes();s,_=sections(b);signature(b)
manifest=plistlib.loads(s['__xat_manifest']);compressed=s['__xat_payload']
assert hashlib.sha256(compressed).hexdigest()==manifest['payloadSHA256']
raw=zlib.decompress(compressed);assert len(raw)==manifest['uncompressedSize']
files=plistlib.loads(raw);assert set(files)==set(manifest['files'])
for name,data in files.items():
    assert not name.startswith('/') and '..' not in name.split('/') and '\\' not in name
    expected=manifest['files'][name]
    assert len(data)==expected['size'] and hashlib.sha256(data).hexdigest()==expected['sha256']
    if name.endswith('.dylib'):signature(data)
assert b'@loader_path/libellekit.dylib' in files['BHTwitter.dylib']
assert b'@executable_path/Frameworks/libellekit.dylib' not in files['BHTwitter.dylib']
assert 'BHTwitter.bundle/Info.plist' in files and 'BHTwitter.bundle/Acknowledgements.rtf' in files
for token in [b'XATTranslationModuleController',b'xatOpenTranslationModule',b'setupSections',b'dlopen',b'__xat_manifest']:
    assert token in b,token
print('PASS integrated release:',len(files),'embedded files, SHA256, nested signature pages, relative ElleKit dependency, settings module')

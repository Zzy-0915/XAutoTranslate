"""Verify the real installable archive, dependency closure and signed Mach-O bytes."""
import hashlib,struct,sys,zipfile,plistlib
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


with zipfile.ZipFile(sys.argv[1]) as z:
    files={name:z.read(name) for name in z.namelist()}
assert len(files)==27
for name,data in files.items():
    assert not name.startswith('/') and '..' not in name.split('/') and '\\' not in name
    if name.endswith('.dylib'):signature(data)
expected={'XAutoTranslate-v13.dylib','BHTwitter.dylib','XATKit.dylib','libbhFLEX.dylib'}
assert {n for n in files if n.endswith('.dylib')}==expected
graph={}
for name in sorted(expected):
    b=files[name];s,commands=sections(b);assert '__xat_payload' not in s and '__xat_manifest' not in s
    deps=[]
    for cmd,p in commands:
        if cmd not in [0xc,0x80000018,0x8000001f]:continue
        start=p+struct.unpack_from('<I',b,p+8)[0];dep=b[start:b.index(0,start)].decode();deps.append(dep)
        if dep.startswith('@loader_path/'):
            assert dep.removeprefix('@loader_path/') in files,(name,dep)
        elif dep.startswith('@rpath/libswift'):pass
        else:assert dep.startswith(('/usr/lib/','/System/Library/')),(name,dep)
    graph[name]=deps
assert '@loader_path/BHTwitter.dylib' in graph['XAutoTranslate-v13.dylib']
assert '@loader_path/libbhFLEX.dylib' in graph['XAutoTranslate-v13.dylib']
assert '@loader_path/XATKit.dylib' in graph['BHTwitter.dylib']
assert 'BHTwitter.bundle/Info.plist' in files and 'BHTwitter.bundle/Acknowledgements.rtf' in files
assert b'dlopen' not in files['XAutoTranslate-v13.dylib']
assert b'xatOpenTranslationModule' in files['XAutoTranslate-v13.dylib']
assert plistlib.loads(files['BHTwitter.bundle/Info.plist'])
print('PASS injection archive: 27 install-time files, four signed libraries, relative dependency closure, resources, no runtime executable extraction or dlopen')

for name,data in files.items():
    if name.endswith('.strings'):
        assert b'NFB-X' not in data,name
for language in ['en','zh_CN']:
    assert b'Zzy-X' in files['BHTwitter.bundle/'+language+'.lproj/Localizable.strings']
for removed in ['开关改动在完全退出','基于 v10 精简版']:
    assert removed.encode() not in files['XAutoTranslate-v13.dylib']
assert b'XATSettingsNavigation' in files['XAutoTranslate-v13.dylib']
print('PASS v13 display branding, shared native settings cells and removed translation footnotes')

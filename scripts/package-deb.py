"""Create an injection-only Debian archive from the already verified install ZIP."""
from pathlib import Path, PurePosixPath
import gzip,io,sys,tarfile,zipfile

out=Path(sys.argv[1]);source=out/'XAutoTranslate-v15-Inject.zip'
destination=out/'XAutoTranslate-v15-Inject.deb'
with zipfile.ZipFile(source) as z:
    files={name:z.read(name) for name in z.namelist()}
assert len(files)==27 and sum(name.endswith('.dylib') for name in files)==4

def tar_entry(name,data=b'',directory=False):
    assert len(name.encode('utf-8'))<100
    item=tarfile.TarInfo(name);item.mode=0o755 if directory or name.endswith('.dylib') else 0o644
    item.type=tarfile.DIRTYPE if directory else tarfile.REGTYPE;item.size=len(data)
    header=bytearray(item.tobuf(format=tarfile.USTAR_FORMAT))
    # Some injectors recognize a bundle directory by an exact '.bundle' suffix.
    # POSIX type=5 does not require a trailing slash; retain the exact name.
    if directory:
        header[:100]=name.encode().ljust(100,b'\0');header[148:156]=b' '*8
        header[148:156]=(f'{sum(header):06o}\0 ').encode()
    return bytes(header)+data+b'\0'*((-len(data))%512)

bundle='Library/Application Support/BHT/BHTwitter.bundle'
data_tar=tar_entry(bundle,directory=True)
for name,data in sorted(files.items()):
    assert not PurePosixPath(name).is_absolute() and '..' not in PurePosixPath(name).parts
    installed='Library/MobileSubstrate/DynamicLibraries/'+name if name.endswith('.dylib') else 'Library/Application Support/BHT/'+name
    data_tar+=tar_entry(installed,data)
data_tar+=b'\0'*1024
control=('Package: dev.zzy0915.xautotranslate.inject\nVersion: 15.0.0\n'
         'Architecture: iphoneos-arm64\nName: XAutoTranslate NFB Injection Bundle\n'
         'Maintainer: Zzy-0915\nSection: Tweaks\n'
         'Description: Import into the app injector; not a system-wide tweak installation.\n').encode()
control_tar=tar_entry('control',control)+b'\0'*1024

def ar_entry(name,data):
    header=(name+'/').ljust(16)+'0'.ljust(12)+'0'.ljust(6)+'0'.ljust(6)+'100644'.ljust(8)+str(len(data)).ljust(10)+'`\n'
    assert len(header)==60
    return header.encode('ascii')+data+(b'\n' if len(data)%2 else b'')

parts={'debian-binary':b'2.0\n','control.tar.gz':gzip.compress(control_tar,mtime=0),
       'data.tar.gz':gzip.compress(data_tar,compresslevel=9,mtime=0)}
destination.write_bytes(b'!<arch>\n'+b''.join(ar_entry(name,data) for name,data in parts.items()))

# Reopen actual output and emulate the injector's flattening/bundle discovery.
raw=destination.read_bytes();assert raw[:8]==b'!<arch>\n';p=8;actual={}
while p<len(raw):
    header=raw[p:p+60];assert len(header)==60 and header[58:]==b'`\n'
    name=header[:16].decode().strip().removesuffix('/');size=int(header[48:58])
    actual[name]=raw[p+60:p+60+size];p+=60+size+(size%2)
assert p==len(raw) and actual==parts
assert gzip.decompress(actual['data.tar.gz'])[:100].split(b'\0')[0].endswith(b'.bundle')
with tarfile.open(fileobj=io.BytesIO(actual['control.tar.gz']),mode='r:gz') as tar:
    assert tar.getnames()==['control']
    assert tar.extractfile('control').read()==control
recovered={};bundles=[]
with tarfile.open(fileobj=io.BytesIO(actual['data.tar.gz']),mode='r:gz') as tar:
    for item in tar:
        assert not item.name.startswith('/') and '..' not in PurePosixPath(item.name).parts
        assert item.isdir() or item.isfile()
        if item.isdir() and item.name.endswith('.bundle'):bundles.append(item.name)
        elif item.isfile():
            data=tar.extractfile(item).read()
            if item.name.endswith('.dylib'):
                assert item.mode==0o755
                recovered[PurePosixPath(item.name).name]=data
            else:
                matches=[b for b in bundles if item.name.startswith(b+'/')]
                assert len(matches)==1,item.name
                recovered[PurePosixPath(matches[0]).name+'/'+item.name[len(matches[0])+1:]]=data
assert recovered==files
assert not any(name.endswith(('preinst','postinst','prerm','postrm')) for name in actual)
print('PASS DEB: standard ar + gzip/tar, exact 27 signed ZIP files, four dylibs, bundle discovery, executable modes, no installation scripts')
print(destination)

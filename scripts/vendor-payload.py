"""Verify user-supplied vendor bytes; prepare signed libraries and resources for installation."""
from pathlib import Path, PurePosixPath
import base64, hashlib, json, plistlib, subprocess, sys, zipfile, io, struct

root=Path(__file__).resolve().parent.parent
vendor=root/'Vendor'
manifest=json.loads((vendor/'manifest.json').read_text())
digest=lambda b:hashlib.sha256(b).hexdigest()
chunks=[]
for part in manifest['parts']:
    raw=base64.b64decode((vendor/part['path']).read_text().strip(),validate=True)
    assert digest(raw)==part['sha256'],part['path']
    chunks.append(raw)
archive=b''.join(chunks)
assert digest(archive)==manifest['archive_sha256']
with zipfile.ZipFile(io.BytesIO(archive)) as z:
    assert set(z.namelist())==set(manifest['files'])
    files={}
    for name,expected in manifest['files'].items():
        path=PurePosixPath(name)
        assert not path.is_absolute() and '..' not in path.parts and '\\' not in name
        data=z.read(name)
        assert len(data)==expected['size'] and digest(data)==expected['sha256'],name
        files[name]=data
for name,data in files.items():
    if name.endswith('.dylib'):
        assert struct.unpack_from('<II',data)==(0xfeedfacf,0x100000c),name
print('PASS vendor archive: exact IPA-derived files, digests, arm64 slices and safe paths')
if '--verify-only' in sys.argv:
    sys.exit(0)
out=root/'output'; staging=out/'vendor';staging.mkdir(parents=True,exist_ok=True)
for name,data in files.items():
    path=staging/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)
# Change display branding only; preserve localization keys, feature text and credits.
for strings in (staging/'BHTwitter.bundle').rglob('*.strings'):
    raw=strings.read_bytes()
    encoding='utf-16' if raw.startswith((b'\xff\xfe',b'\xfe\xff')) else 'utf-8-sig' if raw.startswith(b'\xef\xbb\xbf') else 'utf-8'
    content=raw.decode(encoding)
    if 'NFB-X' in content:strings.write_bytes(content.replace('NFB-X','Zzy-X').encode(encoding))
kit=staging/'XATKit.dylib'
(staging/'libellekit.dylib').rename(kit)
subprocess.run(['install_name_tool','-id','@rpath/XATKit.dylib',str(kit)],check=True)
subprocess.run(['install_name_tool','-change','@executable_path/Frameworks/libellekit.dylib','@loader_path/XATKit.dylib',str(staging/'BHTwitter.dylib')],check=True)
subprocess.run(['install_name_tool','-id','@loader_path/BHTwitter.dylib',str(staging/'BHTwitter.dylib')],check=True)
subprocess.run(['install_name_tool','-id','@loader_path/libbhFLEX.dylib',str(staging/'libbhFLEX.dylib')],check=True)
for name in ['XATKit.dylib','libbhFLEX.dylib','BHTwitter.dylib']:
    path=staging/name
    subprocess.run(['codesign','--force','--sign','-','--identifier','dev.zzy0915.XAutoTranslate.vendor.'+path.stem,'--timestamp=none',str(path)],check=True)
    subprocess.run(['codesign','--verify','--strict',str(path)],check=True)
    subprocess.run(['xcrun','lipo',str(path),'-verify_arch','arm64'],check=True)
    files[name]=path.read_bytes()
print('PASS prepared install-time libraries and bundle:',str(staging))


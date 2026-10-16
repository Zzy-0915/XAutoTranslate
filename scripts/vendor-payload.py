"""Verify user-supplied vendor bytes; prepare signed, self-contained runtime payload."""
from pathlib import Path, PurePosixPath
import base64, hashlib, json, plistlib, subprocess, sys, zipfile, io, zlib

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
print('PASS vendor archive: exact IPA-derived files, digests, arm64 slices and safe paths')
if '--verify-only' in sys.argv:
    sys.exit(0)
out=root/'output'; staging=out/'vendor';staging.mkdir(parents=True,exist_ok=True)
for name,data in files.items():
    path=staging/name;path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)
subprocess.run(['install_name_tool','-change','@executable_path/Frameworks/libellekit.dylib','@loader_path/libellekit.dylib',str(staging/'BHTwitter.dylib')],check=True)
for name in ['libellekit.dylib','libbhFLEX.dylib','BHTwitter.dylib']:
    path=staging/name
    subprocess.run(['codesign','--force','--sign','-','--identifier','dev.zzy0915.XAutoTranslate.vendor.'+path.stem,'--timestamp=none',str(path)],check=True)
    subprocess.run(['codesign','--verify','--strict',str(path)],check=True)
    subprocess.run(['xcrun','lipo',str(path),'-verify_arch','arm64'],check=True)
    files[name]=path.read_bytes()
raw=plistlib.dumps(files,fmt=plistlib.FMT_BINARY,sort_keys=True)
payload=zlib.compress(raw,9)
runtime={'format':1,'uncompressedSize':len(raw),'payloadSHA256':digest(payload),
         'files':{name:{'size':len(data),'sha256':digest(data)} for name,data in files.items()}}
(out/'embedded-payload.bin').write_bytes(payload)
(out/'embedded-manifest.bin').write_bytes(plistlib.dumps(runtime,fmt=plistlib.FMT_BINARY,sort_keys=True))
print('PASS prepared signed payload:',len(files),'files,',len(payload),'compressed bytes')

"""The injector installs all archive members before the app launches."""
from pathlib import Path
import sys,zipfile

out=Path(sys.argv[1]);main=out/'XAutoTranslate-v13.dylib';vendor=out/'vendor'
entries={main.name:main}
for path in vendor.rglob('*'):
    if path.is_file():entries[path.relative_to(vendor).as_posix()]=path
assert len(entries)==27
assert 'XATKit.dylib' in entries and 'libellekit.dylib' not in entries
with zipfile.ZipFile(out/'XAutoTranslate-v13-Inject.zip','w',zipfile.ZIP_DEFLATED,compresslevel=9) as z:
    for name,path in sorted(entries.items()):
        info=zipfile.ZipInfo(name);info.compress_type=zipfile.ZIP_DEFLATED
        info.external_attr=(0o100755 if name.endswith('.dylib') else 0o100644)<<16
        z.writestr(info,path.read_bytes())
print('Prepared complete injection archive:',out/'XAutoTranslate-v13-Inject.zip')

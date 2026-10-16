"""Smoke-test the actual presentation adapter with UIKit and a native-controller double."""
from pathlib import Path
import json,plistlib,subprocess,shutil,re

root=Path(__file__).resolve().parent.parent
def run(args,**kwargs):return subprocess.run(args,check=True,**kwargs)
sdk=subprocess.check_output(['xcrun','--sdk','iphonesimulator','--show-sdk-path'],text=True).strip()
app=root/'build/SettingsUITests.app';app.mkdir(parents=True,exist_ok=True)
identifier='dev.zzy0915.XAutoTranslate.UITests'
(app/'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':identifier,'CFBundleExecutable':'SettingsUITests','CFBundleName':'SettingsUITests','CFBundlePackageType':'APPL','CFBundleVersion':'1','CFBundleShortVersionString':'1.0','MinimumOSVersion':'17.2','LSRequiresIPhoneOS':True,'UIDeviceFamily':[1],'UILaunchScreen':{}}))
shutil.copytree(root/'output/vendor/BHTwitter.bundle',app/'BHTwitter.bundle',dirs_exist_ok=True)
run(['xcrun','--sdk','iphonesimulator','clang','-arch','arm64','-isysroot',sdk,'-mios-simulator-version-min=17.2','-fobjc-arc','-fobjc-exceptions','-fblocks','-Wall','-Wextra','-Werror','-I'+str(root/'Sources'),str(root/'tests/SettingsUITests.m'),str(root/'Sources/XIntegratedPlugin.m'),str(root/'Sources/XSettingsAppearance.m'),'-framework','Foundation','-framework','UIKit','-framework','CoreGraphics','-o',str(app/'SettingsUITests')])
run(['codesign','--force','--sign','-','--timestamp=none',str(app)])
inventory=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','--json'],text=True))
devices=[d for runtime,items in inventory['devices'].items() if re.search(r'iOS-(\d+)-(\d+)',runtime) and tuple(map(int,re.search(r'iOS-(\d+)-(\d+)',runtime).groups()))>=(17,2) for d in items if d['isAvailable'] and 'iPhone' in d['name']]
assert devices,'No available iPhone simulator runtime for UIKit smoke test'
device=next((d for d in devices if d['state']=='Booted'),devices[0]);udid=device['udid']
if device['state']!='Booted':run(['xcrun','simctl','boot',udid])
run(['xcrun','simctl','bootstatus',udid,'-b'],timeout=240)
run(['xcrun','simctl','install',udid,str(app)])
result=subprocess.run(['xcrun','simctl','launch','--terminate-running-process','--console',udid,identifier],text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=120)
print(result.stdout[-14000:])
assert result.returncode==0 and 'PASS UIKit settings:' in result.stdout,'UIKit settings smoke test failed'


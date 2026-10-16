# De-identified public copy. Private executed source has a separate receipt hash.
from pathlib import Path
import subprocess,os
p=Path(os.environ['RUNSTIR_VALIDATION_ROOT']);b=Path(os.environ['RUNSTIR_VALIDATION_BUILD_PRODUCTS'])
repo=Path(os.environ['RUNSTIR_VALIDATION_REPOSITORY'])
objs=[b/(n+'.o') for n in ['Core','AndroidKit','EnvironmentKit','SimulatorKit','Subprocess','_SubprocessCShims','SystemPackage','CSystem','Yams','CYaml','Logging']]
cmd=['/usr/bin/xcrun','swiftc','-parse-as-library','-swift-version','6','-I',str(b),'-module-cache-path',str(p/'harness-module-cache')]
for package,target in [('swift-subprocess','_SubprocessCShims'),('swift-system','CSystem'),('Yams','CYaml')]:
 m=next((repo/'.build/checkouts'/package/'Sources'/target).rglob('module.modulemap'))
 cmd+=['-I',str(m.parent.resolve())]
cmd+=[str(p/'harness/main.swift')]+[str(x) for x in objs]+['-o',str(p/'harness/owned204')]
r=subprocess.run(cmd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
(p/'logs/harness-compile.log').write_text(r.stdout);print(r.returncode,r.stdout[-2300:]);raise SystemExit(r.returncode)

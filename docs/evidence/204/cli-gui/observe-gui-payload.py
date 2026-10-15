# De-identified public helper copy. Resolve the documented aliases before use.
from pathlib import Path
import os,time,stat,json,sys
P=Path('/OWNED_ROOT');name,action=sys.argv[1:3];dst=P/'evidence'/name;dst.mkdir();start=time.monotonic();result=None
while time.monotonic()-start<150:
    for f in (P/'gui-sdk').glob('.runstir-install-*/payload.zip'):
        s=f.lstat()
        if stat.S_ISREG(s.st_mode) and s.st_uid==os.getuid() and s.st_size>0:
            result={'action':action,'payload':str(f),'originalMode':stat.S_IMODE(s.st_mode),'bytesObserved':s.st_size,'at':time.time(),'seconds':round(time.monotonic()-start,3),'stage':'normal official payload download','regular':True,'ownedUID':s.st_uid}
            if action=='controlled-chmod-000':f.chmod(0)
            break
    if result:break
    time.sleep(.02)
if result is None:result={'action':'observation-timeout','seconds':round(time.monotonic()-start,3)}
(dst/'observation.json').write_text(json.dumps(result,indent=2));print(json.dumps(result,indent=2))

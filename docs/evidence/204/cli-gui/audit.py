# De-identified public helper copy. Resolve the documented aliases before use.
from pathlib import Path
import os,json,hashlib,subprocess,time
P=Path('/OWNED_ROOT')
os.environ['GIT_OPTIONAL_LOCKS']='0'  # Public replay avoids index-refresh writes.
def sha(f):return hashlib.sha256(f.read_bytes()).hexdigest()
def stat(f):
    s=f.lstat();return {'mode':s.st_mode,'size':s.st_size,'mtime_ns':s.st_mtime_ns,'uid':s.st_uid,'gid':s.st_gid,'ino':s.st_ino,'link':os.readlink(f) if f.is_symlink() else None}
def tree(root):
    root=Path(root);out={}
    for base,dirs,files in os.walk(root,followlinks=False):
        for name in dirs+files:
            f=Path(base)/name
            try:out[str(f.relative_to(root))]=stat(f)
            except FileNotFoundError:out[str(f.relative_to(root))]={'missingDuringRead':True}
    return out
before=json.loads((P/'evidence/shared-before.json').read_text());after={r:tree(r) for r in before['trees']};deltas={r:[k for k in sorted(set(v)|set(after[r])) if v.get(k)!=after[r].get(k)] for r,v in before['trees'].items()}
leases=Path('/USER_HOME/Library/Caches/dev.runstir/leases');current={f.name:{'stat':stat(f),'sha256':sha(f)} for f in leases.iterdir() if f.is_file()};changedLeases=[k for k,v in before['leases'].items() if current.get(k)!=v];newLeases={k:v for k,v in current.items() if k not in before['leases']}
sources={};packages={};licenses={}
for kind in ['cli','gui','license']:
    src=P/(kind+'-source');old=json.loads((P/'evidence'/(kind+'-tracked-before.json')).read_text());files={r:{'sha256':sha(src/r),'mode':(src/r).stat().st_mode} for r in old['tracked']};sources[kind]={'trackedFileCount':len(files),'trackedBytesModesSame':files==old['tracked'],'indexBytesSame':sha(src/'.git/index')==old['index'],'sourceSHA':subprocess.check_output(['/usr/bin/git','-C',str(src),'rev-parse','HEAD'],text=True).strip(),'status':subprocess.check_output(['/usr/bin/git','-C',str(src),'status','--porcelain=v1','--untracked-files=no'],text=True)}
    sdk=P/(kind+'-sdk');packages[kind]={'present':{r:(sdk/r).exists() for r in ['build-tools/34.0.0','platforms/android-35']},'scratchRemaining':[str(x) for x in sdk.glob('.runstir-*')]}
    if kind!='license':
        root=sdk/'build-tools/34.0.0';files={str(f.relative_to(root)):{'sha256':sha(f),'mode':f.stat().st_mode} for f in root.rglob('*') if f.is_file() and not f.is_symlink()};old=json.loads((P/'evidence'/(kind+'-buildtools-completed.json')).read_text());packages[kind].update({'firstCompletedPackageFiles':len(files),'firstCompletedBytesModesSame':files==old})
        originals=Path('/ORIGINAL_SDK/licenses');licenses[kind]={'records':len(list(originals.iterdir())),'samePublicLicenseRecordBytesAsOriginal':all((sdk/'licenses'/f.name).read_bytes()==f.read_bytes() for f in originals.iterdir() if f.is_file()),'newAcceptance':False}
pref=Path('/USER_HOME/Library/Preferences/dev.runstir.gui.plist');prefBaseline=json.loads((P/'evidence/gui-isolation-before.json').read_text());processes=subprocess.check_output(['/bin/ps','-axo','pid,ppid,comm'],text=True).splitlines();owned=[r for r in processes if str(P) in r and any(x in r for x in ['/Runstir','/bin/mobile','/emulator/','/platform-tools/adb'])]
token=Path('/USER_HOME/.emulator_console_auth_token');report={'at':time.time(),'sharedTrees':{r:{'observedEntries':len(v),'metadataDeltaCount':len(deltas[r]),'deltaPaths':deltas[r]} for r,v in before['trees'].items()},'consoleTokenStatSame':(stat(token) if token.exists() else None)==before['token'],'existingLeaseCount':len(before['leases']),'changedExistingLeaseRecords':changedLeases,'newLeaseRecords':newLeases,'sources':sources,'packages':packages,'licenses':licenses,'originalGUIPlist':{'sameHashSinceIsolationBaseline':sha(pref)==prefBaseline['sha256'],'sameMtimeSinceIsolationBaseline':pref.stat().st_mtime_ns==prefBaseline['mtime_ns'],'initialSharedChangeRetained':True},'ownedRuntimeOrCLIProcesses':owned,'limits':['shared SDK/cache full bytes not collected','whole HOME immutability not proved','tree root directory stat was not captured','ephemeral T and LaunchServices/validation preference OS writes outside SDK/cache audit scope']}
(P/'evidence/shared-after.json').write_text(json.dumps(after));(P/'evidence/final-preservation.json').write_text(json.dumps(report,indent=2));print(json.dumps({k:report[k] for k in ['sharedTrees','consoleTokenStatSame','changedExistingLeaseRecords','sources','packages','originalGUIPlist','ownedRuntimeOrCLIProcesses']},indent=2))

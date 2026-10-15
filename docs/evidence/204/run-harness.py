from pathlib import Path
import subprocess,json,time,sys
p=Path('/Volumes/P41_USB4/Developer/validation/goal204-sdk-install-20261015');name=sys.argv[1];attempt=p/'evidence'/name;attempt.mkdir()
env={'HOME':str(p/'home'),'TMPDIR':str(p/'tmp')+'/', 'PATH':'/usr/bin:/bin:/usr/sbin:/sbin','LANG':'en_US.UTF-8'}
cmd=['/usr/bin/sandbox-exec','-f',str(p/'owned-writes.sb'),str(p/'harness/owned204')]+sys.argv[2:]
(attempt/'command.json').write_text(json.dumps({'command':cmd,'environment':env,'head':subprocess.check_output(['/usr/bin/git','-C','/Volumes/P41_USB4/Developer/worktrees/codex/goal204-sdk-contract/MobileEnvironment','rev-parse','HEAD'],text=True).strip(),'mode':'public PreparationExecution.run / typed Android context with custom owned leases'}))
t=time.monotonic()
with (p/'logs'/(name+'.json')).open('x') as out,(p/'logs'/(name+'.stderr')).open('x') as err:
 r=subprocess.run(cmd,cwd=p/'source',env=env,stdout=out,stderr=err,timeout=180)
(attempt/'result.json').write_text(json.dumps({'exitCode':r.returncode,'seconds':round(time.monotonic()-t,3)}))
print(r.returncode,round(time.monotonic()-t,3))

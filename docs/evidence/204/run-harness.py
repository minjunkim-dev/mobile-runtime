# De-identified public copy. Private executed source has a separate receipt hash.
from pathlib import Path
import subprocess,json,time,sys,os
p=Path(os.environ['RUNSTIR_VALIDATION_ROOT']);name=sys.argv[1];attempt=p/'evidence'/name;attempt.mkdir()
env={key:os.environ[key] for key in ['RUNSTIR_VALIDATION_ROOT','RUNSTIR_VALIDATION_JAVA_HOME','RUNSTIR_VALIDATION_USER']}
env.update({'HOME':str(p/'home'),'TMPDIR':str(p/'tmp')+'/', 'PATH':'/usr/bin:/bin:/usr/sbin:/sbin','LANG':'en_US.UTF-8'})
cmd=['/usr/bin/sandbox-exec','-f',str(p/'owned-writes.sb'),str(p/'harness/owned204')]+sys.argv[2:]
(attempt/'command.json').write_text(json.dumps({'command':cmd,'environment':env,'head':subprocess.check_output(['/usr/bin/git','-C',os.environ['RUNSTIR_VALIDATION_REPOSITORY'],'rev-parse','HEAD'],text=True).strip(),'mode':'public PreparationExecution.run / typed Android context with custom owned leases'}))
t=time.monotonic()
with (p/'logs'/(name+'.json')).open('x') as out,(p/'logs'/(name+'.stderr')).open('x') as err:
 r=subprocess.run(cmd,cwd=p/'source',env=env,stdout=out,stderr=err,timeout=180)
(attempt/'result.json').write_text(json.dumps({'exitCode':r.returncode,'seconds':round(time.monotonic()-t,3)}))
print(r.returncode,round(time.monotonic()-t,3))

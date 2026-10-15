# De-identified public helper copy. Resolve the documented aliases before use.
from pathlib import Path
import sys,subprocess,json,time
from importlib.machinery import SourceFileLoader
helper=SourceFileLoader('owned_cli',str(Path(__file__).with_name('run-cli.py'))).load_module()
P=helper.P;kind=sys.argv[1];name=sys.argv[2];dst=P/'evidence'/name;dst.mkdir()
cmd=['/usr/bin/sandbox-exec','-f',str(P/(kind+'-writes.sb')),str(P/'Runstir204Validation.app/Contents/MacOS/Runstir')]
env=helper.environment(kind)
with (dst/'stdout.txt').open('x') as out,(dst/'stderr.txt').open('x') as err:
    proc=subprocess.Popen(cmd,env=env,cwd=P/(kind+'-source'),stdout=out,stderr=err)
(dst/'launch.json').write_text(json.dumps({'command':cmd,'environment':env,'pid':proc.pid,'source':'70cb2877b259690832cec686e925087ddb1c1d01','at':time.time(),'persistentLauncher':True},indent=2));print(proc.pid,flush=True)
status=proc.wait();(dst/'exit.json').write_text(json.dumps({'exitCode':status,'at':time.time()},indent=2));print('GUI child exit',status,flush=True)

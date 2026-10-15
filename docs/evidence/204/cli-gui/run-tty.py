# De-identified public helper copy. Resolve the documented aliases before use.
from pathlib import Path
import os, pty, select, json, time, re, signal, sys
from importlib.machinery import SourceFileLoader
helper=SourceFileLoader('owned_cli',str(Path(__file__).with_name('run-cli.py'))).load_module()
P=helper.P;dst=P/'evidence'/sys.argv[1];dst.mkdir();kind='cli'
cmd=['/usr/bin/sandbox-exec','-f',str(P/'cli-writes.sb'),str(P/'bin/mobile'),'setup','--project',str(P/'cli-source')]
env=helper.environment(kind);(dst/'command.json').write_text(json.dumps({'command':cmd,'environment':env,'source':'70cb2877b259690832cec686e925087ddb1c1d01','tty':True,'packagesBefore':helper.packages(kind)},indent=2))
start=time.monotonic();pid,fd=pty.fork()
if pid==0:
    os.chdir(P/'cli-source');os.execve(cmd[0],cmd,env)
text='';approved=False;cancelled=False;actions=[];status=None
with (dst/'transcript.txt').open('x') as log:
    while True:
        if select.select([fd],[],[],.02)[0]:
            try: data=os.read(fd,65536)
            except OSError: data=b''
            if data:
                s=data.decode(errors='replace');text+=s;log.write(s);log.flush()
        if not approved:
            match=re.search(r'Type this exact plan-id to approve, or press Return to stop: ([0-9a-f]{64})',text)
            if match:
                os.write(fd,(match[1]+'\n').encode());approved=True;actions.append({'action':'typed-exact-plan-id','id':match[1],'seconds':round(time.monotonic()-start,3)})
        if approved and not cancelled:
            for payload in (P/'cli-sdk').glob('.runstir-install-*/payload.zip'):
                if payload.exists() and payload.stat().st_size>0:
                    actions.append({'action':'TTY-Ctrl-C','bytesObserved':payload.stat().st_size,'payload':str(payload),'seconds':round(time.monotonic()-start,3)});os.write(fd,b'\x03');cancelled=True;break
        got,status=os.waitpid(pid,os.WNOHANG)
        if got:break
        if time.monotonic()-start>180:
            os.kill(pid,signal.SIGTERM);actions.append({'action':'deadline-SIGTERM'});_,status=os.waitpid(pid,0);break
os.close(fd);result={'exitCode':os.waitstatus_to_exitcode(status),'seconds':round(time.monotonic()-start,3),'actions':actions,'packagesAfter':helper.packages(kind),'cancelledStateVisible':'setup: cancelled' in text}
(dst/'result.json').write_text(json.dumps(result,indent=2));print(json.dumps(result,indent=2))

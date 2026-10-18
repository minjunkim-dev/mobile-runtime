import os, pathlib, subprocess, sys, signal, json
log=pathlib.Path(sys.argv[1]);fd=os.open(log,os.O_WRONLY|os.O_CREAT|os.O_TRUNC,0o600)
child=subprocess.Popen(sys.argv[2:],stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
log.with_suffix(log.suffix+'.pid').write_text(str(child.pid)+'\n')
def terminate(sig,frame):
    if child.poll() is None: child.send_signal(sig)
signal.signal(signal.SIGTERM,terminate);signal.signal(signal.SIGINT,terminate)
redacted=0
with os.fdopen(fd,'wb',buffering=0) as out:
    for line in child.stdout:
        if b'Sending adb public key [' in line or b'androidboot.qemu.adb.pubkey=' in line:
            out.write(b'[REDACTED: emulator startup echoed an existing ADB public key]\n');redacted+=1
        else: out.write(line)
code=child.wait()
log.with_suffix(log.suffix+'.receipt.json').write_text(json.dumps({'pid':child.pid,'exitCode':code,'publicKeyLinesRedactedBeforePersistence':redacted},indent=2)+'\n')
sys.exit(code if code>=0 else 128-code)

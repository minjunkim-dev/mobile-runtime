# De-identified public helper copy. Resolve the documented aliases before use.
from pathlib import Path
import os, subprocess, json, time, sys, signal, hashlib, stat

P = Path('/OWNED_ROOT')
JDK = '/JDK17_HOME'

def environment(kind):
    return {'HOME': '/USER_HOME', 'USER': 'VALIDATION_USER', 'LOGNAME': 'VALIDATION_USER', 'LANG': 'en_US.UTF-8',
            'PATH': JDK + '/bin:/usr/bin:/bin:/usr/sbin:/sbin', 'JAVA_HOME': JDK,
            'JAVA_TOOL_OPTIONS': '-Duser.home=' + str(P/'home') + ' -Djava.io.tmpdir=' + str(P/'tmp') + ' -Djava.util.prefs.userRoot=' + str(P/'home/prefs'),
            'ANDROID_HOME': str(P/(kind+'-sdk')), 'ANDROID_SDK_ROOT': str(P/(kind+'-sdk')),
            'ANDROID_USER_HOME': str(P/'android-user'), 'ANDROID_EMULATOR_HOME': str(P/'android-emulator'),
            'ANDROID_AVD_HOME': str(P/'avd'), 'GRADLE_USER_HOME': str(P/(kind+'-gradle')),
            'TMPDIR': str(P/'tmp')+'/', 'XDG_CACHE_HOME': str(P/'home/cache')}

def packages(kind):
    sdk=P/(kind+'-sdk')
    return {r: (sdk/r).exists() for r in ['build-tools/34.0.0', 'platforms/android-35']}

if __name__ == '__main__':
    name, kind = sys.argv[1:3]
    args=sys.argv[3:]; cancel='--observe-cancel' in args; fault='--permission-fault' in args
    if cancel: args.remove('--observe-cancel')
    if fault: args.remove('--permission-fault')
    dst=P/'evidence'/name; dst.mkdir()
    cmd=['/usr/bin/sandbox-exec','-f',str(P/(kind+'-writes.sb')),str(P/'bin/mobile'),'setup','--project',str(P/(kind+'-source'))]+args
    env=environment(kind)
    (dst/'command.json').write_text(json.dumps({'command':cmd,'environment':env,'source':'70cb2877b259690832cec686e925087ddb1c1d01','packagesBefore':packages(kind)},indent=2))
    t=time.monotonic(); action=None
    with (dst/'stdout.txt').open('x') as out,(dst/'stderr.txt').open('x') as err:
        proc=subprocess.Popen(cmd,cwd=P/(kind+'-source'),env=env,stdout=out,stderr=err)
        deadline=time.monotonic()+180
        while proc.poll() is None:
            if (cancel or fault) and action is None:
                for payload in (P/(kind+'-sdk')).glob('.runstir-install-*/payload.zip'):
                    info=payload.lstat()
                    if stat.S_ISREG(info.st_mode) and info.st_uid==os.getuid() and info.st_size>0:
                        action={'action':'SIGINT' if cancel else 'controlled-chmod-000','pid':proc.pid,'payload':str(payload),'originalMode':stat.S_IMODE(info.st_mode),'bytesObserved':info.st_size,'seconds':round(time.monotonic()-t,3),'time':time.time()}
                        if cancel: proc.send_signal(signal.SIGINT)
                        else: payload.chmod(0)
                        break
            if time.monotonic()>deadline:
                proc.send_signal(signal.SIGTERM); action={'action':'deadline-SIGTERM','pid':proc.pid}; proc.wait(timeout=30);break
            time.sleep(.02)
        if fault and action:
            payload=Path(action['payload']);action['cleanupRemovedPayload']=not payload.exists()
            if payload.exists(): payload.chmod(action['originalMode']);action['modeRestored']=True
        result={'exitCode':proc.returncode,'seconds':round(time.monotonic()-t,3),'packagesAfter':packages(kind),'action':action}
    try:
        data=json.loads((dst/'stdout.txt').read_text());result.update({'state':data['operation']['state'],'planID':data.get('plan',{}).get('id'),'completed':data['operation'].get('completed'),'remaining':data['operation'].get('remaining'),'steps':[{k:s.get(k) for k in ['id','kind','target']} for s in data.get('plan',{}).get('steps',[])]})
    except (ValueError,KeyError,TypeError): pass
    (dst/'result.json').write_text(json.dumps(result,indent=2)); print(json.dumps(result,indent=2))

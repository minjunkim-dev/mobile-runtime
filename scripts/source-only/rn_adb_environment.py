"""ADR34 pure-memory model. No collector, runtime adapter, or actual grant."""

SELECTED_ADB = '/Volumes/P41_USB4/Developer/sdk/android/platform-tools/adb'
SOURCE_PIN = 'fb529d52f4485c1fdbe6208f20af6578493e1ca7'
VARIABLES = ('HOME', 'ADB_SERVER_SOCKET', 'ANDROID_ADB_SERVER_ADDRESS',
             'ANDROID_ADB_SERVER_PORT', 'ADB_VENDOR_KEYS')
ROLES = ('foreground-server', 'devices-client')


def environment_state(state, value=None):
    if type(state) is not str or state not in ('UNRECORDED', 'ABSENT', 'EMPTY', 'VALUE'):
        raise ValueError('INVALID_ENV_STATE')
    if state in ('UNRECORDED', 'ABSENT'):
        valid = value is None
    elif state == 'EMPTY':
        valid = type(value) is str and value == ''
    else:
        valid = type(value) is str and 0 < len(value) <= 4096 and '\x00' not in value
    if not valid:
        raise ValueError('INVALID_ENV_VALUE')
    return {'state': state, 'value': value}


def declaration():
    result = {name: environment_state('ABSENT') for name in VARIABLES}
    result['HOME'] = environment_state('VALUE', '/Users/swifty')
    result['ADB_SERVER_SOCKET'] = environment_state('VALUE', 'tcp:localhost:5037')
    return result


def _model_id(value):
    if type(value) is not str or not value.startswith('model://') or not 8 < len(value) <= 128:
        raise ValueError('MODEL_ID_REQUIRED')


def _snapshot(value):
    if type(value) is not dict or set(value) != set(VARIABLES):
        raise ValueError('INVALID_ENV_SCHEMA')
    result = {}
    for name in VARIABLES:
        entry = value[name]
        if type(entry) is not dict or set(entry) != {'state', 'value'}:
            raise ValueError('INVALID_ENV_SCHEMA')
        result[name] = environment_state(entry['state'], entry['value'])
    return result


def model_receipt(run_id, call_id, role, fixture_binary, launcher_values=None,
                  other_environment_preserved=None):
    """Evaluate synthetic launcher input; never attest an actual launch."""
    _model_id(run_id)
    _model_id(call_id)
    if type(role) is not str or role not in ROLES:
        raise ValueError('OUT_OF_SCOPE_ROLE')
    if type(fixture_binary) is not dict or set(fixture_binary) != {'path', 'sha256', 'size'}:
        raise ValueError('INVALID_BINARY_SCHEMA')
    _model_id(fixture_binary['path'])
    digest = fixture_binary['sha256']
    if (type(digest) is not str or len(digest) != 64
            or any(c not in '0123456789abcdef' for c in digest)
            or type(fixture_binary['size']) is not int or fixture_binary['size'] <= 0):
        raise ValueError('INVALID_BINARY_IDENTITY')
    if other_environment_preserved is not None and type(other_environment_preserved) is not bool:
        raise ValueError('INVALID_PRESERVATION_STATE')
    passed = (_snapshot(launcher_values) if launcher_values is not None else
              {name: environment_state('UNRECORDED') for name in VARIABLES})
    declared = declaration()
    unknown = any(entry['state'] == 'UNRECORDED' for entry in passed.values())
    mismatch = any(entry['state'] != 'UNRECORDED' and entry != declared[name]
                   for name, entry in passed.items())
    if mismatch or other_environment_preserved is False:
        verdict = 'MODEL_STOP'
    elif unknown or other_environment_preserved is None:
        verdict = 'MODEL_UNKNOWN'
    else:
        verdict = 'MODEL_MATCH'
    predicted = passed == declared
    arguments = (['-L', 'tcp:localhost:5037', 'server', 'nodaemon']
                 if role == 'foreground-server' else ['devices'])
    return {
        'kind': 'MODEL-ONLY', 'runId': run_id, 'callId': call_id, 'role': role,
        'argvDeclaration': [SELECTED_ADB] + arguments,
        'binaryIdentity': {'fixture': dict(fixture_binary), 'actualStatus': 'UNKNOWN',
                           'installedSourceCorrespondence': 'UNKNOWN'},
        'environment': {'declaration': declared,
                        'launcherPassedModel': passed, 'actualLauncherPassed': 'UNKNOWN',
                        'actualReceived': 'UNKNOWN'},
        'otherEnvironmentPreservedModel': other_environment_preserved,
        'actualOtherEnvironmentPreserved': 'UNKNOWN',
        'sourcePrediction': {'pin': SOURCE_PIN, 'kind': 'CONDITIONAL',
                             'home': '/Users/swifty' if predicted else 'UNKNOWN',
                             'socketSpec': 'tcp:localhost:5037' if predicted else 'UNKNOWN'},
        'historicalOriginalEnvironment': 'UNKNOWN', 'modelVerdict': verdict,
        'actualVerdict': 'STOP', 'actualCompatibility': 'UNKNOWN',
        'actualAuthority': False, 'actualReadiness': False, 'actualLease': None,
    }

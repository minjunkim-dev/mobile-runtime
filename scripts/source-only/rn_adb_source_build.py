"""ADR33 pure-memory source/build model; no collector or actual attestation."""

LINKS = {
    'ARTIFACT_AND_ADB_TO_BUILD': (('artifactDigest', 'archiveAdbDigest'), 'buildIdentity'),
    'BUILD_TO_SOURCE': (('buildIdentity',), 'sourceRevision'),
    'BUILD_TO_DEPENDENCIES': (('buildIdentity',), 'dependencies'),
    'BUILD_TO_TOOLCHAIN': (('buildIdentity',), 'toolchain'),
    'BUILD_TO_INPUTS': (('buildIdentity',), 'buildInputs'),
}
SUBJECTS = ('platform', 'archiveMember', 'artifactDigest', 'archiveAdbDigest',
            'buildIdentity', 'sourceRevision', 'dependencies', 'toolchain', 'buildInputs')
CLASSES = ('CANDIDATE', 'DECLARATION', 'DIRECT_EVIDENCE')


def _model_id(value):
    return type(value) is str and value.startswith('model://') and 8 < len(value) <= 128


def _copy(value, depth=0):
    # Only built-in fixture values: do not invoke caller-defined copy/iteration hooks.
    if depth > 12:
        raise ValueError('MODEL_INPUT_TOO_DEEP')
    if value is None or type(value) in (bool, int):
        return value
    if type(value) is str and len(value) <= 4096:
        return value
    if type(value) is list and len(value) <= 128:
        return [_copy(item, depth + 1) for item in value]
    if (type(value) is dict and len(value) <= 32
            and all(type(key) is str and len(key) <= 128 for key in value)):
        return {key: _copy(item, depth + 1) for key, item in value.items()}
    raise ValueError('BUILTIN_MODEL_INPUT_REQUIRED')


def _shape(value, keys):
    return type(value) is dict and set(value) == set(keys)


def _digest(value):
    if not _shape(value, ('algorithm', 'value')):
        return False
    size = {'sha1': 40, 'sha256': 64}.get(value['algorithm']) if type(value['algorithm']) is str else None
    return (size is not None and type(value['value']) is str and len(value['value']) == size
            and all(c in '0123456789abcdef' for c in value['value']))


def _known(name, value):
    if name in ('artifactDigest', 'archiveAdbDigest'):
        return _digest(value)
    if name == 'buildIdentity':
        return (_shape(value, ('namespace', 'value'))
                and _model_id(value['namespace']) and _model_id(value['value']))
    if name in ('dependencies', 'toolchain', 'buildInputs'):
        return (type(value) is list and bool(value) and all(_model_id(x) for x in value)
                and len(set(value)) == len(value))
    return _model_id(value)


def _scope(value):
    return (_shape(value, ('subjectId', 'epoch'))
            and all(_model_id(x) for x in value.values()))


def _policy(value):
    return (_shape(value, ('revision', 'path', 'digest'))
            and _model_id(value['revision']) and _model_id(value['path']) and _digest(value['digest']))


def _evidence_ready(entry, link_id, scope, subjects):
    keys = ('evidenceId', 'locator', 'readScope', 'observedAt', 'recordedAt',
            'contentDigest', 'rawBytesPreserved', 'materialKind', 'evidenceClass', 'modelBinding')
    if not _shape(entry, keys):
        return False
    binding = entry['modelBinding']
    metadata = {'linkId', 'scope', 'platform', 'archiveMember', 'publisher'}
    if type(binding) is not dict or not metadata <= set(binding) <= metadata | {'from', 'to'}:
        return False
    build = subjects['buildIdentity']
    return (_scope(scope) and _known('buildIdentity', build)
            and _model_id(entry['evidenceId']) and _model_id(entry['locator'])
            and entry['locator'].startswith(build['namespace'] + '/')
            and type(entry['readScope']) is list and link_id in entry['readScope']
            and all(type(x) is str and x in LINKS for x in entry['readScope'])
            and entry['observedAt'] == scope['epoch'] and _model_id(entry['recordedAt'])
            and _digest(entry['contentDigest']) and entry['rawBytesPreserved'] is False
            and entry['materialKind'] == 'SYNTHETIC' and binding['linkId'] == link_id
            and binding['scope'] == scope and binding['publisher'] == build['namespace']
            and _known('platform', subjects['platform']) and binding['platform'] == subjects['platform']
            and _known('archiveMember', subjects['archiveMember'])
            and binding['archiveMember'] == subjects['archiveMember'])


def _link(link_id, records, evidence, scope, policy, subjects):
    from_names, to_name = LINKS[link_id]
    expected_from = {name: subjects[name] for name in from_names}
    expected_to = {to_name: subjects[to_name]}
    reasons, coverage, classes, refs = [], set(), set(), []
    failed = False
    if len(records) != 1:
        reasons.append('MISSING_OR_AMBIGUOUS_LINK')
    if not _policy(policy):
        reasons.append('UNKNOWN_POLICY')
    if not all(_known(name, subjects[name]) for name in (*from_names, to_name)):
        reasons.append('UNKNOWN_SUBJECT')
    for record in records:
        required = {'linkId', 'from', 'to', 'evidenceRefs', 'evidenceClass'}
        allowed = required | {'linkVerdict', 'modelLinkVerdict', 'reason'}
        if not required <= set(record) <= allowed:
            reasons.append('INVALID_LINK_SCHEMA')
        if record.get('from') != expected_from or record.get('to') != expected_to:
            reasons.append('AMBIGUOUS_LINK_TARGET')
        if record.get('evidenceClass') not in CLASSES:
            reasons.append('UNKNOWN_LINK_EVIDENCE_CLASS')
        reference_ids = record.get('evidenceRefs')
        if type(reference_ids) is not list or not reference_ids or not all(_model_id(x) for x in reference_ids):
            reasons.append('MISSING_OR_INVALID_EVIDENCE_REF')
            continue
        if len(set(reference_ids)) != len(reference_ids):
            reasons.append('AMBIGUOUS_EVIDENCE_REF')
        refs.extend(reference_ids)
        for reference in reference_ids:
            matches = [e for e in evidence if type(e) is dict and e.get('evidenceId') == reference]
            if len(matches) != 1:
                reasons.append('MISSING_OR_AMBIGUOUS_EVIDENCE')
            for entry in matches:
                evidence_class = entry.get('evidenceClass')
                if type(evidence_class) is not str or evidence_class not in CLASSES:
                    reasons.append('UNKNOWN_EVIDENCE_CLASS')
                    continue
                classes.add(evidence_class)
                if record.get('evidenceClass') != evidence_class:
                    reasons.append('AMBIGUOUS_EVIDENCE_CLASS')
                if evidence_class != 'DIRECT_EVIDENCE':
                    reasons.append('CANDIDATE_OR_DECLARATION_ONLY')
                    continue
                if not _evidence_ready(entry, link_id, scope, subjects):
                    reasons.append('UNKNOWN_OR_OUT_OF_SCOPE_EVIDENCE')
                    continue
                binding = entry['modelBinding']
                sources, target = binding.get('from'), binding.get('to')
                if type(sources) is not dict or not sources or not set(sources) <= set(from_names):
                    reasons.append('INCOMPLETE_BINDING_SOURCE')
                if not _shape(target, (to_name,)):
                    reasons.append('INCOMPLETE_BINDING_TARGET')
                elif not _known(to_name, target[to_name]):
                    reasons.append('UNKNOWN_BINDING_TARGET')
                elif _known(to_name, subjects[to_name]) and target != expected_to:
                    failed = True
                    reasons.append('CONTRADICTORY_TARGET')
                elif not _known(to_name, subjects[to_name]):
                    reasons.append('UNKNOWN_SUBJECT')
                for name in from_names:
                    if type(sources) is not dict or name not in sources:
                        continue
                    value = sources[name]
                    if not _known(name, value) or not _known(name, subjects[name]):
                        reasons.append('UNKNOWN_BINDING_SOURCE')
                    elif value != subjects[name]:
                        failed = True
                        reasons.append('CONTRADICTORY_SOURCE')
                    elif target == expected_to:
                        coverage.add(name)
    if coverage != set(from_names):
        reasons.append('INCOMPLETE_DIRECT_COVERAGE')
    verdict = 'FAIL' if failed else 'UNKNOWN' if reasons else 'PASS'
    evidence_class = next((c for c in reversed(CLASSES) if c in classes), None)
    return {'linkId': link_id, 'from': expected_from, 'to': expected_to, 'evidenceRefs': refs,
            'evidenceClass': evidence_class, 'linkVerdict': 'UNKNOWN',
            'modelLinkVerdict': verdict, 'reason': sorted(set(reasons))}


def model_receipt(receipt_id, scope=None, policy_ref=None, subjects=None, evidence=None, links=None):
    """Derive MODEL-ONLY verdicts from synthetic bindings; never verify official records."""
    if not _model_id(receipt_id):
        raise ValueError('MODEL_ID_REQUIRED')
    scope, policy_ref, subjects, evidence, links = _copy([scope, policy_ref, subjects, evidence, links])
    if subjects is not None and (type(subjects) is not dict or not set(subjects) <= set(SUBJECTS)):
        raise ValueError('OUT_OF_SCOPE_SUBJECT_SCHEMA')
    subjects = {name: subjects.get(name) if subjects is not None else None for name in SUBJECTS}
    evidence = [] if evidence is None else evidence
    links = [] if links is None else links
    if type(evidence) is not list or type(links) is not list:
        raise ValueError('MODEL_RECORD_LIST_REQUIRED')
    result = [_link(link_id, [r for r in links if type(r) is dict and r.get('linkId') == link_id],
                    evidence, scope, policy_ref, subjects) for link_id in LINKS]
    unknown_links = any(type(r) is not dict or type(r.get('linkId')) is not str
                        or r['linkId'] not in LINKS for r in links)
    verdicts = [r['modelLinkVerdict'] for r in result]
    verdict = ('FAIL' if 'FAIL' in verdicts else 'UNKNOWN'
               if 'UNKNOWN' in verdicts or unknown_links else 'PASS')
    return {
        'schemaVersion': 1, 'receiptId': receipt_id, 'kind': 'MODEL-ONLY',
        'scope': scope, 'policyRef': policy_ref, 'subjects': subjects,
        'evidence': evidence, 'inputLinks': links, 'links': result,
        'modelVerdict': verdict,
        'modelStop': 'FAILURE_STOP' if verdict == 'FAIL' else 'UNKNOWN_STOP' if verdict == 'UNKNOWN' else None,
        'fullSourceBuildVerdict': 'UNKNOWN', 'actualVerdict': 'STOP',
        'actualAuthority': False, 'actualReadiness': False, 'actualLease': None,
    }

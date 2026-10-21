"""Synthetic ADR33 checks; python3 -B; no official records or actual resources."""

import ast
import copy
import unittest
from pathlib import Path

from rn_adb_source_build import LINKS, model_receipt
from rn_adb_environment import declaration, model_receipt as environment_receipt


def fixture():
    scope = {'subjectId': 'model://archive', 'epoch': 'model://historical-observation'}
    policy = {'revision': 'model://policy-revision', 'path': 'model://adr33',
              'digest': {'algorithm': 'sha256', 'value': 'c' * 64}}
    subjects = {
        'platform': 'model://darwin-arm64', 'archiveMember': 'model://platform-tools/adb',
        'artifactDigest': {'algorithm': 'sha256', 'value': 'a' * 64},
        'archiveAdbDigest': {'algorithm': 'sha256', 'value': 'b' * 64},
        'buildIdentity': {'namespace': 'model://publisher', 'value': 'model://exact-build'},
        'sourceRevision': 'model://source-revision', 'dependencies': ['model://dependency-revision'],
        'toolchain': ['model://toolchain-revision'], 'buildInputs': ['model://build-input-revision'],
    }
    evidence, links = [], []
    for link_id, (from_names, to_name) in LINKS.items():
        source = {name: copy.deepcopy(subjects[name]) for name in from_names}
        target = {to_name: copy.deepcopy(subjects[to_name])}
        evidence_id = 'model://evidence/' + link_id
        evidence.append({
            'evidenceId': evidence_id, 'locator': 'model://publisher/' + link_id,
            'readScope': [link_id], 'observedAt': scope['epoch'],
            'recordedAt': 'model://later-recording',
            'contentDigest': {'algorithm': 'sha256', 'value': 'd' * 64},
            'rawBytesPreserved': False, 'materialKind': 'SYNTHETIC',
            'evidenceClass': 'DIRECT_EVIDENCE',
            'modelBinding': {'linkId': link_id, 'from': copy.deepcopy(source),
                             'to': copy.deepcopy(target), 'scope': copy.deepcopy(scope),
                             'platform': subjects['platform'], 'archiveMember': subjects['archiveMember'],
                             'publisher': subjects['buildIdentity']['namespace']},
        })
        links.append({'linkId': link_id, 'from': source, 'to': target,
                      'evidenceRefs': [evidence_id], 'evidenceClass': 'DIRECT_EVIDENCE'})
    return {'scope': scope, 'policy_ref': policy, 'subjects': subjects, 'evidence': evidence, 'links': links}


class SourceBuildModelTests(unittest.TestCase):
    def evaluate(self, data=None, expected='UNKNOWN'):
        result = model_receipt('model://receipt', **(data or {}))
        self.assertEqual(result['modelVerdict'], expected)
        self.assertEqual(result['modelStop'], {'PASS': None, 'FAIL': 'FAILURE_STOP', 'UNKNOWN': 'UNKNOWN_STOP'}[expected])
        self.assertEqual(result['kind'], 'MODEL-ONLY')
        self.assertEqual(result['fullSourceBuildVerdict'], 'UNKNOWN')
        self.assertEqual(result['actualVerdict'], 'STOP')
        self.assertIs(result['actualAuthority'], False)
        self.assertIs(result['actualReadiness'], False)
        self.assertIsNone(result['actualLease'])
        self.assertEqual([r['linkId'] for r in result['links']], list(LINKS))
        self.assertTrue(all(r['linkVerdict'] == 'UNKNOWN' for r in result['links']))
        return result

    def test_complete_model_never_attests_actual_proof(self):
        r = self.evaluate(fixture(), 'PASS')
        self.assertTrue(all(x['modelLinkVerdict'] == 'PASS' for x in r['links']))
        self.assertTrue(all(e['rawBytesPreserved'] is False for e in r['evidence']))

    def test_empty_input_retains_all_missing_links(self):
        r = self.evaluate()
        self.assertTrue(all(x['evidenceRefs'] == [] and x['modelLinkVerdict'] == 'UNKNOWN' for x in r['links']))

    def test_each_missing_link_or_subject_stops(self):
        for link_id in LINKS:
            with self.subTest(link=link_id):
                data = fixture()
                data['links'] = [r for r in data['links'] if r['linkId'] != link_id]
                self.evaluate(data)
        for name in fixture()['subjects']:
            with self.subTest(subject=name):
                data = fixture()
                del data['subjects'][name]
                self.evaluate(data)

    def test_artifact_and_adb_require_both_direct_bindings(self):
        data = fixture()
        artifact = data['evidence'][0]
        adb = copy.deepcopy(artifact)
        adb['evidenceId'] = 'model://adb-binding'
        del artifact['modelBinding']['from']['archiveAdbDigest']
        del adb['modelBinding']['from']['artifactDigest']
        self.evaluate(data)
        data['evidence'].append(adb)
        data['links'][0]['evidenceRefs'].append(adb['evidenceId'])
        self.evaluate(data, 'PASS')

    def test_candidate_and_declaration_are_not_proof_or_contradiction(self):
        for evidence_class in ('CANDIDATE', 'DECLARATION'):
            with self.subTest(evidence_class=evidence_class):
                data = fixture()
                for entry in data['evidence']:
                    entry['evidenceClass'] = evidence_class
                    entry['modelBinding']['to'] = {'buildIdentity': {'namespace': 'model://other', 'value': 'model://other-build'}}
                for link in data['links']:
                    link['evidenceClass'] = evidence_class
                self.evaluate(data)

    def test_candidate_link_cannot_be_promoted_by_a_different_class(self):
        data = fixture()
        data['links'][0]['evidenceClass'] = 'CANDIDATE'
        self.evaluate(data)

    def test_direct_label_and_pass_claim_alone_do_not_pass(self):
        data = fixture()
        for entry in data['evidence']:
            del entry['modelBinding']
        for link in data['links']:
            link['linkVerdict'] = 'PASS'
            link['modelLinkVerdict'] = 'PASS'
            link['reason'] = 'claimed success'
        r = self.evaluate(data)
        self.assertEqual(r['inputLinks'], data['links'])

    def test_failure_wins_over_missing_link_and_preserves_input(self):
        data = fixture()
        data['links'].pop()
        data['evidence'][1]['modelBinding']['to']['sourceRevision'] = 'model://contradictory-source'
        before = copy.deepcopy(data)
        r = self.evaluate(data, 'FAIL')
        self.assertEqual(r['evidence'], before['evidence'])
        self.assertEqual(r['inputLinks'], before['links'])
        self.assertEqual(data, before)
        self.assertIn('CONTRADICTORY_TARGET', r['links'][1]['reason'])

    def test_known_digest_or_build_contradiction_stops(self):
        for name in ('artifactDigest', 'archiveAdbDigest'):
            with self.subTest(digest=name):
                data = fixture()
                data['evidence'][0]['modelBinding']['from'][name]['value'] = 'e' * 64
                self.evaluate(data, 'FAIL')
        data = fixture()
        data['evidence'][0]['modelBinding']['to']['buildIdentity']['value'] = 'model://other-build'
        self.evaluate(data, 'FAIL')

    def test_missing_or_duplicate_references_are_unknown(self):
        for change in ('missing', 'duplicate-id', 'duplicate-ref', 'duplicate-link'):
            with self.subTest(change=change):
                data = fixture()
                if change == 'missing':
                    data['links'][0]['evidenceRefs'] = ['model://missing-evidence']
                elif change == 'duplicate-id':
                    data['evidence'].append(copy.deepcopy(data['evidence'][0]))
                elif change == 'duplicate-ref':
                    data['links'][0]['evidenceRefs'] *= 2
                else:
                    data['links'].append(copy.deepcopy(data['links'][0]))
                self.evaluate(data)

    def test_wrong_origin_platform_member_time_or_read_scope_is_unknown(self):
        for change in ('locator', 'publisher', 'platform', 'archiveMember', 'scope', 'observedAt', 'readScope'):
            with self.subTest(change=change):
                data = fixture()
                entry = data['evidence'][0]
                if change == 'locator':
                    entry['locator'] = 'model://publisher-impostor/record'
                elif change in ('publisher', 'platform', 'archiveMember'):
                    entry['modelBinding'][change] = 'model://other'
                elif change == 'scope':
                    entry['modelBinding']['scope']['epoch'] = 'model://other-time'
                elif change == 'observedAt':
                    entry['observedAt'] = 'model://new-observation'
                else:
                    entry['readScope'] = ['BUILD_TO_SOURCE']
                self.evaluate(data)

    def test_duplicate_id_does_not_hide_an_applicable_contradiction(self):
        data = fixture()
        duplicate = copy.deepcopy(data['evidence'][0])
        duplicate['modelBinding']['from']['artifactDigest']['value'] = 'f' * 64
        data['evidence'].append(duplicate)
        r = self.evaluate(data, 'FAIL')
        self.assertIn('MISSING_OR_AMBIGUOUS_EVIDENCE', r['links'][0]['reason'])
        self.assertIn('CONTRADICTORY_SOURCE', r['links'][0]['reason'])
        self.assertEqual(r['evidence'], data['evidence'])
        duplicate['modelBinding']['platform'] = 'model://other-platform'
        self.evaluate(data)

    def test_incomplete_binding_does_not_hide_known_contradictions(self):
        for missing in ('from', 'to'):
            with self.subTest(missing=missing):
                data = fixture()
                binding = data['evidence'][1]['modelBinding']
                if missing == 'from':
                    binding['to']['sourceRevision'] = 'model://contradictory-source'
                else:
                    binding['from']['buildIdentity']['value'] = 'model://contradictory-build'
                del binding[missing]
                self.evaluate(data, 'FAIL')

    def test_malformed_evidence_and_bindings_never_pass(self):
        for key in fixture()['evidence'][0]:
            for value in (None, False, 0, [], {}, 'invalid'):
                original = fixture()['evidence'][0][key]
                if type(value) is type(original) and value == original:
                    continue
                with self.subTest(field=key, value=value):
                    data = fixture()
                    data['evidence'][0][key] = value
                    self.evaluate(data)
        for key in fixture()['evidence'][0]['modelBinding']:
            for value in (None, False, 0, [], {}, 'invalid'):
                with self.subTest(binding=key, value=value):
                    data = fixture()
                    data['evidence'][0]['modelBinding'][key] = value
                    self.evaluate(data)

    def test_unknown_metadata_and_identity_do_not_crash_or_pass(self):
        for change in ('contentDigest', 'modelBinding', 'recordedAt', 'rawBytesPreserved', 'materialKind'):
            with self.subTest(change=change):
                data = fixture()
                data['evidence'][0][change] = None
                self.evaluate(data)
        for name in ('scope', 'policy_ref'):
            with self.subTest(envelope=name):
                data = fixture()
                data[name] = None
                self.evaluate(data)
        data = fixture()
        data['evidence'][0]['modelBinding']['from']['artifactDigest']['algorithm'] = []
        self.evaluate(data)

    def test_extra_partial_binding_cannot_hide_a_contradiction(self):
        data = fixture()
        extra = copy.deepcopy(data['evidence'][0])
        extra['evidenceId'] = 'model://contradiction'
        extra['modelBinding']['from']['artifactDigest']['value'] = 'f' * 64
        del extra['modelBinding']['from']['archiveAdbDigest']
        data['evidence'].append(extra)
        data['links'][0]['evidenceRefs'].append(extra['evidenceId'])
        data['links'][0]['linkVerdict'] = 'PASS'
        self.evaluate(data, 'FAIL')

    def test_environment_match_and_prediction_do_not_supply_build_proof(self):
        for preserved in (True, False, None):
            with self.subTest(preserved=preserved):
                env = environment_receipt('model://run', 'model://call', 'devices-client',
                                          {'path': 'model://adb', 'sha256': 'a' * 64, 'size': 1},
                                          declaration(), preserved)
                self.assertNotEqual(env['sourcePrediction']['home'], 'UNKNOWN')
                self.evaluate({'evidence': [env]})

    def test_input_output_and_subsequent_calls_are_isolated(self):
        data = fixture()
        original = copy.deepcopy(data)
        result = self.evaluate(data, 'PASS')
        data['evidence'][0]['modelBinding']['from']['artifactDigest']['value'] = 'f' * 64
        self.assertEqual(result['evidence'], original['evidence'])
        result['evidence'][1]['modelBinding']['to']['sourceRevision'] = 'model://changed'
        self.evaluate(original, 'PASS')

    def test_non_model_ids_and_non_builtin_objects_are_rejected_without_hooks(self):
        for receipt_id in ('actual-run', '/actual/receipt', 'model://'):
            with self.subTest(receipt_id=receipt_id), self.assertRaises(ValueError):
                model_receipt(receipt_id)
        class Unsafe:
            def __deepcopy__(self, memo):
                raise AssertionError('caller hook executed')
        with self.assertRaises(ValueError):
            model_receipt('model://receipt', evidence=[Unsafe()])
        cyclic = []
        cyclic.append(cyclic)
        with self.assertRaises(ValueError):
            model_receipt('model://receipt', evidence=cyclic)

    def test_helper_has_no_io_or_adapter(self):
        tree = ast.parse(Path(__file__).with_name('rn_adb_source_build.py').read_text())
        self.assertFalse(any(isinstance(n, (ast.Import, ast.ImportFrom)) for n in ast.walk(tree)))
        calls = {n.func.id for n in ast.walk(tree) if isinstance(n, ast.Call) and isinstance(n.func, ast.Name)}
        self.assertFalse(calls & {'open', 'exec', 'eval', 'compile', '__import__', 'input', 'getattr'})
        attributes = {n.func.attr for n in ast.walk(tree) if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute)}
        self.assertLessEqual(attributes, {'startswith', 'get', 'values', 'items', 'append', 'extend', 'add'})


if __name__ == '__main__':
    unittest.main()

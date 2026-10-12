"""Synthetic ADR34 checks. Run with python3 -B; no actual environment reads."""

import ast
import unittest
from pathlib import Path

from rn_adb_environment import declaration, environment_state, model_receipt, ROLES, VARIABLES


class EnvironmentModelTests(unittest.TestCase):
    def receipt(self, role='devices-client', values=None, preserved=None, binary=None):
        return model_receipt('model://run', 'model://call', role,
                             binary or {'path': 'model://adb', 'sha256': 'a' * 64, 'size': 1},
                             values, preserved)

    def test_match_never_grants_actual_authority(self):
        for role in ROLES:
            with self.subTest(role=role):
                r = self.receipt(role, declaration(), True)
                self.assertEqual(r['modelVerdict'], 'MODEL_MATCH')
                self.assertEqual(r['actualVerdict'], 'STOP')
                self.assertFalse(r['actualAuthority'])
                self.assertFalse(r['actualReadiness'])
                self.assertIsNone(r['actualLease'])
                self.assertEqual(r['environment']['actualReceived'], 'UNKNOWN')
                self.assertEqual(r['environment']['actualLauncherPassed'], 'UNKNOWN')
                self.assertEqual(r['binaryIdentity']['actualStatus'], 'UNKNOWN')
                self.assertEqual(r['binaryIdentity']['installedSourceCorrespondence'], 'UNKNOWN')
                self.assertEqual(r['actualOtherEnvironmentPreserved'], 'UNKNOWN')
                self.assertEqual(r['historicalOriginalEnvironment'], 'UNKNOWN')
                self.assertEqual(r['actualCompatibility'], 'UNKNOWN')
                self.assertEqual(r['sourcePrediction']['socketSpec'], 'tcp:localhost:5037')
                expected = (['-L', 'tcp:localhost:5037', 'server', 'nodaemon']
                            if role == 'foreground-server' else ['devices'])
                self.assertEqual(r['argvDeclaration'][1:], expected)

    def test_uncaptured_is_not_absent(self):
        r = self.receipt()
        self.assertEqual(r['modelVerdict'], 'MODEL_UNKNOWN')
        self.assertEqual(r['sourcePrediction']['home'], 'UNKNOWN')
        self.assertTrue(all(e['state'] == 'UNRECORDED'
                            for e in r['environment']['launcherPassedModel'].values()))
        for state, value in [('UNRECORDED', None), ('ABSENT', None), ('EMPTY', ''), ('VALUE', 'x')]:
            with self.subTest(state=state):
                self.assertEqual(environment_state(state, value), {'state': state, 'value': value})

    def test_each_changed_input_stops(self):
        for name in VARIABLES:
            with self.subTest(name=name):
                values = declaration()
                values[name] = environment_state('EMPTY', '')
                self.assertEqual(self.receipt(values=values, preserved=True)['modelVerdict'], 'MODEL_STOP')
        self.assertEqual(self.receipt(values=declaration(), preserved=False)['modelVerdict'], 'MODEL_STOP')
        self.assertEqual(self.receipt(values=declaration())['modelVerdict'], 'MODEL_UNKNOWN')

    def test_unknown_does_not_hide_known_mismatch(self):
        values = declaration()
        values['HOME'] = environment_state('UNRECORDED')
        values['ADB_SERVER_SOCKET'] = environment_state('VALUE', 'tcp:remote:9999')
        self.assertEqual(self.receipt(values=values, preserved=True)['modelVerdict'], 'MODEL_STOP')

    def test_schema_rejects_full_environment_and_partial_capture(self):
        for name in VARIABLES:
            values = declaration()
            del values[name]
            with self.subTest(missing=name), self.assertRaises(ValueError):
                self.receipt(values=values)
        values = declaration()
        values['SECRET'] = environment_state('VALUE', 'synthetic')
        with self.assertRaises(ValueError):
            self.receipt(values=values)
        values = declaration()
        values['HOME']['extra'] = True
        with self.assertRaises(ValueError):
            self.receipt(values=values)

    def test_invalid_states_and_identity(self):
        for state, value in [('ABSENT', ''), ('EMPTY', None), ('VALUE', ''), ('VALUE', '\x00'),
                             ('UNRECORDED', 'x'), ('UNKNOWN', None)]:
            with self.subTest(state=state, value=value), self.assertRaises(ValueError):
                environment_state(state, value)
        with self.assertRaises(ValueError):
            self.receipt(role='baseline-consumer')
        with self.assertRaises(ValueError):
            model_receipt('actual-run', 'model://call', 'devices-client', {})
        for binary in [{'path': '/actual/adb', 'sha256': 'a' * 64, 'size': 1},
                       {'path': 'model://adb', 'sha256': 'G' * 64, 'size': 1},
                       {'path': 'model://adb', 'sha256': 'a' * 64, 'size': True}]:
            with self.subTest(binary=binary), self.assertRaises(ValueError):
                self.receipt(binary=binary)

    def test_input_and_output_are_isolated(self):
        values = declaration()
        binary = {'path': 'model://adb', 'sha256': 'a' * 64, 'size': 1}
        r = self.receipt(values=values, preserved=True, binary=binary)
        values['HOME']['value'] = '/changed'
        binary['sha256'] = 'b' * 64
        self.assertEqual(r['environment']['launcherPassedModel']['HOME']['value'], '/Users/swifty')
        self.assertEqual(r['binaryIdentity']['fixture']['sha256'], 'a' * 64)
        r['environment']['declaration']['HOME']['value'] = '/changed'
        self.assertEqual(declaration()['HOME']['value'], '/Users/swifty')

    def test_helper_has_no_io_or_import_adapter(self):
        tree = ast.parse(Path(__file__).with_name('rn_adb_environment.py').read_text())
        self.assertFalse(any(isinstance(n, (ast.Import, ast.ImportFrom)) for n in ast.walk(tree)))
        calls = {n.func.id for n in ast.walk(tree) if isinstance(n, ast.Call) and isinstance(n.func, ast.Name)}
        self.assertFalse(calls & {'open', 'exec', 'eval', 'compile', '__import__', 'input'})


if __name__ == '__main__':
    unittest.main()

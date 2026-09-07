import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def load_module(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


station = load_module('station')
doctor = load_module('doctor')
CATALOG = json.loads((ROOT / 'profiles.json').read_text())
CONFIG = json.loads((ROOT / 'station.example.json').read_text())


class StationContract(unittest.TestCase):
    def test_default_station_has_digital_tools_and_native_hamlib(self):
        plan = station.make_plan(CONFIG, CATALOG)
        self.assertTrue({'wsjtx', 'fldigi', 'flrig', 'libhamlib-utils'} <= set(plan['station_packages']))
        self.assertEqual(plan['station_desktop_software_id'], 25)

    def test_packet_station_can_omit_the_desktop(self):
        plan = station.make_plan(dict(CONFIG, mode='services', profiles=['packet']), CATALOG)
        self.assertIn('direwolf', plan['station_packages'])
        self.assertNotIn('wsjtx', plan['station_packages'])
        self.assertIsNone(plan['station_desktop_software_id'])

    def test_gui_profiles_cannot_silently_enter_services_only_mode(self):
        for profile in ('digital', 'sdr'):
            with self.subTest(profile=profile), self.assertRaisesRegex(ValueError, 'requires desktop'):
                station.make_plan(dict(CONFIG, mode='services', profiles=[profile]), CATALOG)

    def test_repeated_and_reordered_profiles_produce_one_stable_plan(self):
        first = station.make_plan(dict(CONFIG, profiles=['packet', 'digital', 'packet']), CATALOG)
        second = station.make_plan(dict(CONFIG, profiles=['digital', 'packet']), CATALOG)
        self.assertEqual(first, second)

    def test_invalid_settings_fail_before_any_installer_starts(self):
        cases = [{'station_user': 'root'}, {'station_user': 'radio;id'}, {'profiles': 'digital'},
                 {'profiles': ['typo']}, {'mode': 'remote'}, {'profilse': ['packet']},
                 {'package_versions': {'wsjtx': '*'}}, {'package_versions': {'unselected': '1.0'}}]
        for override in cases:
            with self.subTest(override=override), self.assertRaises(ValueError):
                station.make_plan(dict(CONFIG, **override), CATALOG)

    def test_exact_version_is_preserved_in_apt_request(self):
        plan = station.make_plan(dict(CONFIG, package_versions={'wsjtx': '2.7.0+repack-1'}), CATALOG)
        self.assertIn('wsjtx=2.7.0+repack-1', plan['station_package_specs'])

    def test_plan_runs_without_ansible_or_network(self):
        result = subprocess.run([sys.executable, str(ROOT / 'station.py'), 'plan'],
                                env={'PATH': ''}, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('wsjtx', json.loads(result.stdout)['station_packages'])

    def test_installer_failure_reaches_the_caller(self):
        # The historical runner hid failures behind logging. Exercise a real subprocess.
        with tempfile.TemporaryDirectory() as tmp:
            fake = Path(tmp) / 'ansible-playbook'
            fake.write_text('#!/bin/sh\nexit 37\n')
            fake.chmod(0o755)
            result = subprocess.run([sys.executable, str(ROOT / 'station.py'), 'check',
                                     '--inventory', str(ROOT / 'inventory.example.ini')],
                                    env={'PATH': tmp}, capture_output=True, text=True)
            self.assertEqual(result.returncode, 37, result.stderr)


class PlatformContract(unittest.TestCase):
    def setUp(self):
        self.facts = {'dietpi_version_present': True, 'install_stage': '2', 'os_id': 'debian',
                      'os_version': '13', 'os_codename': 'trixie', 'package_architecture': 'arm64',
                      'board_model': 'Raspberry Pi 4 Model B Rev 1.5',
                      'station_user_exists': True, 'station_user_uid': 1000}

    def test_both_initial_boards_are_accepted(self):
        for model in ('Raspberry Pi 4 Model B Rev 1.5', 'Raspberry Pi 5 Model B Rev 1.0'):
            self.assertEqual(doctor.problems(dict(self.facts, board_model=model)), [])

    def test_unsupported_targets_fail_closed(self):
        for override in ({'package_architecture': 'armhf'}, {'package_architecture': 'amd64'},
                         {'os_codename': 'bookworm'}, {'dietpi_version_present': False},
                         {'install_stage': '1'}, {'board_model': 'Raspberry Pi 3 Model B'},
                         {'station_user_uid': 0}, {'station_user_exists': False}):
            with self.subTest(override=override):
                self.assertTrue(doctor.problems(dict(self.facts, **override)))

    def test_os_release_is_parsed_as_data(self):
        self.assertEqual(doctor.parse_os_release('ID=debian\nVERSION_ID="13"\n# comment\n'),
                         {'ID': 'debian', 'VERSION_ID': '13'})


if __name__ == '__main__':
    unittest.main()

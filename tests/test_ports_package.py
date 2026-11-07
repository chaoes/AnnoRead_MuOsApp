#!/usr/bin/env python3
"""Exercise archive boundaries and the launcher with a fake PortMaster runtime."""
from pathlib import Path
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
import zipfile

PROJECT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT / "package"))
from make_ports import build_package  # noqa: E402


class PortsPackageTest(unittest.TestCase):
    def test_payload_preserves_keyboard_and_excludes_private_data(self):
        # Use a copy with deliberate fake private files; never read local keys.
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            project = root / "project"
            project.mkdir()
            for name in ("main.lua", "conf.lua", "LICENSE", "THIRD_PARTY_NOTICES.md"):
                shutil.copy2(PROJECT / name, project / name)
            for name in ("src", "assets/fonts", "package/ports"):
                shutil.copytree(PROJECT / name, project / name)
            for name in ("sources/README.md", "config/mimo_tts.example.json", "engine/quickjs/LICENSE", "engine/vendor/Copyright.libxml2"):
                target = project / name
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(PROJECT / name, target)
            # Real host ELF is deliberately rejected; mock readelf only after
            # supplying a tiny AArch64 ELF header for the packaging fixture.
            header = bytearray(64)
            header[:7] = b'\x7fELF\x02\x01\x01'
            header[18:20] = (183).to_bytes(2, 'little')
            engine = project / 'engine/liblegado_qjs_aarch64.so'
            engine.write_bytes(header)
            for name in ('config/mimo_tts.json', 'sources/private.json', 'assets/sources/private.json', 'conf/love/rgcubexx-game/legado_bookshelf.json'):
                target = project / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text('PRIVATE_FIXTURE_DO_NOT_SHIP')
            from unittest.mock import patch
            output = root / 'annoread.zip'
            with patch('make_ports.subprocess.check_output', return_value='Name: GLIBC_2.38'):
                build_package(project, output)
            with zipfile.ZipFile(output) as archive:
                names = archive.namelist()
                for source in (project / 'src').rglob('*.lua'):
                    self.assertEqual(archive.read('annoread/' + source.relative_to(project).as_posix()), source.read_bytes())
                self.assertEqual(archive.read('annoread/conf.lua'), (PROJECT / 'conf.lua').read_bytes())
                self.assertEqual(archive.read('annoread/src/liblegado_qjs.so'), header)
                self.assertFalse(any(name.startswith('annoread/conf/') for name in names))
                self.assertFalse(any(name.endswith('.gptk') or name.endswith('/love') for name in names))
                self.assertFalse(any(b'PRIVATE_FIXTURE_DO_NOT_SHIP' in archive.read(name) for name in names if not name.endswith('/')))
                self.assertTrue((archive.getinfo('AnnoRead.sh').external_attr >> 16) & stat.S_IXUSR)
                metadata = json.loads(archive.read('annoread/port.json'))
                self.assertEqual(metadata['items'], ['AnnoRead.sh', 'annoread'])
            wrong_arch = bytearray(header)
            wrong_arch[18:20] = (62).to_bytes(2, 'little')
            engine.write_bytes(wrong_arch)
            with self.assertRaisesRegex(ValueError, 'AArch64'):
                build_package(project, output)
            engine.write_bytes(header)
            with patch('make_ports.subprocess.check_output', return_value='Name: GLIBC_2.39'):
                with self.assertRaisesRegex(ValueError, 'above'):
                    build_package(project, output)

    def run_launcher(self, *, runtime=True, architecture='aarch64', glibc='2.38', love_status=0):
        with tempfile.TemporaryDirectory(prefix='annoread launcher ') as temporary:
            root = Path(temporary)
            data = root / 'data'
            pm = data / 'PortMaster'
            pm.mkdir(parents=True)
            app = root / 'sd card/ports/annoread'
            app.mkdir(parents=True)
            binaries = root / 'bin'
            binaries.mkdir()
            events = root / 'events'

            def executable(path, content):
                path.write_text('#!/bin/bash\n' + content)
                path.chmod(0o755)

            executable(binaries / 'getconf', 'echo "glibc $TEST_GLIBC"\n')
            executable(binaries / 'curl', 'echo "curl 8.0.0 fixture"\n')
            executable(binaries / 'gptokeyb', 'printf "gptokeyb:%s\\n" "$*" >> "$TEST_EVENTS"\n')
            (pm / 'control.txt').write_text('''
directory="$TEST_SD"
DEVICE_ARCH="$TEST_ARCH"
CFW_NAME=fixture
GPTOKEYB=gptokeyb
get_controls() { sdl_controllerconfig=fixture-controller; }
pm_platform_helper() { wait "$!"; printf 'helper:%s\\n' "$1" >> "$TEST_EVENTS"; }
pm_finish() { echo finish >> "$TEST_EVENTS"; }
''')
            if runtime:
                runtime_dir = pm / 'runtimes/love_11.5'
                runtime_dir.mkdir(parents=True)
                (runtime_dir / 'love.txt').write_text('''
RUNTIME_DIR="$controlfolder/runtimes/love_11.5"
LOVE_BINARY="$RUNTIME_DIR/love.$DEVICE_ARCH"
LOVE_GPTK="love.$DEVICE_ARCH"
''')
                executable(runtime_dir / 'love.aarch64', '''
printf 'love:%s\\ncwd:%s\\nconfig:%s\\nsdl:%s\\n' "$1" "$PWD" "$XDG_DATA_HOME" "$SDL_GAMECONTROLLERCONFIG" >> "$TEST_EVENTS"
exit "$TEST_LOVE_STATUS"
''')
            env = dict(os.environ, XDG_DATA_HOME=str(data),
                       PATH=str(binaries) + ':' + os.environ['PATH'],
                       TEST_SD=str(root / 'sd card'), TEST_ARCH=architecture,
                       TEST_EVENTS=str(events), TEST_GLIBC=glibc,
                       TEST_LOVE_STATUS=str(love_status))
            result = subprocess.run(['bash', str(PROJECT / 'package/ports/AnnoRead.sh')],
                                    env=env, capture_output=True, text=True, timeout=15)
            log = (app / 'log.txt').read_text()
            event_text = events.read_text() if events.exists() else ''
            return result, log, event_text, str(app)

    def test_native_input_paths_and_runtime_failure_cleanup(self):
        result, log, events, app = self.run_launcher(love_status=7)
        self.assertEqual(result.returncode, 7, log)
        self.assertIn('gptokeyb:love.aarch64', events)
        self.assertNotIn('-c ', events)
        self.assertIn('love:' + app, events)
        self.assertIn('cwd:' + app, events)
        self.assertIn('config:' + app + '/conf', events)
        self.assertIn('sdl:fixture-controller', events)
        self.assertTrue(events.endswith('finish\n'))

    def test_missing_runtime_and_incompatible_system_fail_with_cleanup(self):
        for options, message in (({'runtime': False}, 'Install the love_11.5'),
                                 ({'architecture': 'armhf'}, 'requires AArch64'),
                                 ({'glibc': '2.31'}, 'GLIBC >= 2.38')):
            with self.subTest(options=options):
                result, log, events, _ = self.run_launcher(**options)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(message, log)
                self.assertNotIn('love:', events)
                self.assertTrue(events.endswith('finish\n'))


if __name__ == '__main__':
    unittest.main()

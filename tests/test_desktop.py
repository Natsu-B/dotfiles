"""Offline unit tests. These do not replace a Nix build or a real Wayland test."""
import ctypes as ct
import importlib.util
import io
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch, Mock

ROOT = Path(__file__).resolve().parents[1]
DESKTOP = ROOT / 'home/desktop'

def load(name):
    spec = importlib.util.spec_from_file_location(name, DESKTOP / f'{name}.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

keys = load('generate_xremap')
clipboard = load('clipboard')
cheatsheet = load('cheatsheet')

class KeyboardTests(unittest.TestCase):
    def test_profiles_have_shared_navigation(self):
        for name in ('qwerty', 'dvorak'):
            p = keys.profile(name)
            self.assertEqual(p['virtual_modifiers'], ['F15', 'F14'])
            self.assertEqual(p['keymap'][0]['remap']['F15-J'], 'Left')
            self.assertEqual(p['keymap'][0]['remap']['F15-9'], '9')
            self.assertIn('alone_timeout_millis', p['modmap'][1]['remap']['Space'])
    def test_qwerty_has_no_typing_translation(self):
        self.assertEqual(len(keys.profile('qwerty')['keymap']), 1)
    def test_shortcuts_are_not_translated(self):
        typing = keys.profile('dvorak')['keymap'][1]
        self.assertTrue(typing['exact_match'])
        for chord in typing['remap']:
            self.assertNotRegex(chord, r'(Ctrl|Alt|Super|F14|F15)')
            self.assertLessEqual(chord.count('-'), 1)
    def test_all_typing_outputs_match_intended_characters(self):
        remap = keys.profile('dvorak')['keymap'][1]['remap']
        for key, characters in keys.DVP.items():
            for level, expected in enumerate(characters):
                out = remap[('Shift-' if level else '') + key]
                shifted = out.startswith('Shift-')
                self.assertEqual(keys.JIS[out.removeprefix('Shift-')][int(shifted)], expected)
    def test_shift_number_row(self):
        remap = keys.profile('dvorak')['keymap'][1]['remap']
        for digit in '1234567890':
            self.assertEqual(remap[f'Shift-{digit}'], digit)
    def test_jis_brackets_and_yen(self):
        self.assertEqual(keys.DVP['BACKSLASH'], ('$', '~'))
        self.assertEqual(keys.DVP['YEN'], ('\\', '|'))
    def test_japanese_toggle_preserves_existing_mapping(self):
        self.assertEqual(keys.JAPANESE_TOGGLE, 'CODE_93')
        for name in ('qwerty', 'dvorak'):
            profile = keys.profile(name)
            japanese = profile['modmap'][0]['remap']
            self.assertEqual(japanese['CapsLock'], 'CODE_93')
            self.assertEqual(japanese['GRAVE'], 'CODE_93')
            self.assertEqual(profile['keymap'][0]['remap']['F15-U'], 'CODE_93')

    def test_generator_output_is_valid_json_yaml(self):
        with tempfile.TemporaryDirectory() as directory:
            subprocess.run([sys.executable, str(DESKTOP / 'generate_xremap.py'), directory], check=True)
            for name in ('dvorak', 'qwerty'):
                self.assertEqual(json.loads((Path(directory) / f'{name}.yml').read_text()), keys.profile(name))
    def test_invalid_profile_rejected(self):
        with self.assertRaises(ValueError): keys.profile('../../bad')
    def test_profile_switch_and_failure_rollback(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            binaries = path / 'bin'; binaries.mkdir()
            state = path / 'state'; profiles = path / 'profiles'; profiles.mkdir()
            for name in ('qwerty', 'dvorak'): (profiles / f'{name}.yml').write_text('{}')
            (binaries / 'notify-send').write_text('#!/bin/sh\nexit 0\n')
            (binaries / 'systemctl').write_text(
                '#!/bin/sh\n'
                'case "$*" in *restart*)\n'
                '  if [ "${FAIL_DVORAK:-}" = 1 ] && [ "$(cat "$XDG_STATE_HOME/dotfiles/keyboard-profile")" = dvorak ]; then exit 1; fi;;\n'
                'esac\nexit 0\n')
            for binary in binaries.iterdir(): binary.chmod(0o755)
            env = dict(os.environ, PATH=str(binaries) + ':' + os.environ['PATH'],
                       XDG_RUNTIME_DIR=directory, XDG_STATE_HOME=str(state),
                       DOTFILES_XREMAP_PROFILES=str(profiles))
            script = ['bash', str(DESKTOP / 'keyboard-profile.sh')]
            result = subprocess.run(script + ['status'], env=env, capture_output=True, text=True)
            self.assertEqual(result.stdout.strip(), 'dvorak')
            subprocess.run(script + ['toggle'], env=env, check=True)
            saved = state / 'dotfiles/keyboard-profile'
            self.assertEqual(saved.read_text().strip(), 'qwerty')
            env['FAIL_DVORAK'] = '1'
            result = subprocess.run(script + ['toggle'], env=env)
            self.assertEqual(result.returncode, 1)
            self.assertEqual(saved.read_text().strip(), 'qwerty')

    def test_xkb_jp_actual_characters(self):
        """Check generated output events against the installed libxkbcommon jp map."""
        try:
            lib = ct.CDLL('libxkbcommon.so.0')
            header = Path('/usr/include/linux/input-event-codes.h').read_text()
        except (OSError, FileNotFoundError):
            self.skipTest('libxkbcommon / Linux input header not available')
        class Names(ct.Structure):
            _fields_ = [(k, ct.c_char_p) for k in ('rules', 'model', 'layout', 'variant', 'options')]
        lib.xkb_context_new.argtypes = [ct.c_int]; lib.xkb_context_new.restype = ct.c_void_p
        lib.xkb_keymap_new_from_names.argtypes = [ct.c_void_p, ct.POINTER(Names), ct.c_int]
        lib.xkb_keymap_new_from_names.restype = ct.c_void_p
        lib.xkb_state_new.argtypes = [ct.c_void_p]; lib.xkb_state_new.restype = ct.c_void_p
        lib.xkb_state_update_mask.argtypes = [ct.c_void_p] + [ct.c_uint] * 6
        lib.xkb_state_key_get_utf8.argtypes = [ct.c_void_p, ct.c_uint, ct.c_char_p, ct.c_size_t]
        for n in ('state', 'keymap', 'context'): getattr(lib, f'xkb_{n}_unref').argtypes = [ct.c_void_p]
        context = lib.xkb_context_new(0)
        keymap = lib.xkb_keymap_new_from_names(context, ct.byref(Names(None, None, b'jp', b'', b'')), 0)
        if not keymap:
            lib.xkb_context_unref(context)
            self.skipTest('XKB jp rules are not installed')
        state = lib.xkb_state_new(keymap)
        codes = {k: int(v) for k, v in re.findall(r'^#define\s+KEY_(\w+)\s+(\d+)\s*$', header, re.M)}
        try:
            for key, chars in keys.JIS.items():
                for shift, expected in enumerate(chars):
                    lib.xkb_state_update_mask(state, shift, 0, 0, 0, 0, 0)
                    buf = ct.create_string_buffer(32)
                    lib.xkb_state_key_get_utf8(state, codes[key] + 8, buf, len(buf))
                    self.assertEqual(buf.value.decode(), expected, (key, shift))
        finally:
            lib.xkb_state_unref(state); lib.xkb_keymap_unref(keymap); lib.xkb_context_unref(context)

class ClipboardTests(unittest.TestCase):
    def test_missing_runtime_rejected(self):
        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaises(RuntimeError): clipboard.runtime()
    def test_disk_filesystem_rejected(self):
        with tempfile.TemporaryDirectory() as path:
            with patch.dict(os.environ, {'XDG_RUNTIME_DIR': path}), patch.object(clipboard, 'run', return_value=Mock(stdout='ext4\n')):
                with self.assertRaises(RuntimeError): clipboard.runtime()
    def test_wrong_permissions_rejected(self):
        with tempfile.TemporaryDirectory() as path:
            os.chmod(path, 0o755)
            with patch.dict(os.environ, {'XDG_RUNTIME_DIR': path}):
                with self.assertRaises(RuntimeError): clipboard.runtime()
    def test_symlink_rejected(self):
        with tempfile.TemporaryDirectory() as base:
            path = Path(base); (path / 'link').symlink_to(path, target_is_directory=True)
            with patch.dict(os.environ, {'XDG_RUNTIME_DIR': str(path / 'link')}):
                with self.assertRaises(RuntimeError): clipboard.runtime()
    def test_db_path_and_retention_explicit(self):
        with patch.object(clipboard, 'run', return_value=Mock(stdout=b'')) as run:
            clipboard.cliphist(Path('/run/user/1000/dotfiles-clipboard'), 'store', b'example')
            args = run.call_args.args[0]
            self.assertIn('/run/user/1000/dotfiles-clipboard/db', args)
            self.assertEqual(args[args.index('-max-items') + 1], '100')
            self.assertEqual(args[args.index('-config-path') + 1], '/dev/null')
    def test_sensitive_and_empty_states_not_saved(self):
        for state in ('sensitive', 'nil', 'clear'):
            with patch.dict(os.environ, {'CLIPBOARD_STATE': state}), patch.object(clipboard, 'directory', return_value=Path('/not-used')), patch.object(clipboard, 'cliphist') as store:
                clipboard.main('store'); store.assert_not_called()
    def test_oversized_text_not_saved(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(clipboard, 'directory', return_value=Path(directory)), patch.object(clipboard, 'runtime', return_value=Path(directory)), patch.object(clipboard, 'active', return_value=True), patch.object(sys, 'stdin', Mock(buffer=io.BytesIO(b'x' * 65537))), patch.object(clipboard, 'cliphist') as store:
                clipboard.main('store'); store.assert_not_called()
    def test_text_saved_within_bound(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(clipboard, 'directory', return_value=Path(directory)), patch.object(clipboard, 'runtime', return_value=Path(directory)), patch.object(clipboard, 'active', return_value=True), patch.object(sys, 'stdin', Mock(buffer=io.BytesIO(b'example'))), patch.object(clipboard, 'cliphist') as store:
                clipboard.main('store'); self.assertEqual(store.call_args.args[2], b'example')
    def test_lock_prevents_resume(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory); (path / 'dotfiles-screen-locked').touch()
            with patch.object(clipboard, 'runtime', return_value=path), patch.object(clipboard, 'run') as run:
                with self.assertRaises(RuntimeError): clipboard.resume()
                run.assert_not_called()
    def test_gnome_does_not_start_history(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(clipboard, 'runtime', return_value=Path(directory)), patch.object(clipboard, 'active', return_value=False):
                with self.assertRaises(RuntimeError): clipboard.resume()
    def test_purge_removes_payload_and_rofi_cache(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory); (path / 'db').write_text('example')
            (path / 'rofi-cache').mkdir(); (path / 'rofi-cache/search').write_text('query')
            with patch.object(clipboard, 'directory', return_value=path), patch.object(clipboard, 'clear_selection') as clear:
                clipboard.purge()
                self.assertFalse((path / 'db').exists()); self.assertFalse((path / 'rofi-cache').exists()); clear.assert_called_once()
    def test_menu_cancel_does_not_copy(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory); (path / 'db').touch()
            with patch.object(clipboard, 'directory', return_value=path), patch.object(clipboard, 'active', return_value=True), patch.object(clipboard, 'cliphist', return_value=b'1\texample\n'), patch.object(clipboard.sp, 'run', return_value=Mock(returncode=1)), patch.object(clipboard, 'run') as run:
                clipboard.main('menu'); run.assert_not_called()
    def test_menu_uses_numeric_selection_and_runtime_cache(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory); (path / 'db').touch()
            with patch.object(clipboard, 'directory', return_value=path), patch.object(clipboard, 'active', return_value=True), patch.object(clipboard, 'cliphist', side_effect=[b'1\texample\n', b'$(not-a-command)\n']), patch.object(clipboard.sp, 'run', return_value=Mock(returncode=0, stdout=b'0\n')) as menu, patch.object(clipboard, 'run') as copy:
                clipboard.main('menu')
                self.assertEqual(menu.call_args.kwargs['env']['XDG_CACHE_HOME'], str(path / 'rofi-cache'))
                self.assertEqual(copy.call_args.args[0][0], 'wl-copy')
                self.assertEqual(copy.call_args.kwargs['input'], b'$(not-a-command)\n')
                self.assertNotIn('shell', copy.call_args.kwargs)

class ConfigTests(unittest.TestCase):
    def test_shell_syntax(self):
        for file in DESKTOP.glob('*.sh'):
            subprocess.run(['bash', '-n', str(file)], check=True)
    def test_cheatsheet_formats_physical_win_v(self):
        value = cheatsheet.format_binding({'modmask': 64, 'keycode': 55, 'description': 'History'})
        self.assertIn('Win + V', value); self.assertIn('History', value)
    def test_clipboard_menu_owner_is_kept_alive(self):
        text = (DESKTOP / 'default.nix').read_text() + (DESKTOP / 'packages.nix').read_text()
        self.assertIn('RemainAfterExit = true;', text)
        self.assertIn('restart dotfiles-clipboard-menu.service', text)
        self.assertIn('RuntimeDirectoryMode = "0700";', text)
    def test_same_base_layout(self):
        self.assertIn('kb_layout = "jp"', (DESKTOP / 'hypr/input.lua').read_text())
        self.assertIn('layout = "jp"', (ROOT / 'nixos/desktop.nix').read_text())
        self.assertIn('Default Layout=jp', (DESKTOP / 'default.nix').read_text())
    def test_karukan_defaults_to_low_latency_main_strategy(self):
        home = (DESKTOP / 'default.nix').read_text()
        self.assertIn('strategy = "main"', home)
        self.assertIn('live_conversion = false', home)
        self.assertIn('candidate_window = "conversion"', home)
        self.assertIn('light_model = "jinen-v2-xsmall-q4"', home)

    def test_karukan_runtime_dependencies_are_checked(self):
        package = (ROOT / 'nixos/karukan.nix').read_text()
        patcher = (ROOT / 'nixos/patch-karukan.py').read_text()
        self.assertIn('LLAMA_BUILD_SHARED_LIBS = "0";', package)
        self.assertIn("patchelf --print-needed \"$rustlib\"", package)
        self.assertIn("grep -E '^lib(llama|ggml)'", package)
        self.assertIn("ldd -r \"$addon\"", package)
        self.assertIn("undefined symbol", package)
        self.assertIn("grep -Eq '^libopenvino", package)
        self.assertIn('openvino.dev', package)
        self.assertIn('openvino.lib', package)
        self.assertIn('find ${openvino.dev} -type f -name OpenVINOConfig.cmake', package)
        self.assertIn('openvino_cmake_dir="$(dirname "$openvino_config")"', package)
        self.assertIn('OpenVINO_ROOT="${openvino.dev}"', package)
        self.assertIn('lib.makeLibraryPath [ openvino.lib onetbb ocl-icd ]', package)
        self.assertIn('find_package(OpenVINO REQUIRED COMPONENTS Runtime Threading)', patcher)
        self.assertIn('find_package(OpenCL REQUIRED)', patcher)
        self.assertIn('openvino::runtime', patcher)
        self.assertIn('openvino::threading', patcher)
        self.assertIn('OpenCL::OpenCL', patcher)
        self.assertIn('LINKER:--no-as-needed', patcher)
        self.assertIn('passthru.extraLdLibraries', package)
        self.assertIn('assert lib.versionAtLeast openvino.version "2026.4.0";', package)

    def test_karukan_openvino_family_comes_from_unstable(self):
        nixos = (ROOT / 'nixos/configuration.nix').read_text()
        for attr in ('openvino', 'onetbb', 'ocl-icd', 'opencl-headers', 'opencl-clhpp'):
            self.assertIn(f'{attr} = unstable.{attr};', nixos)

    def test_karukan_is_the_only_japanese_engine(self):
        nixos = (ROOT / 'nixos/configuration.nix').read_text()
        desktop = (ROOT / 'nixos/desktop.nix').read_text()
        home = (DESKTOP / 'default.nix').read_text()
        package = (ROOT / 'nixos/karukan.nix').read_text()
        patcher = (ROOT / 'nixos/patch-karukan.py').read_text()
        self.assertIn('karukan = pkgs.callPackage ./karukan.nix', nixos)
        self.assertNotIn('fcitx5-mozc', nixos)
        self.assertIn('DefaultIM=karukan', home)
        self.assertIn('Name=karukan', home)
        self.assertNotIn('Name=mozc', home)
        self.assertIn('hardware.cpu.intel.npu.enable = true;', desktop)
        self.assertIn('GGML_OPENVINO_DEVICE = "GPU";', nixos)
        self.assertIn('GGML_OPENVINO_STATEFUL_EXECUTION = "1";', nixos)
        self.assertIn('intel-compute-runtime = unstablePkgs.intel-compute-runtime;', nixos)
        self.assertNotIn('extraPackages = [ unstable.intel-compute-runtime ]', nixos)
        self.assertIn('clinfo', nixos)
        self.assertIn('GGML_OPENVINO = "ON";', package)
        self.assertIn('-DECM_DIR=${kdePackages.extra-cmake-modules}/share/ECM/cmake', package)
        self.assertIn('-DCMAKE_INSTALL_LIBDIR=lib', package)
        self.assertIn('openvino_config="$(find ${openvino.dev} -type f -name OpenVINOConfig.cmake -print -quit)"', package)
        self.assertIn('export OpenVINO_DIR="$openvino_cmake_dir"', package)
        self.assertIn('export OpenVINO_ROOT="${openvino.dev}"', package)
        self.assertIn('onetbb', package)
        self.assertIn('find ${onetbb.dev} -type f -name TBBConfig.cmake', package)
        self.assertIn('export TBB_DIR="$tbb_cmake_dir"', package)
        self.assertIn('export TBB_ROOT="${onetbb}"', package)
        self.assertRegex(package, r'rev = "[0-9a-f]{40}";')
        self.assertNotIn('cpu_fallback', patcher)
        self.assertNotIn('accelerator_device', patcher)
        self.assertNotIn('from_file_accelerated', patcher)
        self.assertIn("rsplit_once('@')", patcher)
        self.assertRegex(home, r'jinen-v2-small\.gguf@[0-9a-f]{40}')
        self.assertRegex(home, r'jinen-v2-xsmall\.gguf@[0-9a-f]{40}')

    def test_uwsm_target_is_detection_stop_boundary_not_start_target(self):
        target = 'wayland-session@hyprland.desktop.target'
        for path in (DESKTOP / 'default.nix', DESKTOP / 'clipboard.py', DESKTOP / 'lock.sh'):
            text = path.read_text()
            self.assertIn(target, text, path)
            self.assertNotIn('wayland-session@Hyprland.target', text, path)

        nixos = (ROOT / 'nixos/desktop.nix').read_text()
        home = (DESKTOP / 'default.nix').read_text()
        self.assertIn('target = "graphical-session.target";', nixos)
        self.assertIn('ConditionEnvironment =', nixos)
        self.assertIn('"XDG_CURRENT_DESKTOP=Hyprland"', nixos)
        self.assertNotIn('Install.WantedBy = [ target ];', home)
        self.assertGreaterEqual(home.count('Install.WantedBy = [ "graphical-session.target" ];'), 3)

    def test_codex_desktop_uses_immutable_release(self):
        text = (ROOT / 'home/app/codex-desktop.nix').read_text()
        self.assertNotIn('/latest/', text)
        self.assertIn('/pool/main/c/chatgpt/chatgpt_${version}_amd64.deb', text)
        self.assertRegex(text, r'hash = "sha256-[A-Za-z0-9+/=]+";')

    def test_chatgpt_uses_native_wayland_and_wayland_ime(self):
        text = (ROOT / 'home/app/codex-desktop.nix').read_text()
        self.assertIn('--ozone-platform=wayland', text)
        self.assertIn('--enable-features=UseOzonePlatform', text)
        self.assertIn('--enable-wayland-ime', text)
        self.assertNotIn('--force-device-scale-factor=', text)

    def test_no_duplicate_xremap_start(self):
        text = (ROOT / 'home/home.nix').read_text()
        self.assertNotIn('xremap-gnome', text); self.assertNotIn('xremap-hypr', text)
        for path in (DESKTOP / 'hypr').glob('*.lua'):
            self.assertNotIn('hl.exec_cmd(', path.read_text())
    def test_every_binding_has_a_description(self):
        bindings = [line.strip() for line in (DESKTOP / 'hypr/binds.lua').read_text().splitlines() if line.strip().startswith('hl.bind(')]
        self.assertGreater(len(bindings), 30)
        for line in bindings:
            self.assertIn('description =', line)

if __name__ == '__main__':
    unittest.main()

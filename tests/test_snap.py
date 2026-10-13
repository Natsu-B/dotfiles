"""Snap-assist behavior without moving windows on the running desktop."""
import copy
import importlib.util
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location('snap', Path(__file__).resolve().parents[1] / 'home/desktop/snap.py')
snap = importlib.util.module_from_spec(spec)
spec.loader.exec_module(snap)


class SnapTests(unittest.TestCase):
    def setUp(self):
        self.source = dict(address='0x123', mapped=True, hidden=False, monitor=0,
                           workspace=dict(id=1, name='1'), fullscreen=1, floating=False)
        self.target = dict(address='0x456', mapped=True, hidden=False, monitor=1,
                           workspace=dict(id=-98, name='special:minimized-456'),
                           fullscreen=2, floating=False, title='選択するアプリ')
        self.other = dict(address='0x789', mapped=True, hidden=False, monitor=0,
                          workspace=dict(id=1, name='1'), fullscreen=0, floating=False)
        self.windows = [self.source, self.target, self.other]
        self.monitor = dict(id=0, width=1920, height=1200, scale=1, transform=0,
                            x=0, y=0, reserved=[0, 38, 0, 0],
                            activeWorkspace=dict(id=1, name='1'), specialWorkspace=dict(name=''))
        self.calls = []

    def query(self, name):
        return copy.deepcopy({'activewindow': self.source, 'clients': self.windows,
                              'monitors': [self.monitor], 'getoption general:border_size': {'int': 2}}[name])

    def dispatch(self, method, **options):
        self.calls.append((method, options))
        if 'window' not in options or method == 'focus':
            return
        window = next(w for w in self.windows if 'address:' + w['address'] == options['window'])
        if method == 'window.move' and 'workspace' in options:
            window['workspace'] = dict(id=options['workspace'], name=str(options['workspace']))
            window['monitor'] = 0
        if method == 'window.fullscreen_state':
            window['fullscreen'] = options['internal']
        if method == 'window.float':
            window['floating'] = options['action'] == 'on'
        if method == 'window.resize':
            window['size'] = [options['x'], options['y']]
        if method == 'window.move' and 'x' in options:
            window['at'] = [options['x'], options['y']]

    def run_snap(self, direction='right', choose=None):
        picker = choose or (lambda windows, side: self.target['address'])
        with patch.object(snap, 'query', side_effect=self.query), \
             patch.object(snap, 'dispatch', side_effect=self.dispatch), \
             patch.object(snap, 'choose', side_effect=picker) as selection:
            snap.snap(direction)
        return selection

    def test_maximized_and_fullscreen_choose_opposite_half(self):
        for mode in (1, 2):
            for direction, opposite in snap.OPPOSITE.items():
                with self.subTest(mode=mode, direction=direction):
                    self.setUp()
                    self.source['fullscreen'] = mode
                    untouched = copy.deepcopy(self.other)
                    picker = self.run_snap(direction)
                    self.assertEqual(picker.call_args.args[1], opposite)
                    self.assertEqual(self.target['workspace']['id'], 1)
                    self.assertEqual(self.target['monitor'], 0)
                    self.assertTrue(self.source['floating'] and self.target['floating'])
                    self.assertEqual(self.source['fullscreen'], 0)
                    self.assertEqual(self.target['fullscreen'], 0)
                    axis = 0 if direction in ('left', 'right') else 1
                    if direction in ('right', 'down'):
                        self.assertGreater(self.source['at'][axis], self.target['at'][axis])
                    else:
                        self.assertLess(self.source['at'][axis], self.target['at'][axis])
                    for window in (self.source, self.target):
                        self.assertGreaterEqual(window['at'][1], 40)  # reserved bar + border
                    self.assertEqual(self.other, untouched)
                    self.assertEqual(self.calls[-1], ('focus', {'window': 'address:0x456'}))

    def test_normal_window_keeps_directional_movement(self):
        self.source['fullscreen'] = 0
        selection = self.run_snap()
        selection.assert_not_called()
        self.assertEqual(self.calls, [('window.move', {'window': 'address:0x123', 'direction': 'right'})])

    def test_cancel_keeps_source_half_and_leaves_other_windows_alone(self):
        untouched = copy.deepcopy(self.windows[1:])
        self.run_snap(choose=lambda *args: None)
        self.assertTrue(self.source['floating'])
        self.assertEqual(self.source['fullscreen'], 0)
        self.assertEqual(self.windows[1:], untouched)

    def test_closed_companion_is_not_moved(self):
        def choose(*args):
            self.windows.remove(self.target)
            return self.target['address']
        self.run_snap(choose=choose)
        self.assertFalse(any(options.get('window') == 'address:0x456' for _, options in self.calls))

    def test_closed_source_is_not_replaced_by_another_window(self):
        def choose(*args):
            self.windows.remove(self.source)
            return self.target['address']
        self.run_snap(choose=choose)
        self.assertFalse(self.target['floating'])

    def test_workspace_change_during_selection_does_not_move_companion(self):
        def choose(*args):
            self.monitor['activeWorkspace']['id'] = 2
            return self.target['address']
        self.run_snap(choose=choose)
        self.assertFalse(self.target['floating'])

    def test_minimized_source_uses_ordinary_workspace_and_closes_overlay(self):
        self.source['workspace'] = dict(id=-97, name='special:minimized-123')
        self.monitor['specialWorkspace'] = dict(name='special:minimized-123')
        with patch.object(snap.sp, 'run') as process:
            selection = self.run_snap(choose=lambda *args: None)
        self.assertEqual(self.source['workspace']['id'], 1)
        self.assertEqual(process.call_args.args[0][-1], 'hl.dsp.workspace.toggle_special("minimized-123")')
        selection.assert_called_once()

    def test_no_other_windows_needs_no_picker(self):
        self.windows = [self.source]
        self.run_snap().assert_not_called()
        self.assertTrue(self.source['floating'])

    def test_named_ordinary_workspace_is_not_treated_as_minimized(self):
        self.source['workspace'] = dict(id=-1337, name='research')
        self.monitor['activeWorkspace'] = copy.deepcopy(self.source['workspace'])
        self.run_snap(choose=lambda *args: None)
        self.assertEqual(self.source['workspace'], dict(id=-1337, name='research'))
        self.assertFalse(any('workspace' in options for _, options in self.calls))

    def test_scaled_rotated_monitor_and_negative_origin(self):
        monitor = dict(width=1200, height=1920, scale=1.5, transform=1,
                       x=-1280, y=-50, reserved=[10, 40, 20, 30])
        left, right = snap.halves(monitor, 'left', 2)
        self.assertEqual(left, (-1268, -8, 621, 726))
        self.assertEqual(right, (-643, -8, 621, 726))
        self.assertEqual(snap.halves(monitor, 'right', 2), [right, left])

    def test_candidate_identity_is_independent_of_duplicate_or_multiline_titles(self):
        self.source['title'] = self.target['title'] = 'same\nname\x00\x1f'
        hidden = dict(self.other, address='0xaaa', hidden=True)
        unmapped = dict(self.other, address='0xbbb', mapped=False)
        windows = snap.candidates([self.source, self.target, hidden, unmapped], '0x123')
        self.assertEqual(windows, [self.target])
        with patch.object(snap.sp, 'run', return_value=subprocess.CompletedProcess([], 0, stdout='0\n')) as process:
            self.assertEqual(snap.choose(windows, 'left'), '0x456')
        self.assertEqual(process.call_args.kwargs['input'].count('\n'), 1)
        self.assertNotIn('\x00', process.call_args.kwargs['input'])
        self.assertIn('最小化', process.call_args.kwargs['input'])
        self.assertIn('左側に並べるアプリ', process.call_args.args[0])

    def test_picker_rejects_cancel_and_invalid_indices(self):
        for code, output in [(1, '0'), (0, '-1'), (0, '99'), (0, 'typed text')]:
            with self.subTest(code=code, output=output), patch.object(snap.sp, 'run', return_value=subprocess.CompletedProcess([], code, stdout=output)):
                self.assertIsNone(snap.choose([self.target], 'left'))

    def test_lua_ipc_escapes_names_without_shell_interpretation(self):
        with patch.object(snap.sp, 'run', return_value=subprocess.CompletedProcess([], 0, stdout='ok\n')) as process:
            snap.dispatch('window.move', window='address:0x123', workspace='name:日本語"\n\x01\\$(x)', follow=False)
        args = process.call_args.args[0]
        self.assertEqual(args[:2], ['hyprctl', 'dispatch'])
        self.assertIn('workspace = "name:日本語\\"\\010\\001\\\\$(x)"', args[2])
        self.assertIn('follow = false', args[2])
        self.assertNotIn('shell', process.call_args.kwargs)


if __name__ == '__main__':
    unittest.main()

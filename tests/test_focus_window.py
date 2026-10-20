"""Activation regressions; no changes to the running compositor."""
import copy
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('focus_window', Path(__file__).resolve().parents[1] / 'home/desktop/focus_window.py')
focus = importlib.util.module_from_spec(spec)
spec.loader.exec_module(focus)


class FocusTests(unittest.TestCase):
    def setUp(self):
        self.target = dict(address='0x123', mapped=True, hidden=False, floating=False,
                           fullscreen=0, fullscreenClient=0, monitor=0,
                           workspace=dict(id=1, name='1'), at=[20, 40], size=[800, 600])
        self.cover = dict(address='0x456', mapped=True, hidden=False, floating=True,
                          fullscreen=0, fullscreenClient=0, monitor=0,
                          workspace=dict(id=1, name='1'), at=[100, 100], size=[400, 300])
        self.windows = [self.target, self.cover]
        self.monitor = dict(id=0, activeWorkspace=dict(id=1, name='1'), specialWorkspace=dict(id=0, name=''))
        self.calls = []
        self.active = None

    def query(self, name):
        return copy.deepcopy({'clients': self.windows, 'monitors': [self.monitor],
                              'activewindow': self.active or {}}[name])

    def dispatch(self, method, **options):
        self.calls.append((method, options))
        w = next((w for w in self.windows if 'address:' + w['address'] == options.get('window')), None)
        if method == 'focus':
            self.active = w
        elif method == 'window.float':
            w['floating'] = True
        elif method == 'window.move' and 'workspace' in options:
            w['workspace'] = dict(id=options['workspace'], name=str(options['workspace']))
        elif method == 'window.fullscreen_state':
            w['fullscreen'] = options['internal']
            w['fullscreenClient'] = options['client']

    def activate(self):
        with patch.object(focus, 'query', self.query), patch.object(focus, 'dispatch', self.dispatch):
            return focus.activate('0x123')

    def test_occluded_tiled_window_becomes_visible_and_keeps_geometry(self):
        self.assertTrue(self.activate())
        self.assertTrue(self.target['floating'])
        self.assertIn(('window.resize', dict(window='address:0x123', x=800, y=600, relative=False)), self.calls)
        self.assertIn(('window.move', dict(window='address:0x123', x=20, y=40, relative=False)), self.calls)
        self.assertEqual(self.calls[-2:], [('focus', dict(window='address:0x123')),
                                         ('window.alter_zorder', dict(window='address:0x123', mode='top'))])

    def test_normal_tiling_remains_without_visible_overlap(self):
        for update in ({'hidden': True}, {'mapped': False}, {'floating': False},
                       {'at': [900, 40]}, {'workspace': dict(id=2, name='2')}):
            with self.subTest(update=update):
                self.setUp()
                self.cover.update(update)
                self.activate()
                self.assertFalse(self.target['floating'])

    def test_pinned_float_on_other_workspace_still_occludes(self):
        self.cover.update(workspace=dict(id=2, name='2'), pinned=True)
        self.activate()
        self.assertTrue(self.target['floating'])

    def test_minimized_target_returns_to_ordinary_workspace_and_closes_overlay(self):
        self.target['workspace'] = dict(id=-95, name='special:minimized-123')
        self.monitor['specialWorkspace'] = dict(id=-95, name='special:minimized-123')
        with patch.object(focus.sp, 'check_output', return_value='ok\n') as command:
            self.activate()
        self.assertEqual(self.calls[0], ('window.move', dict(window='address:0x123', workspace=1, follow=False)))
        self.assertIn('toggle_special("minimized-123")', command.call_args.args[0][-1])
        self.assertEqual(self.target['workspace']['id'], 1)

    def test_only_fullscreen_blocker_on_destination_is_cleared(self):
        self.cover.update(fullscreen=1, fullscreenClient=2)
        unrelated = copy.deepcopy(self.cover)
        unrelated.update(address='0x789', workspace=dict(id=2, name='2'))
        self.windows.append(unrelated)
        self.activate()
        self.assertEqual((self.cover['fullscreen'], self.cover['fullscreenClient']), (0, 0))
        self.assertEqual(unrelated['fullscreen'], 1)

    def test_target_fullscreen_is_preserved(self):
        self.target['fullscreen'] = 2
        self.activate()
        self.assertEqual(self.target['fullscreen'], 2)
        self.assertFalse(self.target['floating'])

    def test_closed_window_does_not_change_focus(self):
        self.windows = [self.cover]
        self.assertFalse(self.activate())
        self.assertEqual(self.calls, [])

    def test_invalid_addresses_are_rejected_before_ipc(self):
        for value in ('active', '0x', '0x123"})', '123', ''):
            with self.subTest(value=value), patch.object(focus, 'query') as query:
                with self.assertRaises(ValueError):
                    focus.activate(value)
                query.assert_not_called()

    def test_failed_focus_is_reported(self):
        with patch.object(focus, 'query', self.query), patch.object(focus, 'dispatch'):
            with self.assertRaisesRegex(RuntimeError, 'did not receive focus'):
                focus.activate('0x123')


if __name__ == '__main__':
    unittest.main()

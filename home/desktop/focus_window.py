"""Activate an existing Hyprland window, restore it, and make it usable in front."""
import argparse
import json
import re
import subprocess as sp
import time


def query(name):
    return json.loads(sp.check_output(['hyprctl', '-j', name], text=True))


def literal(value):
    # Lua does not support JSON's Unicode escapes. Preserve Japanese names.
    if isinstance(value, str):
        return '"' + ''.join('\\' + c if c in '\\"' else
                             f'\\{ord(c):03d}' if ord(c) < 32 or ord(c) == 127 else c
                             for c in value) + '"'
    return str(value).lower()


def dispatch(method, **options):
    args = ', '.join(f'{key}={literal(value)}' for key, value in options.items())
    result = sp.check_output(['hyprctl', 'dispatch', f'hl.dsp.{method}({{{args}}})'], text=True)
    if result.strip() != 'ok':
        raise RuntimeError(result.strip())


def overlaps(a, b):
    ax, ay = a['at']; aw, ah = a['size']
    bx, by = b['at']; bw, bh = b['size']
    return ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah


def activate(address):
    if not re.fullmatch(r'0x[0-9a-fA-F]+', address):
        raise ValueError('Invalid window address')
    windows = query('clients')
    target = next((w for w in windows if w['address'] == address and w.get('mapped')), None)
    if not target:
        return False  # The window may have closed since the shortcut was pressed.
    selector = 'address:' + address
    monitors = query('monitors')
    monitor = next((m for m in monitors if m['id'] == target['monitor']), None)
    if monitor is None:
        return False

    # Minimization is storage, not a permanent overlay. Restore just this window
    # to its monitor's ordinary workspace before selecting it.
    if target['workspace']['name'].startswith('special:minimized'):
        workspace = monitor['activeWorkspace']['id']
        dispatch('window.move', window=selector, workspace=workspace, follow=False)
        target = next(w for w in query('clients') if w['address'] == address)
    workspace = target['workspace']['id']
    overlay = monitor.get('specialWorkspace', {})
    if overlay.get('name') and overlay['id'] != workspace:
        # This dispatcher takes a string, not a table.
        name = overlay['name'].removeprefix('special:')
        result = sp.check_output(['hyprctl', 'dispatch',
                                  'hl.dsp.workspace.toggle_special(' + literal(name) + ')'], text=True)
        if result.strip() != 'ok':
            raise RuntimeError(result.strip())

    windows = query('clients')
    for other in windows:
        if other['address'] != address and other.get('mapped') and not other.get('hidden') \
                and other['workspace']['id'] == workspace and other.get('fullscreen'):
            dispatch('window.fullscreen_state', window='address:' + other['address'],
                     internal=0, client=0, action='set')

    # Hyprland always stacks floating windows above tiled windows. Raising a
    # tiled target alone cannot uncover it. Float it only when it is overlapped,
    # retaining its visible rectangle; otherwise leave normal tiling intact.
    windows = query('clients')
    target = next(w for w in windows if w['address'] == address)
    if not target['floating'] and not target.get('fullscreen') and any(
            w['address'] != address and w.get('mapped') and not w.get('hidden')
            and w.get('floating') and (w['workspace']['id'] == workspace or w.get('pinned'))
            and overlaps(target, w) for w in windows):
        x, y = target['at']; width, height = target['size']
        dispatch('window.float', window=selector, action='on')
        dispatch('window.resize', window=selector, x=width, y=height, relative=False)
        dispatch('window.move', window=selector, x=x, y=y, relative=False)
    dispatch('focus', window=selector)
    dispatch('window.alter_zorder', window=selector, mode='top')
    if query('activewindow').get('address') != address:
        raise RuntimeError('The requested window did not receive focus')
    return True


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--address')
    group.add_argument('--app', help='Comma-separated native app classes; wait for a launched window')
    args = parser.parse_args()
    if args.address:
        activate(args.address)
        return
    classes = {name.casefold() for name in args.app.split(',')}
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        target = next((w for w in query('clients') if w.get('mapped') and
                       str(w.get('class', '')).casefold() in classes), None)
        if target and activate(target['address']):
            return
        time.sleep(0.1)
    raise RuntimeError('No window appeared for the requested application')


if __name__ == '__main__':
    main()

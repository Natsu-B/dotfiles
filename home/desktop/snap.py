"""Snap a maximized window and choose a companion using Hyprland's Lua IPC."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import subprocess as sp
import sys


OPPOSITE = {'left': 'right', 'right': 'left', 'up': 'down', 'down': 'up'}
SIDE = {'left': '左側', 'right': '右側', 'up': '上側', 'down': '下側'}


def query(name):
    return json.loads(sp.check_output(['hyprctl', '-j', *name.split()], text=True))


def lua(value):
    if isinstance(value, str):
        # Lua has no JSON-style \u escapes. Keep UTF-8 and escape control bytes.
        return '"' + ''.join(
            '\\' + ch if ch in '\\"' else
            f'\\{ord(ch):03d}' if ord(ch) < 32 or ord(ch) == 127 else ch
            for ch in value) + '"'
    if isinstance(value, bool):
        return 'true' if value else 'false'
    return str(int(value))


def dispatch(method, **options):
    args = ', '.join(f'{key} = {lua(value)}' for key, value in options.items())
    result = sp.run(['hyprctl', 'dispatch', f'hl.dsp.{method}({{{args}}})'],
                    check=True, capture_output=True, text=True)
    if result.stdout.strip() != 'ok':
        raise RuntimeError(result.stdout.strip() or result.stderr.strip())


def halves(monitor, direction, border):
    width, height = monitor['width'], monitor['height']
    if monitor.get('transform', 0) % 2:
        width, height = height, width
    width, height = int(width / monitor['scale']), int(height / monitor['scale'])
    left, top, right, bottom = monitor['reserved']
    x, y = monitor['x'] + left, monitor['y'] + top
    width, height = width - left - right, height - top - bottom
    if direction in ('left', 'right'):
        cut = width // 2
        first, second = (x, y, cut, height), (x + cut, y, width - cut, height)
    else:
        cut = height // 2
        first, second = (x, y, width, cut), (x, y + cut, width, height - cut)
    boxes = [tuple((bx + border, by + border, bw - 2 * border, bh - 2 * border))
             for bx, by, bw, bh in (first, second)]
    if any(box[2] <= 0 or box[3] <= 0 for box in boxes):
        raise RuntimeError('The monitor has no usable space for two windows')
    return boxes if direction in ('left', 'up') else boxes[::-1]


def place(window, workspace, box):
    selector = 'address:' + window['address']
    dispatch('window.fullscreen_state', window=selector, internal=0, client=0, action='set')
    if window.get('pinned'):
        dispatch('window.pin', window=selector, action='off')
    if window.get('grouped'):
        dispatch('window.move', window=selector, out_of_group=True)
    if window['workspace']['id'] != workspace['id']:
        destination = workspace['id'] if workspace['id'] > 0 else 'name:' + workspace['name']
        dispatch('window.move', window=selector, workspace=destination, follow=False)
    # Floating halves give exactly the selected pair space even with other tiled
    # windows on the workspace. Win+Shift+Space returns each one to normal tiling.
    dispatch('window.float', window=selector, action='on')
    x, y, width, height = box
    dispatch('window.resize', window=selector, x=width, y=height, relative=False)
    dispatch('window.move', window=selector, x=x, y=y, relative=False)
    dispatch('window.alter_zorder', window=selector, mode='top')


def candidates(windows, source):
    return sorted((w for w in windows if w.get('mapped') and not w.get('hidden')
                   and w['address'] != source),
                  key=lambda w: w.get('focusHistoryID', -1) if w.get('focusHistoryID', -1) >= 0 else sys.maxsize)


def label(window):
    workspace = window['workspace']['name']
    workspace = '最小化' if workspace.startswith('special:minimized') else f'WS {workspace}'
    text = f"{window.get('class') or 'アプリ'} — {window.get('title') or '無題'}  [{workspace}]"
    return ' '.join(''.join(ch if ord(ch) >= 32 and ord(ch) != 127 else ' ' for ch in text).split())


def choose(windows, direction):
    result = sp.run([
        'rofi', '-dmenu', '-i', '-no-custom', '-sync', '-format', 'i',
        '-p', f'{SIDE[direction]}に並べるアプリ', '-click-to-exit',
        '-me-select-entry', '', '-me-accept-entry', 'MousePrimary',
        '-theme-str', 'entry { placeholder: "起動中のアプリを検索"; }',
    ], input='\n'.join(label(w) for w in windows) + '\n', capture_output=True, text=True)
    if result.returncode:
        return None
    try:
        index = int(result.stdout.strip())
    except ValueError:
        return None
    return windows[index]['address'] if 0 <= index < len(windows) else None


def snap(direction):
    source = query('activewindow')
    if not source.get('address'):
        return
    if not source.get('fullscreen'):
        dispatch('window.move', window='address:' + source['address'], direction=direction)
        return
    monitors = query('monitors')
    monitor = next((m for m in monitors if m['id'] == source['monitor']), None)
    if monitor is None:
        return
    destination = source['workspace']
    # Recalled minimized windows live on a special workspace. Bring the pair to
    # this monitor's ordinary workspace so minimizing it later hides only one.
    if destination['name'].startswith('special:'):
        destination = monitor['activeWorkspace']
    workspace = destination['id']
    own, companion = halves(monitor, direction, query('getoption general:border_size')['int'])
    place(source, destination, own)
    special = monitor.get('specialWorkspace', {}).get('name', '')
    if special and special == source['workspace']['name']:
        current = next((m for m in query('monitors') if m['id'] == monitor['id']), {})
        if current.get('specialWorkspace', {}).get('name') == special:
            # This dispatcher takes a string rather than a table.
            sp.run(['hyprctl', 'dispatch', f'hl.dsp.workspace.toggle_special({lua(special.removeprefix("special:"))})'],
                   check=True, capture_output=True, text=True)
    dispatch('focus', window='address:' + source['address'])
    windows = candidates(query('clients'), source['address'])
    if not windows:
        return
    selected = choose(windows, OPPOSITE[direction])
    if selected is None:
        return
    # A window may close or the user may change workspace while choosing.
    current = {w['address']: w for w in query('clients') if w.get('mapped')}
    source_now, target = current.get(source['address']), current.get(selected)
    if not source_now or not target or target.get('hidden'):
        return
    if source_now['workspace']['id'] != workspace or source_now['monitor'] != monitor['id']:
        return
    monitor_now = next((m for m in query('monitors') if m['id'] == monitor['id']), {})
    if monitor_now.get('activeWorkspace', {}).get('id') != workspace or monitor_now.get('specialWorkspace', {}).get('name'):
        return
    # Reapply the source box in case extracting the companion changed its group.
    place(target, destination, companion)
    place(source_now, destination, own)
    dispatch('focus', window='address:' + selected)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('direction', choices=OPPOSITE)
    args = parser.parse_args()
    with (Path(os.environ['XDG_RUNTIME_DIR']) / 'dotfiles-snap-assist.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return
        snap(args.direction)


if __name__ == '__main__':
    main()

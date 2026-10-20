"""Generate xremap profiles for a JIS keyboard with the XKB jp layout.

Only unmodified/Shift typing is translated. Ctrl/Alt/Super chords pass through.
Do not also enable XKB us(dvp) or the legacy custom_dvorak.xkb.
"""
import argparse
from itertools import combinations
import json
from pathlib import Path

# evdev key names, followed by characters produced by XKB jp at levels 1 and 2.
JIS = {
    **{c.upper(): (c, c.upper()) for c in 'abcdefghijklmnopqrstuvwxyz'},
    **dict(zip('1234567890', zip('1234567890', '!"#$%&\'()~'))),
    'MINUS': ('-', '='), 'EQUAL': ('^', '~'), 'YEN': ('\\', '|'),
    'LEFTBRACE': ('@', '`'), 'RIGHTBRACE': ('[', '{'),
    'SEMICOLON': (';', '+'), 'APOSTROPHE': (':', '*'),
    'BACKSLASH': (']', '}'), 'COMMA': (',', '<'), 'DOT': ('.', '>'),
    'SLASH': ('/', '?'), 'RO': ('\\', '_'),
}
# Programmer Dvorak, with the requested physical Shift+1..0 number row.
DVP = {
    **dict(zip('1234567890', zip('&[{}(=*)+]', '1234567890'))),
    'MINUS': ('!', '%'), 'EQUAL': ('#', '`'),
    **dict(zip('QWERTYUIOP', zip(';, .pyfgcrl'.replace(' ', ''), ':<>PYFGCRL'))),
    'LEFTBRACE': ('/', '?'), 'RIGHTBRACE': ('@', '^'),
    **{k: (v, v.upper()) for k, v in zip('ASDFGHJKL', 'aoeuidhtn')},
    'SEMICOLON': ('s', 'S'), 'APOSTROPHE': ('-', '_'),
    'BACKSLASH': ('$', '~'), 'YEN': ('\\', '|'),
    'Z': ("'", '"'),
    **{k: (v, v.upper()) for k, v in zip('XCVBNM', 'qjkxbm')},
    'COMMA': ('w', 'W'), 'DOT': ('v', 'V'), 'SLASH': ('z', 'Z'),
    'RO': ('\\', '_'),
}

# Linux input-event-codes.h: KEY_KATAKANAHIRAGANA = 93.
# Keep the existing Japanese-mode key behavior: the real issue was that the
# Karukan addon failed to dlopen, not this event mapping.
JAPANESE_TOGGLE = 'CODE_93'


def output_key(character):
    for key, chars in JIS.items():
        for shifted, value in enumerate(chars):
            if character == value:
                return ('Shift-' if shifted else '') + key
    raise ValueError(f'Character not available on JIS: {character!r}')


def desktop_shortcuts():
    # Use physical keys in both typing profiles. Explicit modifier combinations
    # preserve Shift/Ctrl/Alt rather than letting a plain F14 chord consume them.
    keys = list(JIS) + [f'F{n}' for n in range(1, 13)] + [
        'Space', 'Tab', 'Enter', 'ESC', 'Backspace', 'Delete',
        'Left', 'Right', 'Up', 'Down', 'Home', 'End', 'PageUp', 'PageDown',
    ]
    directions = {'W': 'Up', 'A': 'Left', 'S': 'Down', 'D': 'Right'}
    remap = {}
    for count in range(4):
        for modifiers in combinations(('Shift', 'Ctrl', 'Alt'), count):
            for key in keys:
                # Win+A is quick settings; Henkan+A is left, so use Henkan+C.
                target = directions.get(key, 'A' if key == 'C' else key)
                remap['-'.join((*modifiers, 'F14', key))] = '-'.join(('Super', *modifiers, target))
    return {'name': 'Henkan desktop shortcuts', 'exact_match': True, 'remap': remap}


def profile(name):
    if name not in ('qwerty', 'dvorak'):
        raise ValueError('Unknown keyboard profile')
    navigation = {
        'F15-J': 'Left', 'F15-L': 'Right', 'F15-I': 'Up', 'F15-K': 'Down',
        'F15-SEMICOLON': 'Enter', 'F15-O': 'Delete', 'F15-P': 'Backspace',
        'F15-H': 'Tab', 'F15-U': JAPANESE_TOGGLE,
        **{f'F15-{n}': n for n in '1234567890'},
    }
    result = {
        'virtual_modifiers': ['F15', 'F14'],
        'modmap': [
            {'name': 'Japanese input', 'remap': {
                'CapsLock': JAPANESE_TOGGLE, 'GRAVE': JAPANESE_TOGGLE,
                'MUHENKAN': 'F15', 'HENKAN': 'F14'}},
            {'name': 'SandS', 'remap': {'Space': {
                'held': 'Shift_L', 'alone': 'Space',
                'alone_timeout_millis': 999999999999}}},
        ],
        'keymap': [{'name': 'Muhenkan navigation', 'remap': navigation}],
    }
    if name == 'dvorak':
        remap = {}
        for key, chars in DVP.items():
            for shifted, character in enumerate(chars):
                remap[('Shift-' if shifted else '') + key] = output_key(character)
        result['keymap'].append({
            'name': 'Programmer Dvorak typing only', 'exact_match': True,
            'remap': remap,
        })
    result['keymap'].append(desktop_shortcuts())
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    for name in ('qwerty', 'dvorak'):
        # JSON is a YAML subset accepted by xremap; avoids a PyYAML dependency.
        (args.output / f'{name}.yml').write_text(
            json.dumps(profile(name), indent=2) + '\n', encoding='utf-8')

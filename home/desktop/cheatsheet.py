"""Display descriptions from the live Hyprland bindings, without executing them."""
import json
import subprocess as sp

KEYS = {**dict(zip(range(10, 20), '1234567890')),
        **dict(zip(range(24, 34), 'QWERTYUIOP')),
        **dict(zip(range(38, 47), 'ASDFGHJKL')),
        **dict(zip(range(52, 59), 'ZXCVBNM')),
        36: 'Enter', 65: 'Space', 67: 'F1', 68: 'F2'}


def format_binding(binding):
    mask = binding.get('modmask', 0)
    mods = [name for bit, name in ((64, 'Win'), (4, 'Ctrl'), (8, 'Alt'), (1, 'Shift')) if mask & bit]
    key = binding.get('key') or KEYS.get(binding.get('keycode'), f"code:{binding.get('keycode')}")
    description = binding.get('description', '').replace('\n', ' ')
    return f"{' + '.join(mods + [str(key)]) :<30} {description}"


if __name__ == '__main__':
    bindings = json.loads(sp.check_output(['hyprctl', '-j', 'binds']))
    rows = [format_binding(b) for b in bindings if b.get('description')]
    rows += ['Space (hold)                   Shift (SandS)',
             'Muhenkan + I/J/K/L             Up / Left / Down / Right',
             'Muhenkan + 1..0                Digits 1..0',
             'Henkan + 5                     %',
             'CapsLock / Hankaku             Japanese input toggle']
    sp.run(['rofi', '-dmenu', '-i', '-no-custom', '-no-history', '-p', 'Shortcuts'],
           input='\n'.join(rows), text=True, stdout=sp.DEVNULL, check=False)

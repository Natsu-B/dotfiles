"""Private, session-only cliphist frontend. Never fall back to a disk cache."""
import contextlib
import fcntl
import os
from pathlib import Path
import resource
import shutil
import stat
import subprocess as sp
import sys

UNIT = 'dotfiles-clipboard.service'
MENU = 'dotfiles-clipboard-menu.service'
MAX_BYTES = 65536


def run(args, **kwargs):
    return sp.run(args, check=True, **kwargs)


def active(unit=UNIT):
    return sp.run(['systemctl', '--user', 'is-active', '--quiet', unit],
                  stdout=sp.DEVNULL, stderr=sp.DEVNULL).returncode == 0


def runtime():
    value = os.environ.get('XDG_RUNTIME_DIR')
    if not value or not Path(value).is_absolute():
        raise RuntimeError('XDG_RUNTIME_DIR is required; disk fallback is disabled')
    path = Path(value)
    info = path.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o700:
        raise RuntimeError('Runtime directory must be owned by this user and have mode 0700')
    kind = run(['stat', '-f', '-c', '%T', str(path)], capture_output=True, text=True).stdout.strip()
    if kind != 'tmpfs':
        raise RuntimeError('Clipboard history requires tmpfs; disk fallback is disabled')
    return path


def directory():
    path = runtime() / 'dotfiles-clipboard'
    path.mkdir(mode=0o700, exist_ok=True)
    info = path.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
        raise RuntimeError('Unsafe clipboard directory')
    path.chmod(0o700)
    return path


@contextlib.contextmanager
def locked(path):
    with (path / 'access.lock').open('a') as handle:
        fcntl.flock(handle, fcntl.LOCK_EX)
        yield


def cliphist(path, action, data=None):
    # Ignore any user config which could redirect storage or enlarge retention.
    return run(['cliphist', '-config-path', '/dev/null', '-db-path', str(path / 'db'),
                '-max-items', '100', action], input=data,
               stdout=sp.PIPE, stderr=sp.DEVNULL).stdout


def clear_selection():
    for args in (['wl-copy', '--clear'], ['wl-copy', '--primary', '--clear']):
        try:
            sp.run(args, check=False, stdout=sp.DEVNULL, stderr=sp.DEVNULL, timeout=2)
        except sp.TimeoutExpired:
            pass


def purge():
    path = directory()
    with locked(path):
        (path / 'db').unlink(missing_ok=True)
        shutil.rmtree(path / 'rofi-cache', ignore_errors=True)
    clear_selection()


def resume():
    if (runtime() / 'dotfiles-screen-locked').exists():
        raise RuntimeError('Clipboard recording cannot be resumed while locked')
    if not active('wayland-session@hyprland.desktop.target'):
        raise RuntimeError('Clipboard history is only enabled in the Hyprland session')
    run(['systemctl', '--user', 'start', UNIT])


def main(action):
    os.umask(0o077)
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    if action == 'status':
        print('on' if active() else 'paused')
        return
    if action in ('pause', 'clear', 'toggle', 'resume'):
        was_active = active()
        if action == 'resume' or (action == 'toggle' and not was_active):
            resume()
        else:
            # PartOf stops the selector too; no stale preview/selection survives.
            run(['systemctl', '--user', 'stop', MENU, UNIT])
            purge()
            if action == 'clear' and was_active:
                resume()
        return
    if action == 'purge':
        purge()
        return
    path = directory()
    if action == 'watch':
        if (runtime() / 'dotfiles-screen-locked').exists():
            raise RuntimeError('Refusing to record clipboard while locked')
        purge()  # Do not ingest a password copied while recording was paused.
        os.execvp('wl-paste', ['wl-paste', '--type', 'text', '--watch',
                              os.environ['DOTFILES_CLIPBOARD_SELF'], 'store'])
    elif action == 'store':
        if os.environ.get('CLIPBOARD_STATE', 'data') in ('sensitive', 'nil', 'clear'):
            return
        if (runtime() / 'dotfiles-screen-locked').exists() or not active():
            return
        data = sys.stdin.buffer.read(MAX_BYTES + 1)
        if not data.strip() or len(data) > MAX_BYTES:
            return
        with locked(path):
            cliphist(path, 'store', data)
    elif action == 'menu':
        if not active() or not (path / 'db').exists():
            return
        with locked(path):
            rows = cliphist(path, 'list').splitlines()
        if not rows:
            return
        cache = path / 'rofi-cache'
        cache.mkdir(mode=0o700, exist_ok=True)
        env = dict(os.environ, XDG_CACHE_HOME=str(cache))
        result = sp.run(['rofi', '-dmenu', '-i', '-no-custom', '-no-history',
                         '-format', 'i', '-display-columns', '2', '-p', 'Clipboard'],
                        input=b'\n'.join(rows) + b'\n', stdout=sp.PIPE,
                        stderr=sp.DEVNULL, env=env)
        if result.returncode != 0:
            return  # Escape is cancellation, not an error.
        try:
            index = int(result.stdout.strip())
        except ValueError:
            return
        if not 0 <= index < len(rows) or not active():
            return
        with locked(path):
            if not (path / 'db').exists():
                return
            data = cliphist(path, 'decode', rows[index] + b'\n')
        # Selection only copies; it never types into a terminal or executes text.
        run(['wl-copy', '--type', 'text/plain;charset=utf-8'], input=data,
            stdout=sp.DEVNULL, stderr=sp.DEVNULL)
    else:
        raise RuntimeError('Unknown clipboard action')


if __name__ == '__main__':
    try:
        main(sys.argv[1] if len(sys.argv) == 2 else 'menu')
    except (OSError, RuntimeError, sp.SubprocessError) as error:
        # Never include clipboard payloads or subprocess stdin in diagnostics.
        print(f'desktop-clipboard: {type(error).__name__}; check session/storage setup', file=sys.stderr)
        sys.exit(1)

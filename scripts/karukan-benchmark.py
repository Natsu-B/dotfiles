"""Measure the built Fcitx engine without touching the desktop session."""
import ctypes as C
import json
import os
from pathlib import Path
import resource
import tempfile
import time

isolated = None
live = os.environ.get('BENCH_LIVE') == '1'
if os.environ.get('BENCH_MODEL'):
    model = Path(os.environ['BENCH_MODEL']).expanduser().absolute()
    assert model.is_file() and model.with_name('tokenizer.json').is_file()
    isolated = tempfile.TemporaryDirectory(prefix='karukan-benchmark-')
    for variable, directory in [('XDG_CONFIG_HOME', 'config'), ('XDG_DATA_HOME', 'data'),
                                ('XDG_CACHE_HOME', 'cache')]:
        os.environ[variable] = str(Path(isolated.name) / directory)
    config = Path(os.environ['XDG_CONFIG_HOME']) / 'karukan-im/config.toml'
    config.parent.mkdir(parents=True)
    config.write_text('[conversion]\nmodel = "bench"\nstrategy = "main"\nn_threads = 4\n'
                      'num_candidates = 9\nlive_conversion = ' + str(live).lower() + '\nmax_latency_ms = 0\n'
                      'use_context = true\ncontext_chars = 10\n'
                      '[learning]\nenabled = false\n'
                      '[display]\ncandidate_window = "conversion"\n'
                      '[models]\nbench = ' + json.dumps(str(model)) + '\n')
elif not all(os.environ.get(name) for name in ['XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_CACHE_HOME']):
    raise SystemExit('Set BENCH_MODEL to a local GGUF with tokenizer.json to isolate the benchmark.')

if os.environ.get('BENCH_FRONTEND_BINARY'):
    import subprocess
    subprocess.run([os.environ['BENCH_FRONTEND_BINARY']], check=True)
    raise SystemExit(0)


def gpu_time():
    clients = {}
    for path in Path('/proc/self/fdinfo').glob('*'):
        try:
            lines = path.read_text().splitlines()
        except OSError:
            continue
        values = dict(line.split(':', 1) for line in lines if ':' in line)
        client = values.get('drm-client-id')
        if client is not None:
            clients[client] = {k: int(v.strip().split()[0]) for k, v in values.items()
                               if k.startswith('drm-engine-') and v.strip().endswith(' ns')}
    total = {}
    for values in clients.values():
        for key, value in values.items():
            total[key] = total.get(key, 0) + value
    return total


def accelerator_fds():
    devices = []
    for path in Path('/proc/self/fd').glob('*'):
        try:
            target = str(path.resolve())
            if target.startswith(('/dev/accel/', '/dev/dri/')):
                devices.append(target)
        except OSError:
            pass
    return sorted(set(devices))


def emit(value):
    print(json.dumps(value, ensure_ascii=False), flush=True)


package = Path(os.environ['BENCH_PACKAGE'])
os.environ['RUST_LOG'] = os.environ.get('BENCH_RUST_LOG', 'info')
addon = C.CDLL(str(package / 'lib/fcitx5/karukan.so'), mode=C.RTLD_GLOBAL)
lib = C.CDLL(str(package / 'lib/fcitx5/libkarukan_fcitx5.so'))


def bind(name, result, args):
    fn = getattr(lib, 'karukan_engine_' + name)
    fn.restype = result
    fn.argtypes = args
    return fn


new = bind('new', C.c_void_p, [])
init = bind('init', C.c_int, [C.c_void_p])
free = bind('free', None, [C.c_void_p])
reset = bind('reset', None, [C.c_void_p])
key = bind('process_key', C.c_int, [C.c_void_p, C.c_uint, C.c_uint, C.c_int])
candidate = bind('get_candidate', C.c_char_p, [C.c_void_p, C.c_uint])
aux = bind('get_aux', C.c_char_p, [C.c_void_p])
preedit = bind('get_preedit', C.c_char_p, [C.c_void_p])
commit = bind('get_commit', C.c_char_p, [C.c_void_p])
conversion_ms = bind('get_last_conversion_ms', C.c_uint64, [C.c_void_p])
asynchronous = os.environ.get('BENCH_ASYNC') == '1'
if asynchronous:
    poll_live = bind('poll_live', C.c_int, [C.c_void_p])
    async_pending = bind('async_pending', C.c_int, [C.c_void_p])
    is_empty = bind('is_empty', C.c_int, [C.c_void_p])
    has_preedit = bind('has_preedit', C.c_int, [C.c_void_p])
    has_commit = bind('has_commit', C.c_int, [C.c_void_p])


def wait_live(engine):
    if not asynchronous:
        return 0
    started = time.perf_counter()
    while True:
        poll_live(engine)
        if not async_pending(engine):
            return (time.perf_counter() - started) * 1000
        if time.perf_counter() - started > 15:
            raise RuntimeError('live conversion did not settle within 15 seconds')
        time.sleep(0.008)

log = Path(os.environ['BENCH_LOG'])


def create_engine():
    offset = len(log.read_text(errors='replace'))
    start = time.perf_counter()
    engine = new()
    assert engine
    assert init(engine) == 0
    deadline = time.monotonic() + 45
    while 'Main model loaded:' not in log.read_text(errors='replace')[offset:]:
        if time.monotonic() > deadline:
            raise RuntimeError('model did not load within 45 seconds')
        time.sleep(0.05)
    key(engine, 0xff1b, 0, 0)  # Poll the completed background model load.
    emit({'kind': 'ready', 'device': os.environ.get('GGML_OPENVINO_DEVICE', 'CPU'),
          'load_ms': (time.perf_counter() - start) * 1000, 'gpu_engines': gpu_time(), 'accelerator_fds': accelerator_fds(),
          'driver_libraries': sorted({line.split()[-1] for line in Path('/proc/self/maps').read_text().splitlines()
                                      if 'libze_intel_npu' in line or 'npu_compiler' in line or 'libnpu_driver_compiler' in line})})
    return engine


engine = create_engine()
if asynchronous:
    # Discarded/reset/committed compositions must never receive a late rewrite.
    for raw, finish in [('nihongo', 'reset'), ('kyouhaiitenkidesu', 'commit')]:
        reset(engine)
        for character in raw:
            key(engine, ord(character), 0, 0)
        if finish == 'reset':
            reset(engine)
        else:
            key(engine, 0xff0d, 0, 0)
            assert (commit(engine) or b'').decode() == '今日はいい天気です', commit(engine)
        wait_live(engine)
        # Cached getter bytes survive Commit; dirty flags describe new UI actions.
        assert is_empty(engine), (finish, preedit(engine))
        assert not has_preedit(engine), ('late preedit after', finish)
        assert not has_commit(engine), ('late commit after', finish)
        emit({'kind': 'async_invalidation', 'finish': finish})
    reset(engine)
    for character in 'nihongo':
        key(engine, ord(character), 0, 0)
    key(engine, 0xff08, 0, 0)
    key(engine, 0xff08, 0, 0)
    for character in 'njinn':
        key(engine, ord(character), 0, 0)
    edited_settle = wait_live(engine)
    assert (preedit(engine) or b'').decode() == '日本人', preedit(engine)
    emit({'kind': 'async_edit', 'preedit': '日本人', 'settle_ms': edited_settle})
    reset(engine)
    for character in 'toukyou':
        key(engine, ord(character), 0, 0)
    key(engine, ord('l'), 5, 0)  # Ctrl+Shift+L: turn live conversion off in flight.
    wait_live(engine)
    assert (preedit(engine) or b'').decode() == 'とうきょう', preedit(engine)
    key(engine, ord('l'), 5, 0)
    wait_live(engine)
    assert (preedit(engine) or b'').decode() == '東京', preedit(engine)
    emit({'kind': 'async_toggle', 'preedit': '東京'})
    reset(engine)
    if os.environ.get('BENCH_LONG') == '1':
        # More than one chunk: each later chunk needs the preceding conversion
        # as context. This catches starvation from replacing prefix requests.
        raw = 'watashihanihongowobenkyoushiteimasu' * 3
        key_times = []
        for character in raw:
            started = time.perf_counter_ns()
            key(engine, ord(character), 0, 0)
            key_times.append((time.perf_counter_ns() - started) / 1e6)
        settled_ms = wait_live(engine)
        live_text = (preedit(engine) or b'').decode()
        assert any('\u4e00' <= c <= '\u9fff' for c in live_text), live_text
        key(engine, ord(' '), 0, 0)
        explicit_text = (candidate(engine, 0) or b'').decode()
        assert explicit_text == live_text, (live_text, explicit_text)
        emit({'kind': 'async_long', 'romaji_chars': len(raw), 'preedit': live_text,
              'max_key_ms': max(key_times), 'settle_ms': settled_ms})
        reset(engine)
if os.environ.get('BENCH_CONTEXT') == '1':
    surrounding = bind('set_surrounding_text', None, [C.c_void_p, C.c_char_p, C.c_uint])
    for context, raw, expected_context in [
        ('銀行にお金を預ける', 'kouza', '口座'), ('大学で授業を受ける', 'kouza', '講座'),
        ('川の向こうへ渡る', 'hashi', '橋'), ('ご飯を食べる道具', 'hashi', '箸'),
        ('夏休みに故郷へ帰る', 'kisei', '帰省'), ('交通ルールで制限する', 'kisei', '規制'),
        ('紙に文章を書く', 'kaku', '書く'), ('鉛筆で絵を描く', 'kaku', '描く'),
    ]:
        reset(engine)
        surrounding(engine, context.encode(), len(context))
        times = []
        for character in raw:
            started = time.perf_counter_ns()
            key(engine, ord(character), 0, 0)
            times.append((time.perf_counter_ns() - started) / 1e6)
        settle_ms = wait_live(engine)
        key(engine, ord(' '), 0, 0)
        result = (candidate(engine, 0) or b'').decode()
        emit({'kind': 'context', 'context': context, 'romaji': raw,
              'candidate': result, 'expected': expected_context,
              'correct': result == expected_context, 'max_key_ms': max(times),
              'settle_ms': settle_ms})
    reset(engine)
    surrounding(engine, b'', 0)
if os.environ.get('BENCH_PENDING_ROMAJI') == '1':
    assert live, 'pending-romaji checks require live conversion'
    for raw, pending_indices in [('k', {0}), ('sh', {0, 1}),
                                 ('nihongo', {0, 2, 4, 5}), ('kan', {0, 2}),
                                 ('kann', {0, 2})]:
        reset(engine)
        for index, character in enumerate(raw):
            assert key(engine, ord(character), 0, 0) == 1
            shown = (preedit(engine) or b'').decode()
            elapsed = conversion_ms(engine)
            if index in pending_indices:
                assert elapsed == 0, (raw, index, shown, elapsed)
                assert shown.endswith(character), (raw, index, shown)
            emit({'kind': 'pending_romaji', 'raw': raw, 'index': index,
                  'preedit': shown, 'engine_inference_ms': elapsed})
        if raw == 'nihongo':
            wait_live(engine)
            assert (preedit(engine) or b'').decode() == '日本語'
        if raw in ('kan', 'kann'):
            key(engine, 0xff0d, 0, 0)
            committed = (commit(engine) or b'').decode()
            # Upstream deliberately flushes a lone n literally; nn is settled ん.
            if raw == 'kan':
                assert committed == 'かn', ('pending-n commit', committed)
            else:
                assert committed and not committed.endswith('n'), ('settled-n commit', committed)
            emit({'kind': 'pending_commit', 'raw': raw, 'commit': committed})
    reset(engine)
    for character in 'shi':
        key(engine, ord(character), 0, 0)
    key(engine, 0xff08, 0, 0)
    assert conversion_ms(engine) == 0
    key(engine, 0xff1b, 0, 0)
    assert not preedit(engine)
    reset(engine)
if os.environ.get('BENCH_C_ALIAS') == '1':
    for raw, expected_preedit in [('ca', 'か'), ('ci', 'き'), ('cu', 'く'), ('ce', 'け'),
                                 ('co', 'こ'), ('cya', 'きゃ'), ('cca', 'っか'),
                                 ('cka', 'っか'), ('Cc', 'Cc')]:
        reset(engine)
        for character in raw:
            assert key(engine, ord(character), 0, 0) == 1
        shown = (preedit(engine) or b'').decode()
        assert shown == expected_preedit, (raw, shown, expected_preedit)
        emit({'kind': 'alias', 'raw': raw, 'preedit': shown})
    reset(engine)
phrases = [('nihongo', 'にほんご'), ('kyouhaiitenkidesu', 'きょうはいいてんきです'),
           ('watashihanihongowobenkyoushiteimasu', 'わたしはにほんごをべんきょうしています'),
           ('toukyou', 'とうきょう'), ('arigatougozaimasu', 'ありがとうございます')]
expected = {'にほんご': '日本語', 'きょうはいいてんきです': '今日はいい天気です',
            'わたしはにほんごをべんきょうしています': 'わたしは日本語を勉強しています',
            'とうきょう': '東京', 'ありがとうございます': 'ありがとうございます'}
phrases = phrases[:int(os.environ.get('BENCH_PHRASE_LIMIT', '5'))]
if os.environ.get('BENCH_C_ALIAS') == '1':
    phrases = [(raw.replace('k', 'c'), reading) for raw, reading in phrases]
try:
    seconds = float(os.environ.get('BENCH_SECONDS', '0'))
    deadline = time.monotonic() + seconds
    for repetition in range(10000 if seconds else int(os.environ.get('BENCH_REPETITIONS', '4'))):
        if seconds and time.monotonic() >= deadline:
            break
        if repetition and os.environ.get('BENCH_FRESH_ENGINE') == '1':
            free(engine)
            engine = create_engine()
        for romaji, reading in phrases:
            reset(engine)
            before_gpu = gpu_time()
            before_cpu = time.process_time_ns()
            before = time.perf_counter_ns()
            events = []
            settle_ms = 0
            last_input_at = None
            settled_at = None
            interval = float(os.environ.get('BENCH_KEY_INTERVAL_MS', '0')) / 1000
            for index, ch in enumerate(romaji + ' '):
                scheduled = before / 1e9 + index * interval
                while time.perf_counter() < scheduled:
                    if asynchronous:
                        poll_live(engine)
                        if index == len(romaji) and settled_at is None and not async_pending(engine):
                            settled_at = time.perf_counter()
                    time.sleep(min(0.008, max(0, scheduled - time.perf_counter())))
                if ch == ' ':
                    settle_ms = wait_live(engine)
                    if asynchronous and settled_at is None:
                        settled_at = time.perf_counter()
                key_start = time.perf_counter_ns()
                cpu_start = time.process_time_ns()
                assert key(engine, ord(ch), 0, 0) == 1
                if index == len(romaji) - 1:
                    last_input_at = time.perf_counter()
                event = {'kind': 'key', 'repetition': repetition, 'reading': reading,
                         'index': index, 'key': ch,
                         'wall_ms': (time.perf_counter_ns() - key_start) / 1e6,
                         'cpu_ms': (time.process_time_ns() - cpu_start) / 1e6,
                         'engine_inference_ms': conversion_ms(engine)}
                events.append(event)
                emit(event)
            wall_ms = (time.perf_counter_ns() - before) / 1e6
            cpu_ms = (time.process_time_ns() - before_cpu) / 1e6
            after_gpu = gpu_time()
            converted = (candidate(engine, 0) or b'').decode()
            auxiliary = (aux(engine) or b'').decode()
            model_used = '🤖 AI' in auxiliary
            if os.environ.get('BENCH_REQUIRE_CORRECT') == '1':
                assert converted == expected[reading], (reading, converted)
                assert model_used, auxiliary
                if not live:
                    assert all(e['engine_inference_ms'] == 0 for e in events[:-1]), events
            emit({'kind': 'sample', 'repetition': repetition, 'reading': reading,
                  'candidate': converted, 'model_used': model_used,
                  'correct': converted == expected[reading] and model_used,
                  'accelerator_fds': accelerator_fds(),
                  'aux': auxiliary,
                  'wall_ms': wall_ms, 'cpu_ms': cpu_ms,
                  'typing_ms': sum(e['wall_ms'] for e in events[:-1]),
                  'space_ms': events[-1]['wall_ms'],
                  'settle_ms': settle_ms,
                  'after_last_input_ms': max(0, (settled_at - last_input_at) * 1000) if asynchronous else 0,
                  'max_key_ms': max(e['wall_ms'] for e in events),
                  'engine_inference_ms': conversion_ms(engine),
                  'gpu_ms': {k: (v - before_gpu.get(k, 0)) / 1e6 for k, v in after_gpu.items()},
                  'maxrss_kib': resource.getrusage(resource.RUSAGE_SELF).ru_maxrss})
            if os.environ.get('BENCH_TYPE_TO_COMMIT') == '1':
                assert key(engine, ord(' '), 0, 0) == 1  # Select the next candidate.
                selected = (candidate(engine, 1) or b'').decode()
                # The FFI exposes the full list; Space has advanced to index 1.
                assert selected
                assert key(engine, ord('c'), 0, 0) == 1
                committed = (commit(engine) or b'').decode()
                assert committed == selected, (committed, selected)
                assert (preedit(engine) or b'').decode() == 'k'
                assert key(engine, ord('a'), 0, 0) == 1
                assert (preedit(engine) or b'').decode() == 'か'
                emit({'kind': 'type_to_commit', 'committed': committed, 'next_preedit': 'か'})
finally:
    free(engine)
    if isolated is not None:
        isolated.cleanup()

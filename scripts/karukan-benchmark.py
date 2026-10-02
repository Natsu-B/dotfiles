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
os.environ['RUST_LOG'] = 'info'
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
conversion_ms = bind('get_last_conversion_ms', C.c_uint64, [C.c_void_p])

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
            for index, ch in enumerate(romaji + ' '):
                key_start = time.perf_counter_ns()
                cpu_start = time.process_time_ns()
                assert key(engine, ord(ch), 0, 0) == 1
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
                  'max_key_ms': max(e['wall_ms'] for e in events),
                  'engine_inference_ms': conversion_ms(engine),
                  'gpu_ms': {k: (v - before_gpu.get(k, 0)) / 1e6 for k, v in after_gpu.items()},
                  'maxrss_kib': resource.getrusage(resource.RUSAGE_SELF).ru_maxrss})
finally:
    free(engine)
    if isolated is not None:
        isolated.cleanup()

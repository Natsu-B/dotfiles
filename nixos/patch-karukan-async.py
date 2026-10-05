"""Apply the asynchronous live-conversion extension to the pinned engine."""
from pathlib import Path
import sys


def replace(root, name, old, new, count=1):
    path = root / name
    text = path.read_text()
    if text.count(old) != count:
        raise SystemExit(f'{name}: expected {count} matches for {old!r}')
    path.write_text(text.replace(old, new))


def main(root, module):
    core = 'karukan-im/core/src/core/engine/'
    (root / core / 'async_live.rs').write_text(module.read_text())
    replace(root, core + 'mod.rs', 'mod cache;', 'mod async_live;\nmod cache;')
    replace(root, core + 'mod.rs', '    suppress_suggest: bool,',
            '    suppress_suggest: bool,\n    async_live: Option<async_live::AsyncLive>,\n'
            '    async_live_active: bool,\n    async_live_requested: bool,')
    replace(root, core + 'mod.rs', '            suppress_suggest: false,',
            '            suppress_suggest: false,\n            async_live: None,\n'
            '            async_live_active: false,\n            async_live_requested: false,')
    replace(root, core + 'mod.rs', '        self.poll_loaded_models();',
            '        self.poll_loaded_models();\n        self.drain_live_results();')
    replace(root, core + 'mod.rs', '    pub(super) fn clear_composition(&mut self) {',
            '    pub(super) fn clear_composition(&mut self) {\n'
            '        if let Some(worker) = &self.async_live { worker.cancel_queued(); }')
    replace(root, core + 'types.rs', 'Option<KanaKanjiConverter>',
            'Option<std::sync::Arc<super::async_live::SharedConverter>>', count=2)
    replace(root, core + 'init.rs', 'self.converters.kanji = Some(loaded.kanji);',
            'self.converters.kanji = Some(std::sync::Arc::new(async_live::SharedConverter::new(loaded.kanji)));')
    replace(root, core + 'init.rs', 'self.converters.light_kanji = loaded.light_kanji;',
            'self.converters.light_kanji = loaded.light_kanji.map(|c| std::sync::Arc::new(async_live::SharedConverter::new(c)));\n'
            '                if std::env::var("KARUKAN_ASYNC_LIVE").as_deref() == Ok("1") {\n'
            '                    self.async_live = async_live::AsyncLive::start();\n                }')
    replace(root, core + 'input.rs', '            self.chunked_auto_suggest()\n',
            '            self.async_live_active = self.live.enabled && self.async_live.is_some();\n'
            '            self.async_live_requested = false;\n'
            '            let suggested = self.chunked_auto_suggest();\n'
            '            self.async_live_active = false;\n            suggested\n')
    replace(root, core + 'input.rs', '            Keysym::RETURN => self.commit_composing(),',
            '            Keysym::RETURN => self.commit_live_composing(),')
    replace(root, core + 'model.rs', '        let Some(converter) = self.converter_for(model) else {',
            '        if self.async_live_active {\n'
            '            if !self.async_live_requested {\n'
            '                let converter = match model {\n'
            '                    ModelRole::Main => self.converters.kanji.clone(),\n'
            '                    ModelRole::Light => self.converters.light_kanji.clone(),\n                };\n'
            '                if let (Some(worker), Some(converter)) = (&self.async_live, converter) {\n'
            '                    worker.submit(Self::cache_key(model, beam_width, katakana, lctx), converter);\n'
            '                    self.async_live_requested = true;\n                }\n            }\n'
            '            return (Vec::new(), None);\n        }\n'
            '        let Some(converter) = self.converter_for(model) else {')
    replace(root, core + 'model.rs', 'Option<&KanaKanjiConverter>', 'Option<&async_live::SharedConverter>')
    replace(root, core + 'model.rs', 'self.converters.kanji.as_ref(),', 'self.converters.kanji.as_deref(),')
    replace(root, core + 'model.rs', 'self.converters.light_kanji.as_ref(),', 'self.converters.light_kanji.as_deref(),')
    ffi = 'karukan-im/fcitx5/'
    path = root / ffi / 'src/ffi/input.rs'
    path.write_text(path.read_text() + '''
/// Called only on the Fcitx event thread; workers never access FFI state.
#[unsafe(no_mangle)]
pub extern "C" fn karukan_engine_poll_live(engine: *mut KarukanEngine) -> c_int {
    let engine = ffi_mut!(engine, 0);
    engine.clear_flags();
    let result = engine.engine.poll_live_conversion();
    let changed = !result.actions.is_empty();
    engine.apply_actions(result.actions);
    engine.sync_timing();
    changed as c_int
}

#[unsafe(no_mangle)]
pub extern "C" fn karukan_engine_async_pending(engine: *mut KarukanEngine) -> c_int {
    let engine = ffi_mut!(engine, 0);
    engine.engine.async_pending() as c_int
}
''')
    replace(root, ffi + 'include/karukan.h', 'void karukan_engine_reset(KarukanEngine* engine);',
            'void karukan_engine_reset(KarukanEngine* engine);\n'
            'int karukan_engine_poll_live(KarukanEngine* engine);\n'
            'int karukan_engine_async_pending(KarukanEngine* engine);')
    addon = ffi + 'fcitx5-addon/src/'
    replace(root, addon + 'karukan.h', '#include <fcitx/addonfactory.h>',
            '#include <fcitx-utils/event.h>\n#include <fcitx/addonfactory.h>')
    replace(root, addon + 'karukan.h', '    void emitPendingCommit();',
            '    void emitPendingCommit();\n    void armAsync();')
    replace(root, addon + 'karukan.h', '    bool engineInitialized_{false};',
            '    bool engineInitialized_{false};\n    std::unique_ptr<EventSourceTime> asyncTimer_;')
    replace(root, addon + 'karukan.h', '    void selectCandidate(InputContext* ic, int index);',
            '    void selectCandidate(InputContext* ic, int index);\n'
            '    Instance* instance() const { return instance_; }')
    replace(root, addon + 'karukan.cpp', 'KarukanState::~KarukanState() {',
            'KarukanState::~KarukanState() {\n    asyncTimer_.reset();')
    replace(root, addon + 'karukan.cpp', '    updateUI();\n}\n\nvoid KarukanState::reset()',
            '    updateUI();\n    armAsync();\n}\n\nvoid KarukanState::reset()')
    replace(root, addon + 'karukan.cpp', 'void KarukanState::reset() {',
            'void KarukanState::reset() {\n    asyncTimer_.reset();')
    replace(root, addon + 'karukan.cpp', 'void KarukanState::updateUI() {', '''void KarukanState::armAsync() {
    if (!rustEngine_ || !karukan_engine_async_pending(rustEngine_)) { return; }
    if (asyncTimer_) {
        if (!asyncTimer_->isEnabled()) {
            asyncTimer_->setTime(now(CLOCK_MONOTONIC) + 8000);
            asyncTimer_->setOneShot();
        }
        return;
    }
    asyncTimer_ = engine_->instance()->eventLoop().addTimeEvent(
        CLOCK_MONOTONIC, now(CLOCK_MONOTONIC) + 8000, 1000,
        [this](EventSourceTime* source, uint64_t) {
            if (!ic_->hasFocus()) { source->setEnabled(false); return true; }
            if (karukan_engine_poll_live(rustEngine_)) { updateUI(); }
            if (karukan_engine_async_pending(rustEngine_)) {
                source->setTime(now(CLOCK_MONOTONIC) + 8000);
                source->setOneShot();
            } else { source->setEnabled(false); }
            return true;
        });
    asyncTimer_->setOneShot();
}

void KarukanState::updateUI() {''')


if __name__ == '__main__':
    main(Path(sys.argv[1]), Path(sys.argv[2]))

//! Non-blocking live conversion. One running job and one replaceable queued job.
//! The worker owns no engine/UI pointers; results enter the content-addressed cache.
use std::sync::{Arc, Condvar, Mutex};
use std::time::Instant;

use karukan_engine::KanaKanjiConverter;

use super::cache::ConversionCacheKey;
use super::*;

// Serialize explicit and background calls to the same model. Reuse the last
// answer when Space arrives while its live request is still running.
pub(super) struct SharedConverter {
    converter: KanaKanjiConverter,
    last: Mutex<Option<(String, String, usize, Vec<String>)>>,
}

impl SharedConverter {
    pub fn new(converter: KanaKanjiConverter) -> Self {
        Self { converter, last: Mutex::new(None) }
    }

    pub fn model_display_name(&self) -> &str {
        self.converter.model_display_name()
    }

    pub fn convert(&self, reading: &str, context: &str, count: usize) -> anyhow::Result<Vec<String>> {
        let mut last = self.last.lock().unwrap_or_else(|e| e.into_inner());
        if let Some((r, c, n, result)) = last.as_ref() {
            if r == reading && c == context && *n == count {
                return Ok(result.clone());
            }
        }
        let result = self.converter.convert(reading, context, count)?;
        if !result.is_empty() {
            *last = Some((reading.to_owned(), context.to_owned(), count, result.clone()));
        }
        Ok(result)
    }
}

struct Job {
    key: ConversionCacheKey,
    converter: Arc<SharedConverter>,
}

#[derive(Default)]
struct Slots {
    queued: Option<Job>,
    running: Option<ConversionCacheKey>,
    ready: Option<(ConversionCacheKey, Vec<String>, u64)>,
    stopped: bool,
}

pub(super) struct AsyncLive {
    slots: Arc<(Mutex<Slots>, Condvar)>,
}

impl AsyncLive {
    pub fn start() -> Option<Self> {
        let slots = Arc::new((Mutex::new(Slots::default()), Condvar::new()));
        let worker = Arc::clone(&slots);
        let spawned = std::thread::Builder::new().name("karukan-live".into()).spawn(move || {
            let (lock, wake) = &*worker;
            loop {
                let job = {
                    let mut state = lock.lock().unwrap_or_else(|e| e.into_inner());
                    while state.queued.is_none() && !state.stopped {
                        state = wake.wait(state).unwrap_or_else(|e| e.into_inner());
                    }
                    if state.stopped { break; }
                    let job = state.queued.take().unwrap();
                    state.running = Some(job.key.clone());
                    job
                };
                // Never hold the mailbox lock during GPU inference.
                let start = Instant::now();
                let result = job.converter.convert(&job.key.katakana, &job.key.lctx, job.key.beam_width)
                    .unwrap_or_else(|error| {
                        tracing::warn!(%error, "Karukan live conversion failed");
                        Vec::new()
                    });
                let elapsed = start.elapsed().as_millis() as u64;
                let mut state = lock.lock().unwrap_or_else(|e| e.into_inner());
                state.running = None;
                if state.stopped { break; }
                state.ready = Some((job.key, result, elapsed));
            }
        });
        match spawned {
            Ok(_) => Some(Self { slots }),
            Err(error) => { tracing::error!(%error, "Karukan live worker unavailable"); None }
        }
    }

    pub fn submit(&self, key: ConversionCacheKey, converter: Arc<SharedConverter>) {
        let (lock, wake) = &*self.slots;
        let mut state = lock.lock().unwrap_or_else(|e| e.into_inner());
        if state.running.as_ref() == Some(&key)
            || state.ready.as_ref().map(|r| &r.0) == Some(&key) {
            state.queued = None;
            return;
        }
        if state.queued.as_ref().map(|j| &j.key) == Some(&key) {
            return;
        }
        // Replace superseded requests instead of building a typing backlog.
        state.queued = Some(Job { key, converter });
        wake.notify_one();
    }

    pub fn take_ready(&self) -> Option<(ConversionCacheKey, Vec<String>, u64)> {
        self.slots.0.lock().unwrap_or_else(|e| e.into_inner()).ready.take()
    }

    pub fn pending(&self) -> bool {
        let state = self.slots.0.lock().unwrap_or_else(|e| e.into_inner());
        state.queued.is_some() || state.running.is_some() || state.ready.is_some()
    }

    pub fn cancel_queued(&self) {
        let mut state = self.slots.0.lock().unwrap_or_else(|e| e.into_inner());
        state.queued = None;
        state.ready = None;
    }
}

impl Drop for AsyncLive {
    fn drop(&mut self) {
        let (lock, wake) = &*self.slots;
        let mut state = lock.lock().unwrap_or_else(|e| e.into_inner());
        state.stopped = true;
        state.queued = None;
        wake.notify_one();
        // Do not join a GPU inference on the event thread. The worker's Arc
        // keeps all its data alive until it finishes, without a raw UI pointer.
    }
}

impl InputMethodEngine {
    pub(super) fn async_live_preedit(&mut self) -> Option<Preedit> {
        if self.async_live.is_none() || !self.live.enabled || self.suppress_suggest
            || self.mode.current() != InputMode::Hiragana
            || self.input_buf.cursor() != self.input_buf.char_count() {
            return None;
        }
        if !self.async_live_requested && self.input_buf.pending().is_empty() {
            self.async_live_preview = self.live.shown.then(|| {
                (self.input_buf.reading(), self.live_text())
            });
            return None;
        }
        // Display-only: never turn this draft into a model cache entry or candidate.
        // A changed/deleted prefix has no trustworthy reading-to-kanji mapping.
        let (reading, converted) = self.async_live_preview.as_ref()?;
        let display = self.build_input_display();
        let tail = display.strip_prefix(reading)?;
        let display = format!("{converted}{tail}");
        let mut preedit = Preedit::with_text_underlined(&display);
        preedit.set_caret(display.chars().count());
        Some(preedit)
    }

    pub(super) fn commit_live_composing(&mut self) -> EngineResult {
        // Keep character input asynchronous, but an explicit Enter must commit
        // the current reading's AI answer rather than an unfinished kana draft.
        if self.live.enabled && self.async_live.is_some()
            && self.input_buf.pending().is_empty()
            && self.mode.current() == InputMode::Hiragana {
            self.drain_live_results();
            if let Some(worker) = &self.async_live { worker.cancel_queued(); }
            self.async_live_active = false;
            self.live.shown = self.chunked_auto_suggest().is_some();
        }
        self.commit_composing()
    }

    pub(super) fn drain_live_results(&mut self) -> bool {
        let Some((key, candidates, elapsed)) = self.async_live.as_ref().and_then(|w| w.take_ready()) else {
            return false;
        };
        if candidates.is_empty() { return false; }
        self.conversion_cache.insert(key, candidates);
        tracing::debug!(elapsed, "Karukan asynchronous conversion finished");
        true
    }

    pub fn async_pending(&self) -> bool {
        self.model_loading.is_some() || self.async_live.as_ref().is_some_and(|w| w.pending())
    }

    pub fn poll_live_conversion(&mut self) -> EngineResult {
        let was_loading = self.model_loading.is_some();
        self.poll_loaded_models();
        let changed = self.drain_live_results()
            || (was_loading && self.model_loading.is_none());
        if changed && self.live.enabled && matches!(self.state, InputState::Composing { .. }) {
            // Rebuild from the CURRENT reading/context. An old result is only a
            // cache entry; it can never overwrite newer input or committed text.
            let result = self.refresh_input_state();
            self.hide_candidate_window(result)
        } else {
            EngineResult::default()
        }
    }
}

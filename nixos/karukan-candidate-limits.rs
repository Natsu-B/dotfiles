//! Conservative limits on unsolicited continuations, measured in Unicode chars.
//! Dictionary/history candidates have readings; model output only has a surface,
//! so its bound catches large expansions without guessing how kanji are read.
pub(super) fn within_limit(reading: &str, candidate: &str) -> bool {
    let chars = reading.chars().count();
    // Allow small completions, but never append more than four characters.
    let extra = (chars / 2).clamp(2, 4);
    candidate.chars().count() <= chars.saturating_add(extra)
}

pub(super) fn filter_model_candidates(reading: &str, candidates: Vec<String>) -> Vec<String> {
    candidates.into_iter().filter(|text| within_limit(reading, text)).collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use super::super::*;

    fn dict() -> Dictionary {
        let file = tempfile::NamedTempFile::new().unwrap();
        // All long entries rank ahead of the short ones, and their compressed
        // kanji surfaces are short: surface-only filtering would miss them.
        std::fs::write(file.path(), r#"[
            {"reading":"わせだだいがく","candidates":[{"surface":"早稲田大学","score":0.0}]},
            {"reading":"わせだまえ","candidates":[{"surface":"早稲田前","score":1.0}]},
            {"reading":"わせだえき","candidates":[{"surface":"早稲田駅","score":2.0}]},
            {"reading":"わせだ","candidates":[{"surface":"早稲田","score":9000.0}]},
            {"reading":"わせだし","candidates":[{"surface":"早稲田市","score":9001.0}]}
        ]"#).unwrap();
        Dictionary::build_from_json(file.path()).unwrap()
    }

    fn seed(engine: &mut InputMethodEngine, candidates: &[&str]) {
        engine.conversion_cache.insert(ConversionCacheKey {
            katakana: "ニホンゴ".into(), lctx: String::new(),
            model: ModelRole::Main, beam_width: 1,
        }, candidates.iter().map(|c| c.to_string()).collect());
    }

    #[test]
    fn unicode_lengths_keep_normal_conversion_and_small_completions() {
        assert!(within_limit("にほんご", "日本語"));
        assert!(within_limit("わせ", "わせだし"));
        assert!(!within_limit("わせ", "わせだえき"));
        assert!(!within_limit("にほんご", "日本語を勉強しています"));
        assert!(!within_limit(&"あ".repeat(40), &"あ".repeat(45)));
        assert!(within_limit("えーあい", "AI"));
    }

    #[test]
    fn model_filter_keeps_order_and_never_truncates_text() {
        let candidates = ["日本語を勉強しています", "日本語", "にほんご", "日本語の長い続き"];
        assert_eq!(filter_model_candidates("にほんご", candidates.map(String::from).to_vec()),
                   vec!["日本語", "にほんご"]);
    }

    #[test]
    fn cached_model_answers_are_filtered_and_all_rejected_fall_back_to_kana() {
        let mut engine = InputMethodEngine::with_config(EngineConfig {
            live_conversion: true, ..EngineConfig::default()
        });
        seed(&mut engine, &["日本語を勉強しています", "日本語"]);
        assert_eq!(engine.run_kana_kanji_conversion("にほんご", "", 1), vec!["日本語"]);
        seed(&mut engine, &["日本語を勉強しています"]);
        for ch in "nihongo".chars() {
            engine.process_key(&KeyEvent::press(Keysym(ch as u32)));
        }
        assert_eq!(engine.preedit().unwrap().text(), "にほんご");
        engine.process_key(&KeyEvent::press(Keysym::SPACE));
        let candidates = engine.candidates().unwrap();
        assert!(candidates.candidates().iter().any(|c| c.text == "にほんご"));
        assert!(candidates.candidates().iter().all(|c| c.text != "日本語を勉強しています"));
    }

    #[test]
    fn dictionary_limits_readings_before_counting_slots_and_keeps_exact_matches() {
        let mut engine = InputMethodEngine::new();
        engine.dicts.system = Some(dict());
        let suggestions = engine.lookup_dict_candidates("わせ");
        assert_eq!(suggestions.iter().map(|c| c.text.as_str()).collect::<Vec<_>>(),
                   vec!["早稲田", "早稲田市"]);
        let mixed = engine.build_conversion_candidates("わせ", "わせ", "", 1, LearningLookup::Use);
        assert!(mixed.iter().any(|c| c.text == "早稲田"));
        assert!(!mixed.iter().any(|c| c.text == "早稲田大学"));
        let exact = engine.lookup_dict_candidates("わせだだいがく");
        assert!(exact.iter().any(|c| c.text == "早稲田大学"));
        // A deliberately registered abbreviation is an exact conversion.
        engine.dicts.user = Some({
            let file = tempfile::NamedTempFile::new().unwrap();
            std::fs::write(file.path(), r#"[{"reading":"よろ","candidates":[{"surface":"よろしくお願いします","score":0.0}]}]"#).unwrap();
            Dictionary::build_from_json(file.path()).unwrap()
        });
        assert!(engine.lookup_dict_candidates("よろ").iter().any(|c| c.text == "よろしくお願いします"));
    }

    #[test]
    fn learning_limits_prefix_predictions_without_deleting_history() {
        let mut engine = InputMethodEngine::new();
        let mut cache = LearningCache::new(LearningConfig::default());
        for _ in 0..10 { cache.record("にほんごをべんきょうしています", "日本語を勉強しています"); }
        cache.record("にほんご", "日本語");
        cache.record("にほんごで", "日本語で");
        engine.learning = Some(cache);
        let candidates = engine.lookup_learning_candidates("にほんご");
        assert!(candidates.iter().any(|c| c.text == "日本語"));
        assert!(candidates.iter().any(|c| c.text == "日本語で"));
        assert!(!candidates.iter().any(|c| c.text == "日本語を勉強しています"));
        let exact = engine.lookup_learning_history("にほんごをべんきょうしています", "");
        assert!(exact.iter().any(|c| c.text == "日本語を勉強しています"));
    }

    #[test]
    fn pending_romaji_still_narrows_short_predictions() {
        let mut engine = InputMethodEngine::new();
        engine.dicts.system = Some(dict());
        for ch in "wased".chars() {
            engine.process_key(&KeyEvent::press(Keysym(ch as u32)));
        }
        let candidates = engine.lookup_dict_candidates("わせ");
        assert!(candidates.iter().any(|c| c.text == "早稲田"));
        assert!(!candidates.iter().any(|c| c.text == "早稲田大学"));
    }
}

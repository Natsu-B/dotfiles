#!/usr/bin/env python3
from pathlib import Path
import re
import sys


def sub(path: Path, pattern: str, replacement: str) -> None:
    text = path.read_text()
    text, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise SystemExit(f"{path}: patch pattern did not match exactly once")
    path.write_text(text)


def main(root: Path) -> None:
    llamacpp = root / "karukan-engine/src/kanji/llamacpp.rs"
    sub(
        llamacpp,
        r"    /// Load a GGUF model using llama\.cpp.*?(?=    /// Load the external tokenizer)",
        '''    /// Load a GGUF model on the CPU backend.\n    pub fn from_file<P: AsRef<Path>, T: AsRef<Path>>(path: P, tokenizer_json: T) -> Result<Self> {\n        Self::from_file_with_n_ctx_and_gpu_layers(path, tokenizer_json, 256, 0)\n    }\n\n    /// Load a GGUF model and offload all available layers to the selected\n    /// accelerator backend. The caller keeps a CPU model as a runtime fallback.\n    pub fn from_file_accelerated<P: AsRef<Path>, T: AsRef<Path>>(\n        path: P,\n        tokenizer_json: T,\n    ) -> Result<Self> {\n        Self::from_file_with_n_ctx_and_gpu_layers(path, tokenizer_json, 256, u32::MAX)\n    }\n\n    /// Load a CPU GGUF model with explicit context window size.\n    pub fn from_file_with_n_ctx<P: AsRef<Path>, T: AsRef<Path>>(\n        path: P,\n        tokenizer_json: T,\n        n_ctx: u32,\n    ) -> Result<Self> {\n        Self::from_file_with_n_ctx_and_gpu_layers(path, tokenizer_json, n_ctx, 0)\n    }\n\n    fn from_file_with_n_ctx_and_gpu_layers<P: AsRef<Path>, T: AsRef<Path>>(\n        path: P,\n        tokenizer_json: T,\n        n_ctx: u32,\n        n_gpu_layers: u32,\n    ) -> Result<Self> {\n        ensure_model_file_exists(path.as_ref())?;\n        let backend = get_backend()?;\n        let model_params = LlamaModelParams::default().with_n_gpu_layers(n_gpu_layers);\n        let model = LlamaModel::load_from_file(backend, path.as_ref(), &model_params)\n            .map_err(|e| KanjiError::ModelLoad(e.into()))?;\n        Self::finish(model, tokenizer_json, n_ctx)\n    }\n\n''',
    )

    backend = root / "karukan-engine/src/kanji/backend.rs"
    sub(
        backend,
        r"use std::path::PathBuf;\n",
        "use std::path::PathBuf;\nuse std::sync::atomic::{AtomicBool, Ordering};\nuse tracing::{info, warn};\n",
    )
    sub(
        backend,
        r"pub struct KanaKanjiConverter \{\n    model: LlamaCppModel,\n    display_name: String,\n\}",
        '''pub struct KanaKanjiConverter {\n    model: LlamaCppModel,\n    cpu_fallback: Option<LlamaCppModel>,\n    accelerator_failed: AtomicBool,\n    accelerator_device: Option<String>,\n    display_name: String,\n}''',
    )
    sub(
        backend,
        r"    /// Load the model at .*?(?=    /// Convert hiragana to kanji candidates)",
        '''    /// Load the selected OpenVINO accelerator plus a native CPU fallback.\n    pub fn from_source(source: &ModelSource, name: &str) -> Result<Self> {\n        let (gguf, tokenizer) = source.resolve()?;\n        let cpu_model = LlamaCppModel::from_file(&gguf, &tokenizer)?;\n        let accelerator_device = std::env::var("GGML_OPENVINO_DEVICE")\n            .ok()\n            .filter(|device| !device.eq_ignore_ascii_case("CPU"));\n\n        if let Some(device) = accelerator_device.as_deref() {\n            match LlamaCppModel::from_file_accelerated(&gguf, &tokenizer) {\n                Ok(model) => {\n                    info!("Karukan {} model loaded for '{}'", device, name);\n                    Ok(KanaKanjiConverter {\n                        model,\n                        cpu_fallback: Some(cpu_model),\n                        accelerator_failed: AtomicBool::new(false),\n                        accelerator_device: Some(device.to_string()),\n                        display_name: name.to_string(),\n                    })\n                }\n                Err(error) => {\n                    warn!(\n                        "Karukan {} load failed for '{}'; using CPU: {}",\n                        device, name, error\n                    );\n                    Ok(KanaKanjiConverter {\n                        model: cpu_model,\n                        cpu_fallback: None,\n                        accelerator_failed: AtomicBool::new(true),\n                        accelerator_device: None,\n                        display_name: name.to_string(),\n                    })\n                }\n            }\n        } else {\n            Ok(KanaKanjiConverter {\n                model: cpu_model,\n                cpu_fallback: None,\n                accelerator_failed: AtomicBool::new(false),\n                accelerator_device: None,\n                display_name: name.to_string(),\n            })\n        }\n    }\n\n    /// Set the number of threads for inference (0 = default).\n    pub fn set_n_threads(&mut self, n: u32) {\n        self.model.set_n_threads(n);\n        if let Some(model) = self.cpu_fallback.as_mut() {\n            model.set_n_threads(n);\n        }\n    }\n\n''',
    )
    sub(
        backend,
        r"    pub fn convert\(.*?(?=    /// Get a human-readable model name)",
        '''    pub fn convert(\n        &self,\n        reading: &str,\n        context: &str,\n        num_candidates: usize,\n    ) -> Result<Vec<String>> {\n        // NPU does not support Karukan's multi-sequence beam path. GPU can\n        // stay on the accelerated backend, so only NPU beam falls back.\n        let npu = self\n            .accelerator_device\n            .as_deref()\n            .is_some_and(|device| device.eq_ignore_ascii_case("NPU"));\n        if num_candidates > 1 && npu {\n            if let Some(cpu_fallback) = self.cpu_fallback.as_ref() {\n                return Self::convert_with_model(cpu_fallback, reading, context, num_candidates);\n            }\n        }\n\n        if self.accelerator_failed.load(Ordering::Relaxed) {\n            if let Some(cpu_fallback) = self.cpu_fallback.as_ref() {\n                return Self::convert_with_model(cpu_fallback, reading, context, num_candidates);\n            }\n        }\n\n        match Self::convert_with_model(&self.model, reading, context, num_candidates) {\n            Ok(candidates) => Ok(candidates),\n            Err(error) => {\n                let Some(cpu_fallback) = self.cpu_fallback.as_ref() else {\n                    return Err(error);\n                };\n                self.accelerator_failed.store(true, Ordering::Relaxed);\n                warn!(\n                    "Karukan {} inference failed for '{}'; retrying on CPU: {}",\n                    self.accelerator_device.as_deref().unwrap_or("accelerator"),\n                    self.display_name,\n                    error\n                );\n                Self::convert_with_model(cpu_fallback, reading, context, num_candidates)\n            }\n        }\n    }\n\n    fn convert_with_model(\n        model: &LlamaCppModel,\n        reading: &str,\n        context: &str,\n        num_candidates: usize,\n    ) -> Result<Vec<String>> {\n        let katakana = hiragana_to_katakana(reading);\n        let prompt = build_jinen_prompt(&katakana, context);\n        let tokens = model.tokenize(&prompt)?;\n        let eos = Some(model.eos_token_id().0);\n        let mut candidates = Vec::with_capacity(num_candidates);\n\n        if num_candidates == 1 {\n            let output_tokens = model.generate(&tokens, MAX_NEW_TOKENS, eos)?;\n            let generated = &output_tokens[tokens.len()..];\n            let text = model.decode(generated, true)?;\n            let clean = clean_model_output(&text);\n            if !clean.is_empty() {\n                candidates.push(clean);\n            }\n        } else {\n            let results =\n                model.generate_beam_search(&tokens, MAX_NEW_TOKENS, eos, num_candidates)?;\n            for (output_tokens, _score) in results {\n                let text = model.decode(&output_tokens, true)?;\n                let clean = clean_model_output(&text);\n                if !clean.is_empty() && !candidates.contains(&clean) {\n                    candidates.push(clean);\n                }\n            }\n        }\n\n        if candidates.is_empty() {\n            candidates.push(reading.to_string());\n        }\n        Ok(candidates)\n    }\n\n''',
    )

    cmake = root / "karukan-im/fcitx5/fcitx5-addon/CMakeLists.txt"
    sub(
        cmake,
        r"    COMMAND \$\{KARUKAN_CARGO_ENV\} \$\{CARGO\} build --release -p karukan-fcitx5\n",
        "    COMMAND \x24{KARUKAN_CARGO_ENV} \x24{CARGO} build --offline --release -p karukan-fcitx5\n",
    )
    # ggml-openvino is built as a static archive inside llama-cpp-sys. Cargo
    # links that archive into libkarukan_fcitx5.so, but it cannot see CMake's
    # transitive OpenVINO/OpenCL link interface. Make the actual Fcitx addon
    # carry those shared-library dependencies so dlopen() has a complete lookup
    # scope for the Rust cdylib.
    sub(
        cmake,
        r"find_package\(PkgConfig REQUIRED\)\n",
        "find_package(PkgConfig REQUIRED)\n"
        "find_package(OpenVINO REQUIRED COMPONENTS Runtime Threading)\n"
        "find_package(OpenCL REQUIRED)\n",
    )
    sub(
        cmake,
        r"""target_link_libraries\(karukan
    Fcitx5::Core
    Fcitx5::Config
    \$\{KARUKAN_RUST_LIB\}
    \$\{XKBCommon_LIBRARIES\}
\)""",
        """target_link_libraries(karukan
    Fcitx5::Core
    Fcitx5::Config
    ${KARUKAN_RUST_LIB}
    ${XKBCommon_LIBRARIES}
    openvino::runtime
    openvino::threading
    OpenCL::OpenCL
)
target_link_options(karukan PRIVATE "LINKER:--no-as-needed")""",
    )

    hf = root / "karukan-engine/src/kanji/hf_download.rs"
    sub(
        hf,
        r"/// Download a GGUF model from HuggingFace Hub\n",
        '''/// Split an optional immutable revision from owner/repo@<40-hex-revision>.\nfn split_repo_revision(repo_id: &str) -> (&str, &str) {\n    if let Some((repo, revision)) = repo_id.rsplit_once('@') {\n        if revision.len() == 40 && revision.bytes().all(|b| b.is_ascii_hexdigit()) {\n            return (repo, revision);\n        }\n    }\n    (repo_id, "main")\n}\n\n/// Download a GGUF model from HuggingFace Hub\n''',
    )
    sub(
        hf,
        r"    let \(owner, name\) = split_id\(repo_id\);\n    let repo = client\.model\(owner, name\);",
        '''    let (repo_id, revision) = split_repo_revision(repo_id);\n    let (owner, name) = split_id(repo_id);\n    let repo = client.model(owner, name);''',
    )
    sub(
        hf,
        r"        \.filename\(filename\)\n        \.local_files_only\(true\)",
        "        .filename(filename)\n        .revision(revision)\n        .local_files_only(true)",
    )
    sub(
        hf,
        r'''    tracing::info!\("Downloading \{\} from \{\}\.\.\.", filename, repo_id\);\n\n    let path = repo\n        \.download_file\(\)\n        \.filename\(filename\)\n        \.send\(\)''',
        '''    tracing::info!(\n        "Downloading {} from {} at revision {}...",\n        filename, repo_id, revision\n    );\n\n    let path = repo\n        .download_file()\n        .filename(filename)\n        .revision(revision)\n        .send()''',
    )


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit(f"usage: {sys.argv[0]} KARUKAN_SOURCE_ROOT")
    main(Path(sys.argv[1]))

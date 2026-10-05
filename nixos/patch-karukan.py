#!/usr/bin/env python3
from pathlib import Path
import re
import sys


def sub(path: Path, pattern: str, replacement: str, expected: int = 1) -> None:
    text = path.read_text()
    text, count = re.subn(pattern, replacement, text, flags=re.S)
    if count != expected:
        raise SystemExit(f"{path}: patch pattern matched {count} times, expected {expected}")
    path.write_text(text)


def main(root: Path) -> None:
    # Typing after candidate selection commits it and starts a new composition.
    sub(
        root / "karukan-im/core/src/core/engine/conversion.rs",
        r"                // A printable character refines instead of committing:\n"
        r"                // the reading grows and the suggestion rewrites in place,\n"
        r"                // keeping any active source filter\.\n"
        r"                if key\.to_char\(\)\.is_some\(\) && !key\.modifiers\.control_key \{\n"
        r"                    return self\.refine_through_composing\(key\);\n"
        r"                }",
        "                // Commit the selected candidate, then handle the next character normally.\n"
        "                if key.to_char().is_some() && !key.modifiers.control_key {\n"
        "                    let mut result = self.commit_conversion();\n"
        "                    result.actions.extend(self.process_key_empty(key).actions);\n"
        "                    return result;\n"
        "                }",
    )
    # Normalize kana input in the shared buffer; direct alphabet input is unchanged.
    sub(
        root / "karukan-im/core/src/core/engine/input_buffer.rs",
        r"    pub fn push_romaji\(&mut self, ch: char, romaji: &RomajiConverter\) \{\n",
        "    pub fn push_romaji(&mut self, ch: char, romaji: &RomajiConverter) {\n"
        "        let ch = if ch.eq_ignore_ascii_case(&'c') { 'k' } else { ch };\n",
    )
    # Upstream silently discards inference errors and displays kana fallback.
    sub(
        root / "karukan-im/core/src/core/engine/model.rs",
        r"(\.convert\([^\n]+\)\n)(\s*)\.unwrap_or_default\(\)",
        r'\1\2.unwrap_or_else(|error| { tracing::warn!(%error, "Karukan conversion failed"); Vec::new() })',
        expected=3,
    )
    # Do not infer on an unfinished romaji syllable. Preserve valid live chunks,
    # but hide selectable suggestions until the reading is complete again.
    sub(
        root / "karukan-im/core/src/core/engine/input.rs",
        r"        let full_reading = self\.input_buf\.reading\(\);\n",
        "        let full_reading = self.input_buf.reading();\n"
        "        if !self.input_buf.pending().is_empty() {\n"
        "            let chunk_reading: String = self.chunks.iter().map(|c| c.reading.as_str()).collect();\n"
        "            self.live.shown = self.live.shown && chunk_reading == full_reading;\n"
        "            self.shown_suggestions = CandidateList::default();\n"
        "            let preedit = self.set_composing_state();\n"
        "            return EngineResult::consumed()\n"
        "                .with_action(EngineAction::UpdatePreedit(preedit))\n"
        "                .with_action(EngineAction::HideCandidates)\n"
        "                .with_action(EngineAction::UpdateAuxText(self.format_aux_composing()));\n"
        "        }\n",
    )
    # Hidden suggestions must not block typing when explicit conversion is used.
    sub(
        root / "karukan-im/core/src/core/engine/input.rs",
        r"        let convert = !self\.suppress_suggest\n",
        "        let convert = !self.suppress_suggest\n"
        "            && (self.live.enabled || self.config.candidate_window == CandidateWindow::Always)\n",
    )
    # Upstream forces CPU for GPT-2/Metal. Restore llama.cpp's default (-1,
    # all layers); OpenVINO selects its own device through the environment.
    sub(
        root / "karukan-engine/src/kanji/llamacpp.rs",
        r"        // GPT-2 has Metal issues, use CPU\n"
        r"        let model_params = LlamaModelParams::default\(\)\.with_n_gpu_layers\(0\);",
        "        let model_params = LlamaModelParams::default();",
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
        "option(KARUKAN_OPENVINO \"Link the OpenVINO backend runtime\" ON)\n"
        "if(KARUKAN_OPENVINO)\n"
        "    find_package(OpenVINO REQUIRED COMPONENTS Runtime Threading)\n"
        "    find_package(OpenCL REQUIRED)\n"
        "endif()\n",
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
)
if(KARUKAN_OPENVINO)
    target_link_libraries(karukan openvino::runtime openvino::threading OpenCL::OpenCL)
    target_link_options(karukan PRIVATE "LINKER:--no-as-needed")
endif()""",
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

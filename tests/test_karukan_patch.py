"""Apply the packaging patch to the pinned upstream checkout.

KARUKAN_SOURCE_ROOT=/path/to/karukan python -m unittest discover -s tests
"""
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('karukan_patch', ROOT / 'nixos/patch-karukan.py')
patcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(patcher)
async_spec = importlib.util.spec_from_file_location('karukan_async_patch', ROOT / 'nixos/patch-karukan-async.py')
async_patcher = importlib.util.module_from_spec(async_spec)
async_spec.loader.exec_module(async_patcher)


@unittest.skipUnless(os.environ.get('KARUKAN_SOURCE_ROOT'), 'requires pinned upstream checkout')
class KarukanPatchTests(unittest.TestCase):
    def test_async_extension_applies_to_pinned_frontend_and_engine(self):
        source = Path(os.environ['KARUKAN_SOURCE_ROOT'])
        # Apply both packaging extensions to the real source tree, so a pinned
        # upstream layout change fails before spending time on a native build.
        import shutil
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / 'source'
            shutil.copytree(source, root)
            for path in [root, *root.rglob('*')]:
                path.chmod(0o755 if path.is_dir() else 0o644)
            patcher.main(root)
            async_patcher.main(root, ROOT / 'nixos/karukan-async-live.rs')
            self.assertIn('karukan_engine_poll_live',
                          (root / 'karukan-im/fcitx5/include/karukan.h').read_text())
            self.assertIn('mod async_live;',
                          (root / 'karukan-im/core/src/core/engine/mod.rs').read_text())

    def test_patch_preserves_converter_and_restores_default_offload(self):
        source = Path(os.environ['KARUKAN_SOURCE_ROOT'])
        loader = 'karukan-engine/src/kanji/llamacpp.rs'
        converter = 'karukan-engine/src/kanji/backend.rs'
        hf = 'karukan-engine/src/kanji/hf_download.rs'
        cmake = 'karukan-im/fcitx5/fcitx5-addon/CMakeLists.txt'
        input_source = 'karukan-im/core/src/core/engine/input.rs'
        model_source = 'karukan-im/core/src/core/engine/model.rs'
        buffer_source = 'karukan-im/core/src/core/engine/input_buffer.rs'
        conversion_source = 'karukan-im/core/src/core/engine/conversion.rs'
        strategy_source = 'karukan-im/core/src/core/engine/strategy.rs'
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in (loader, converter, hf, cmake, input_source, model_source, buffer_source, conversion_source, strategy_source):
                target = root / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes((source / name).read_bytes())
            patcher.main(root)
            expected = (source / loader).read_text().replace(
                '        // GPT-2 has Metal issues, use CPU\n', ''
            ).replace('LlamaModelParams::default().with_n_gpu_layers(0)', 'LlamaModelParams::default()')
            self.assertEqual((root / loader).read_text(), expected)
            self.assertEqual((root / converter).read_bytes(), (source / converter).read_bytes())
            self.assertEqual((root / hf).read_text().count('.revision(revision)'), 2)
            self.assertIn('build --offline --release', (root / cmake).read_text())
            self.assertIn('openvino::runtime', (root / cmake).read_text())
            self.assertIn('OpenCL::OpenCL', (root / cmake).read_text())
            expected_input = (source / input_source).read_text().replace(
                '        let full_reading = self.input_buf.reading();\n',
                '        let full_reading = self.input_buf.reading();\n'
                '        if !self.input_buf.pending().is_empty() {\n'
                '            let chunk_reading: String = self.chunks.iter().map(|c| c.reading.as_str()).collect();\n'
                '            self.live.shown = self.live.shown && chunk_reading == full_reading;\n'
                '            self.shown_suggestions = CandidateList::default();\n'
                '            let preedit = self.set_composing_state();\n'
                '            return EngineResult::consumed()\n'
                '                .with_action(EngineAction::UpdatePreedit(preedit))\n'
                '                .with_action(EngineAction::HideCandidates)\n'
                '                .with_action(EngineAction::UpdateAuxText(self.format_aux_composing()));\n'
                '        }\n',
            ).replace(
                '        let convert = !self.suppress_suggest\n',
                '        let convert = !self.suppress_suggest\n'
                '            && (self.live.enabled || self.config.candidate_window == CandidateWindow::Always)\n',
            )
            self.assertEqual((root / input_source).read_text(), expected_input)
            self.assertEqual((root / model_source).read_text().count('Karukan conversion failed'), 3)
            self.assertIn("let ch = if ch.eq_ignore_ascii_case(&'c') { 'k' } else { ch };", (root / buffer_source).read_text())
            self.assertIn('result.actions.extend(self.process_key_empty(key).actions);', (root / conversion_source).read_text())


if __name__ == '__main__':
    unittest.main()

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


@unittest.skipUnless(os.environ.get('KARUKAN_SOURCE_ROOT'), 'requires pinned upstream checkout')
class KarukanPatchTests(unittest.TestCase):
    def test_patch_preserves_converter_and_restores_default_offload(self):
        source = Path(os.environ['KARUKAN_SOURCE_ROOT'])
        loader = 'karukan-engine/src/kanji/llamacpp.rs'
        converter = 'karukan-engine/src/kanji/backend.rs'
        hf = 'karukan-engine/src/kanji/hf_download.rs'
        cmake = 'karukan-im/fcitx5/fcitx5-addon/CMakeLists.txt'
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in (loader, converter, hf, cmake):
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


if __name__ == '__main__':
    unittest.main()

"""macOS acceptance for Apple's PNG decoder, scaling and crop origin."""
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).parents[2]))
sys.path.insert(0, str(Path(__file__).parents[1]))
from ui_preview import create_preview
from png_fixture import png


class NativePreviewTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not Path('/usr/bin/sips').is_file():
            raise RuntimeError('Run preview-native on a local Mac with Apple sips')

    def test_real_resize_crop_orientation_no_upscale_and_original_hash(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'source.png'
            original = png()
            source.write_bytes(original)
            small = create_preview(source, root / 'small', max_edge=40)
            self.assertEqual(small['preview']['size_pixels'], [20, 40])
            same = create_preview(source, root / 'same')
            self.assertEqual(same['preview']['size_pixels'], [40, 80])
            for name, crop, color in (('top-left', (2, 3, 8, 10), b'\x00\xff\xff'),
                                      ('bottom-right', (29, 65, 8, 10), b'\x00\x00\x00')):
                result = create_preview(source, root / name, crop=crop)
                self.assertEqual(result['preview']['size_pixels'], [8, 10])
                bitmap = root / (name + '.bmp')
                subprocess.run(['/usr/bin/sips', '-s', 'format', 'bmp', result['preview']['path'],
                                '--out', str(bitmap)], check=True, capture_output=True, timeout=30)
                data = bitmap.read_bytes()
                offset = struct.unpack_from('<I', data, 10)[0]
                self.assertEqual(data[offset:offset + 3], color)
            scaled = create_preview(source, root / 'scaled', crop=(2, 3, 8, 10), max_edge=5)
            self.assertEqual(scaled['preview']['size_pixels'], [4, 5])
            self.assertEqual(source.read_bytes(), original)

    def test_structurally_valid_png_with_broken_compressed_data_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'corrupt.png'
            source.write_bytes(png(compressed=b'invalid'))
            with self.assertRaises(ValueError):
                create_preview(source, root / 'output')
            self.assertFalse((root / 'output/preview.json').exists())
            failure = json.loads((root / 'output/failure.json').read_text())
            self.assertNotEqual(failure['commands'][0]['exit_code'], 0)


if __name__ == '__main__':
    unittest.main()

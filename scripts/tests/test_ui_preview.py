"""Portable preview contracts: evidence isolation, failure retention and geometry."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).parents[1]))
import ui_preview
from png_fixture import png


class PreviewTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.run = self.root / 'run'
        self.run.mkdir()
        (self.run / 'manifest.json').write_text('{}')
        self.source = self.run / 'screen.png'
        self.source.write_bytes(png())
        self.output = self.root / 'preview'
        self.binary = patch.object(ui_preview, 'SIPS', Path(__file__))
        self.binary.start()
        self.addCleanup(self.binary.stop)

    def test_all_runs_symlink_aliases_and_existing_outputs_are_protected(self):
        other = self.root / 'another-run'
        other.mkdir()
        (other / 'manifest.json').write_text('{}')
        alias = self.root / 'alias'
        alias.symlink_to(other, target_is_directory=True)
        for output in (self.run / 'preview', other / 'preview', alias / 'preview'):
            with self.subTest(output=output), self.assertRaisesRegex(ValueError, 'outside all recorded runs'):
                ui_preview.create_preview(self.source, output)
        self.output.mkdir()
        (self.output / 'keep.txt').write_text('keep')
        with self.assertRaises(FileExistsError):
            ui_preview.create_preview(self.source, self.output)
        self.assertEqual((self.output / 'keep.txt').read_text(), 'keep')

    def test_invalid_crop_or_png_cannot_create_output(self):
        for crop in ((-1, 0, 4, 4), (0, 0, 0, 4), (39, 0, 2, 4), (0, 0, 4)):
            with self.subTest(crop=crop), self.assertRaises(ValueError):
                ui_preview.create_preview(self.source, self.output, crop=crop)
        for data in (png()[:24], png()[:-5], png() + b'trailing', png()[:40] + b'x' + png()[41:]):
            self.source.write_bytes(data)
            with self.subTest(length=len(data)), self.assertRaises(ValueError):
                ui_preview.create_preview(self.source, self.output)
        self.assertFalse(self.output.exists())

    def test_conversion_failure_or_timeout_is_retained_without_success_record(self):
        for index, failure in enumerate((Mock(returncode=13, stdout='', stderr='decode failed'),
                                         subprocess.TimeoutExpired('sips', 30))):
            output = self.root / str(index)
            kwargs = {'side_effect': failure} if isinstance(failure, Exception) else {'return_value': failure}
            with patch.object(ui_preview.subprocess, 'run', **kwargs), self.assertRaises(ValueError):
                ui_preview.create_preview(self.source, output)
            self.assertFalse((output / 'preview.json').exists())
            record = json.loads((output / 'failure.json').read_text())
            self.assertEqual(record['kind'], 'image_preview_failure')
            self.assertEqual(len(record['commands']), 1)

    def test_wrong_geometry_and_source_change_are_failures(self):
        def wrong_geometry(argv, **kwargs):
            Path(argv[-1]).write_bytes(png(20, 20))
            return Mock(returncode=0, stdout='', stderr='')
        def changed_source(argv, **kwargs):
            Path(argv[-1]).write_bytes(png())
            result = Mock(returncode=0, stdout="", stderr="")
            self.source.write_bytes(png(20, 20))
            return result
        for index, execute in enumerate((wrong_geometry, changed_source)):
            output = self.root / str(index)
            with patch.object(ui_preview.subprocess, 'run', side_effect=execute), self.assertRaises(ValueError):
                ui_preview.create_preview(self.source, output)
            self.assertTrue((output / 'failure.json').exists())
            self.assertFalse((output / 'preview.json').exists())


if __name__ == '__main__':
    unittest.main()

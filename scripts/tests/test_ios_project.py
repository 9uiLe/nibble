"""Invalid project descriptions must fail before invoking Apple tools."""
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).parents[1]))
from ios_project import load_project


class ProjectConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        project = self.root / 'app/Nibble.xcodeproj'
        project.mkdir(parents=True)
        (project / 'project.pbxproj').write_text('fixture')
        self.config = dict(project='app/Nibble.xcodeproj', scheme='Nibble',
                           bundle_id='nibble.9uiLe.com', app_name='Nibble', minimum_ios='26.0')

    def load(self, value):
        (self.root / 'project.json').write_text(json.dumps(value))
        return load_project(self.root, 'project.json')

    def test_invalid_descriptions_are_rejected(self):
        invalid = [[], {}, {**self.config, 'unknown': 'option'}]
        for key, value in [('project', '../Nibble.xcodeproj'), ('project', '/tmp/Other.xcodeproj'),
                           ('project', 'app/Missing.xcodeproj'), ('scheme', ''), ('scheme', 1),
                           ('app_name', '../Nibble'), ('bundle_id', 'bad bundle'),
                           ('minimum_ios', 'latest'), ('simulator_signing', 'distribution')]:
            invalid.append({**self.config, key: value})
        for config in invalid:
            with self.subTest(config=config), self.assertRaises(ValueError):
                self.load(config)

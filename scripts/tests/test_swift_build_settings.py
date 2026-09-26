"""Build warning policy rejects missing settings in either configuration."""

from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from check_swift_build_settings import check


PROJECT = '''
000000000000000000000001 = { isa = PBXProject; buildConfigurationList = 000000000000000000000002; };
000000000000000000000002 = { isa = XCConfigurationList; buildConfigurations = (000000000000000000000003, 000000000000000000000004); };
000000000000000000000003 = { isa = XCBuildConfiguration; name = Debug; buildSettings = { SWIFT_TREAT_WARNINGS_AS_ERRORS = YES; GCC_TREAT_WARNINGS_AS_ERRORS = YES; }; };
000000000000000000000004 = { isa = XCBuildConfiguration; name = Release; buildSettings = { SWIFT_TREAT_WARNINGS_AS_ERRORS = YES; GCC_TREAT_WARNINGS_AS_ERRORS = YES; }; };
'''


class SwiftBuildSettingsTests(unittest.TestCase):
    def test_all_owned_builds_require_warning_errors(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ('app/Nibble.xcodeproj/project.pbxproj',
                         'validation/VerificationApp.xcodeproj/project.pbxproj'):
                path = root / name
                path.parent.mkdir(parents=True)
                path.write_text(PROJECT)
            self.assertEqual(check(root), [])

            project = root / 'app/Nibble.xcodeproj/project.pbxproj'
            project.write_text(PROJECT.replace('name = Release; buildSettings = { SWIFT_TREAT_WARNINGS_AS_ERRORS = YES;',
                                               'name = Release; buildSettings = {'))
            self.assertTrue(any('Release' in error for error in check(root)))
            project.write_text(PROJECT)
            fixture = root / 'validation/VerificationApp.xcodeproj/project.pbxproj'
            fixture.write_text(PROJECT.replace('GCC_TREAT_WARNINGS_AS_ERRORS = YES;', '', 1))
            self.assertTrue(any('validation/' in error and 'Debug' in error
                                and 'GCC_TREAT_WARNINGS_AS_ERRORS' in error for error in check(root)))

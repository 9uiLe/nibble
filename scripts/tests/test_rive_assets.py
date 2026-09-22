"""The export guard must fail on stale output and broken binding contracts."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location("rive_assets", Path(__file__).parents[1] / "rive_assets.py")
rive_assets = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(rive_assets)

SCENE = '''<Rive><Artboard id="0:1" name="Art" defaultStateMachineId="0:2" viewModelId="0:3">
<StateMachine id="0:2" name="Play"/></Artboard><ViewModel id="0:3" name="Model" defaultInstanceId="0:4">
<ViewModelPropertyBoolean id="0:5" name="enabled"/><ViewModelInstance id="0:4" exports="true">
<ViewModelInstanceBoolean viewModelPropertyId="0:5" propertyValue="true"/></ViewModelInstance></ViewModel></Rive>'''


class RiveAssetTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "source"
        self.source.mkdir()
        (self.source / "scene.rml").write_text(SCENE)
        (self.root / "asset.riv").write_bytes(b"fixture")
        self.asset = dict(source="source", output="asset.riv", artboard="Art", state_machine="Play",
                          view_model="Model", properties={"enabled": "Boolean"},
                          sources_sha256=rive_assets.sources(self.source),
                          output_sha256=rive_assets.digest(self.root / "asset.riv"))

    def test_source_and_new_material_require_rebuild(self):
        rive_assets.check_asset(self.root, self.asset)
        (self.source / "material.png").write_bytes(b"new input")
        with self.assertRaisesRegex(ValueError, "Sources changed"):
            rive_assets.check_asset(self.root, self.asset)

    def test_output_tamper_or_missing_rejected(self):
        for content in (b"wrong export", None):
            p = self.root / "asset.riv"
            if content is None:
                p.unlink()
            else:
                p.write_bytes(content)
            with self.assertRaisesRegex(ValueError, "Missing or changed generated"):
                rive_assets.check_asset(self.root, self.asset)

    def test_broken_links_and_property_types_rejected(self):
        for before, after in [('defaultStateMachineId="0:2"', 'defaultStateMachineId="0:7"'),
                              ('viewModelId="0:3"', 'viewModelId="0:7"'),
                              ('defaultInstanceId="0:4"', 'defaultInstanceId="0:7"'),
                              ('exports="true"', 'exports="false"'),
                              ('ViewModelPropertyBoolean', 'ViewModelPropertyNumber'),
                              ('viewModelPropertyId="0:5"', 'viewModelPropertyId="0:7"')]:
            with self.subTest(after=after):
                (self.source / "scene.rml").write_text(SCENE.replace(before, after))
                with self.assertRaises(ValueError):
                    rive_assets.structure(self.source, self.asset)

    def test_state_machine_inputs_scripts_and_shaders_are_rejected(self):
        for tag in ('StateMachineNumber', 'ScriptAsset', 'ShaderAsset'):
            (self.source / "scene.rml").write_text(SCENE.replace('</Rive>', f'<{tag}/></Rive>'))
            with self.assertRaisesRegex(ValueError, "unsigned, script-free"):
                rive_assets.structure(self.source, self.asset)

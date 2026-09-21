from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from swift_view_structure import structure_violations


class ViewStructureTests(unittest.TestCase):
    def test_display_helpers_are_rejected_in_every_product_entry(self):
        for base in ['Nibble', 'NibbleShare', 'NibbleKeyboard', 'Shared', 'Packages/P/Sources/P']:
            for member in ['var header: some View { Text("x") }',
                           'func row() -> some SwiftUI.View { Text("x") }',
                           '@ViewBuilder func item() -> Text { Text("x") }']:
                with self.subTest(base=base, member=member):
                    self.assertTrue(structure_violations('struct Card: View {' + member + '}', f'app/{base}/Card.swift'))

    def test_protocol_witnesses_values_and_native_bridges_are_allowed(self):
        for source, name in [
            ('struct Card: View { var body: some View { Text(title) }; var title: String { "x" } }', 'Card'),
            ('struct Card: EquatableBodyView { var equatableBody: some View { Text("x") } }', 'Card'),
            ('struct Style: ViewModifier { func body(content: Content) -> some View { content } }', 'Style'),
            ('struct Style: ButtonStyle { func makeBody(configuration: Configuration) -> some View { configuration.label } }', 'Style'),
            ('struct Tools: ToolbarContent { var body: some ToolbarContent { ToolbarItem {} } }', 'Tools'),
            ('struct Native: UIViewRepresentable { func makeUIView(context: Context) -> UIView { UIView() } }', 'Native')]:
            self.assertEqual(structure_violations(source, f'app/Shared/{name}.swift'), [])

    def test_one_view_per_matching_file_including_nested_views(self):
        self.assertTrue(structure_violations('struct Card: View {}', 'app/Nibble/Screen.swift'))
        self.assertTrue(structure_violations('struct Card: View { struct Label: View {} }', 'app/Nibble/Card.swift'))
        self.assertTrue(structure_violations('struct Card: View {}\nstruct Label: View {}', 'app/Nibble/Card.swift'))
        self.assertEqual(structure_violations('struct Card: View {}\nclass Host: UIView {}', 'app/Nibble/Card.swift'), [])

    def test_fixture_views_may_be_colocated_with_tests(self):
        source = 'struct A: View {}; struct B: View {}'
        self.assertEqual(structure_violations(source, 'app/NibbleTests/Views.swift'), [])
        self.assertEqual(structure_violations(source, 'validation/VerificationAppTests/Views.swift'), [])

    def test_comments_and_literals_are_not_declarations(self):
        self.assertEqual(structure_violations('struct Card: View { var body: some View { Text("func x() -> some View") } } // var other: some View {}', 'app/Nibble/Card.swift'), [])

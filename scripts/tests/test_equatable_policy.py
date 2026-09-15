"""Regressions for AppMacros adoption and comparison-boundary bypasses."""

import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from check_swift_policy import violations


class EquatablePolicyTests(unittest.TestCase):
    def test_value_only_comparison_views_and_native_values_are_allowed(self):
        for source in [
            '@Equatable struct Row: EquatableBodyView { let title: String; let pinned: Bool; var equatableBody: some View { Text(title) } }',
            '@AppMacros.Equatable struct Row: AppMacros.EquatableBodyView { let value: Int; var equatableBody: some SwiftUI.View { Text("x") } }',
            'struct ModelValue: Sendable, Equatable { var title: String }',
            'enum Route: Equatable { case home, edit(Int) }',
            '@Equatable struct Value { let id: Int; var text: String }',
            'struct Screen: View { @State private var model = Model(); var body: some View { Row(title: model.title, pinned: false) } }',
            'func equal<T: Equatable>(_ a: T, _ b: T) -> Bool { a == b }',
        ]:
            with self.subTest(source=source):
                self.assertEqual(violations(source), [])

    def test_direct_gates_aliases_and_exclusions_are_rejected(self):
        for source in [
            'Row().equatable()', 'let gate = Row().equatable', 'Row().equatableBody',
            'Row().\n/* gate */ `equatable`()',
            'SwiftUI.EquatableView(content: Row())', 'typealias Gate = EquatableView<Row>',
            '@SkipEquatable let hidden: Int', '@AppMacros.SkipEquatable let cache: Cache',
            'typealias Equal = Swift.Equatable', 'typealias Gate = AppMacros.EquatableBodyView',
            'protocol RowProtocol: EquatableBodyView {}', 'protocol RowProtocol: SwiftUI.View {}', 'typealias HiddenView = SwiftUI.View',
        ]:
            with self.subTest(source=source):
                self.assertTrue(violations(source))

    def test_handwritten_equality_is_rejected_but_calls_are_allowed(self):
        for source in [
            'struct Value { static func == (lhs: Self, rhs: Self) -> Bool { true } }',
            'extension Value { static func /* skipped */ == (lhs: Self, rhs: Self) -> Bool { true } }',
            'func == (lhs: Value, rhs: Value) -> Bool { true }',
        ]:
            with self.subTest(source=source):
                self.assertTrue(any('handwritten' in v[2] for v in violations(source)))
        self.assertEqual(violations('let same = first == second'), [])

    def test_views_cannot_omit_the_macro_or_the_gate(self):
        for source in [
            'struct Row: EquatableBodyView { let value: Int; var equatableBody: some View { Text("x") } }',
            '@Equatable struct Row: View { let value: Int; var body: some View { Text("x") } }',
            'struct Row: SwiftUI.View, Swift.Equatable { let value: Int; var body: some View { Text("x") } }',
            'struct Row: SwiftUI /* comment */ . `View`, Swift.Equatable { let value: Int; var body: some View { Text("x") } }',
            'protocol RowProtocol: View, Equatable {}',
            'extension Row: Equatable {}',
            '@Equatable struct Row { let value: Int; var body: some View { Text("x") } }',
        ]:
            with self.subTest(source=source):
                self.assertTrue(violations(source))

    def test_body_and_conformance_cannot_move_to_an_extension(self):
        for source in [
            '@Equatable struct Row: EquatableBodyView { let value: Int; var body: some View { Text("x") } }',
            'extension Row { var body: some View { Text("x") } }',
            'extension Row { var equatableBody: some View { Text("x") } }',
            'extension Row: EquatableBodyView { var equatableBody: some View { Text("x") } }',
            '@Equatable struct Row: EquatableBodyView { let value: Int }',
        ]:
            with self.subTest(source=source):
                self.assertTrue(violations(source))

    def test_comparison_views_cannot_hide_inputs(self):
        for prop in [
            'let callback: () -> Void', 'let callback: (() -> Void)?',
            'let callbacks: [() -> Void]', 'let callback = { print("called") }',
            '@State private var value = 0', '@Binding var value: Int',
            '@Bindable var value: Model', '@Environment(\\.colorScheme) var scheme',
            '@CustomWrapper let value: Int', 'var value: Int', 'lazy var value = 0',
            'var value = 0 { didSet {} }', 'unowned let value: Model',
        ]:
            source = '@Equatable struct Row: EquatableBodyView { let title: String; ' + prop + '; var equatableBody: some View { Text(title) } }'
            with self.subTest(source=source):
                self.assertTrue(violations(source))
        self.assertTrue(violations('@Equatable struct Row: EquatableBodyView { var equatableBody: some View { Text("fixed") } }'))

    def test_comments_and_strings_do_not_trigger_but_interpolation_does(self):
        self.assertEqual(violations('let example = "@SkipEquatable Row().equatable()"\n// static func ==\n/* EquatableView */'), [])
        self.assertTrue(violations('let example = "\\(Row().equatable())"'))

    def test_app_macros_diagnostics_preserve_unicode_positions(self):
        source = '// 日本語\nlet view = Row().equatable()'
        result = violations(source)
        self.assertEqual(result[0][:2], (2, 18))

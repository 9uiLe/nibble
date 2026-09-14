"""Policy regression tests exercise actual forbidden and library-owned forms."""

from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from check_swift_policy import SwiftLexer, check, violations


class SwiftPolicyTests(unittest.TestCase):
    def test_raw_task_creation_handles_and_aliases_are_rejected(self):
        cases = [
            'Task { await work() }',
            'Task(priority: .high) { await work() }',
            '_Concurrency.Task<Void, Never> { await work() }',
            'Swift.Task.detached { await work() }',
            'Task<Void, Error>.init(operation: work)',
            'Task\n/* owner? */ . detached(operation: work)',
            '`Task` { await work() }',
            'var handle: Task<Void, Never>?',
            'typealias Work = Task<Void, Never>',
            'let start = Task.detached',
            'let factory = Task<Void, Never>.init',
        ]
        for source in cases:
            with self.subTest(source=source):
                self.assertTrue(violations(source))

    def test_alternative_schedulers_cannot_bypass_ownership(self):
        for source in ['DispatchQueue.main.async {}', 'DispatchWorkItem {}',
                       'OperationQueue().addOperation {}', 'BlockOperation {}',
                       'Thread.detachNewThread {}', 'Timer.scheduledTimer()',
                       'DispatchSource.makeTimerSource()']:
            with self.subTest(source=source):
                self.assertTrue(violations(source))

    def test_raw_animation_calls_references_and_modifiers_are_rejected(self):
        for source in ['withAnimation { value = true }', 'SwiftUI.withAnimation(.spring) {}',
                       'let animate = withAnimation', 'withTransaction(transaction) {}',
                       'Transaction(animation: .default)', 'typealias Motion = Transaction',
                       'view\n.animation\n(.spring, value: value)', 'view.animation { $0.scaleEffect(2) }',
                       'binding.animation(.default)', 'view.transaction { $0.animation = nil }',
                       'view.phaseAnimator([0, 1]) {}', 'view.keyframeAnimator(initialValue: 0) {}',
                       'UIView.animate(withDuration: 1) {}', 'UIKit.UIView.animateKeyframes() {}',
                       'UIView.transition(with: view)', 'UIView.performWithoutAnimation {}',
                       'UIViewPropertyAnimator(duration: 1, curve: .linear)', 'CATransaction.begin()',
                       'CABasicAnimation(keyPath: "opacity")', 'NSAnimationContext.runAnimationGroup {}']:
            with self.subTest(source=source):
                self.assertTrue(violations(source))

    def test_owned_actions_structured_work_and_scoped_animation_are_allowed(self):
        source = '''
        import Tasking
        import TaskingCore
        import ScopedAnimation
        let tasks = ViewTaskStore()
        tasks.start(id: Actions.save, lifetime: .screenBound, policy: .ignoreNew) { cancellation in
            try cancellation.check()
            async let child = work()
            await withTaskGroup(of: Void.self) { group in group.addTask { await work() } }
            await child
        }
        let slot = TaskSlot()
        await slot.replace { cancellation in try cancellation.check() }
        View().task(id: query) { await load() }
        try await Task.sleep(for: .seconds(1))
        try await Task<Never, Never>.sleep(for: .seconds(1))
        await Task.yield()
        try Task.checkCancellation()
        let cancelled = Task.isCancelled
        let priority = Task.currentPriority
        AnimationScope(.spring, value: expanded) { Content() }
        AnimationScope(.default) { scope in Button("Expand") { scope.animate { expanded.toggle() } } }
        AnimationScope(triggers: [AnimationTrigger.animation(.default, value: value)]) { Content() }
        Content().animationBarrier().detectAnimationLeaks()
        '''
        self.assertEqual(violations(source), [])

    def test_comments_strings_raw_strings_and_regex_are_not_code(self):
        source = r'''
        // Task { }
        /* withAnimation {} /* nested .animation */ Task.detached */
        let label = "Task { } and \\\"withAnimation\\\""
        let raw = ##"Task {} \(withAnimation {})"##
        let multiline = """
        .animation(.default)
        """
        let regex = #/Task\s*\{withAnimation/#
        let bare = /Task[{}]/
        let quotient = total / count
        '''
        self.assertEqual(violations(source), [])

    def test_string_interpolations_are_checked_including_nested_literals(self):
        for source in [r'"result: \(Task { 1 })"',
                       r'##"result: \##(Task.detached { 1 })"##',
                       '"""result: \\(Task { 1 })"""',
                       r'"nested \("inner \(Task { 1 })")"']:
            with self.subTest(source=source):
                self.assertTrue(violations(source))

    def test_suppression_comments_do_not_disable_the_policy(self):
        self.assertTrue(violations('withAnimation {} // animation-exception: intentional'))
        self.assertTrue(violations('// swiftlint:disable all\nTask {}'))

    def test_diagnostics_preserve_original_line_and_column(self):
        self.assertEqual(violations('// comment\n  Task\n{}')[0][:2], (2, 3))
        self.assertEqual(violations('let s = "ignored"\nlet t = "\\(Task {})"')[0][:2], (2, 12))

    def test_unterminated_sources_fail_closed(self):
        for source in ['/* unfinished', 'let x = "unfinished', '`Task', '"\\(Task {}']:
            with self.subTest(source=source):
                with self.assertRaises(ValueError):
                    SwiftLexer(source).scan()

    def test_scan_includes_tests_research_and_new_source_directories(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ['app/Main.swift', 'app/Tests/Case.swift', 'validation/Probe.swift', 'NewFeature/Foo.swift']:
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text('Task {}')
            ignored = root / 'artifacts/Dependencies/Raw.swift'
            ignored.parent.mkdir(parents=True)
            ignored.write_text('Task {}')
            count, errors = check(root)
            self.assertEqual(count, 4)
            self.assertEqual(len(errors), 4)
            result = subprocess.run([sys.executable, str(Path(__file__).resolve().parents[1] / 'check_swift_policy.py'), '--root', str(root)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 1)
            self.assertIn('app/Main.swift:1:1: error:', result.stdout)

    def test_symlink_sources_and_directories_fail_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'Real.swift'
            source.write_text('import Tasking')
            linked = root / 'Alias.swift'
            linked.symlink_to(source)
            with self.assertRaises(ValueError):
                check(root)
            linked.unlink()
            (root / 'LinkedSources').symlink_to(root, target_is_directory=True)
            with self.assertRaises(ValueError):
                check(root)

    def test_no_sources_is_not_success(self):
        with tempfile.TemporaryDirectory() as directory:
            self.assertTrue(check(Path(directory))[1])


if __name__ == '__main__':
    unittest.main()

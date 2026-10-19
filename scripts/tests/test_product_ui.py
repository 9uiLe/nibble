import copy
from pathlib import Path
import sys
import unittest
from types import SimpleNamespace
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).parents[1]))
from ios import VerificationError
from product_ui import ProductRun, editor_mode_target, editor_viewport, identifiers, input_point


class ProductNavigationTests(unittest.TestCase):
    def test_editor_modes_use_native_roles_and_reject_text_or_ambiguity(self):
        group = {'uniqueId': 'editor.mode', 'role': 'TabGroup'}
        self.assertEqual(editor_mode_target({'entries': [group]}, 'プレビュー'), (group, .75))
        radio = {'label': 'プレビュー', 'role': 'RadioButton'}
        self.assertEqual(editor_mode_target({'entries': [radio]}, 'プレビュー'), (radio, .5))
        with self.assertRaises(VerificationError):
            editor_mode_target({'entries': [{'label': 'プレビュー', 'role': 'Text'}]}, 'プレビュー')
        with self.assertRaises(VerificationError):
            editor_mode_target({'entries': [radio, copy.deepcopy(radio)]}, 'プレビュー')

    def test_input_point_uses_only_the_visible_intersection(self):
        data = {'screen': {'height': 667}, 'entries': [
            {'uniqueId': 'editor.body', 'frame': {'x': 24, 'y': 300, 'width': 327, 'height': 180}},
            {'uniqueId': 'editor.keyboard.help', 'frame': {'y': 355, 'height': 44}},
        ]}
        self.assertEqual(input_point(data, 'editor.body'), (187.5, 327.5))
        data['entries'][0]['frame']['y'] = 368
        with self.assertRaises(VerificationError):
            input_point(data, 'editor.body')

    def test_focus_observes_and_reveals_the_field_after_keyboard_layout(self):
        def screen(y):
            return {'screen': {'width': 375, 'height': 667}, 'entries': [
                {'uniqueId': 'editor.body', 'frame': {'x': 24, 'y': y, 'width': 327, 'height': 40}},
                {'uniqueId': 'editor.keyboard.help', 'frame': {'y': 355, 'height': 44}},
                {'uniqueId': 'editor.keyboard.dismiss'},
            ]}
        run = object.__new__(ProductRun)
        run.args = SimpleNamespace(device='selected')
        run.ui = Mock(side_effect=[screen(140), screen(140), screen(368), screen(368), screen(368),
                                   screen(200), screen(200)])
        run.command = Mock()
        with patch('ios.time.sleep'):
            self.assertEqual(run._focus_input('editor.body'), (187.5, 220))
        self.assertEqual([call.args[0][1] for call in run.command.call_args_list], ['tap', 'swipe'])

    def test_focus_waits_for_interactive_keyboard_dismissal_before_using_the_title_point(self):
        def screen(y, keyboard):
            entries = [
                {'uniqueId': 'editor.title', 'frame': {'x': 20, 'y': y, 'width': 362, 'height': 34}},
                {'uniqueId': 'editor.exitGuidance', 'frame': {'y': 140, 'height': 18}},
                {'uniqueId': 'editor.keyboard.help' if keyboard else 'editor.help',
                 'frame': {'y': 501 if keyboard else 803, 'height': 18}},
            ]
            if keyboard:
                entries.append({'uniqueId': 'editor.keyboard.dismiss'})
            return {'screen': {'width': 402, 'height': 874}, 'entries': entries}

        run = object.__new__(ProductRun)
        run.args = SimpleNamespace(device='selected')
        run.ui = Mock(side_effect=[screen(584, True), screen(584, True), screen(423, True),
                                   screen(584, False), screen(584, False), screen(448, True),
                                   screen(448, True), screen(448, True)])
        run.command = Mock()
        with patch('ios.time.sleep'):
            self.assertEqual(run._focus_input('editor.title'), (201, 465))
        self.assertEqual([call.args[0][1] for call in run.command.call_args_list], ['swipe', 'tap'])
        tap = run.command.call_args_list[1].args[0]
        self.assertEqual(float(tap[tap.index('-y') + 1]), 601)

    def test_reveal_waits_for_changes_to_either_the_frame_or_the_viewport(self):
        def screen(y, bottom):
            return {'screen': {'width': 375, 'height': 667}, 'entries': [
                {'uniqueId': 'editor.body', 'frame': {'x': 24, 'y': y, 'width': 327, 'height': 180}},
                {'uniqueId': 'editor.keyboard.help', 'frame': {'y': bottom, 'height': 44}},
            ]}

        for changed in [screen(280, 355), screen(300, 400)]:
            with self.subTest(changed=changed):
                run = object.__new__(ProductRun)
                run.ui = Mock(side_effect=[screen(300, 355), changed, copy.deepcopy(changed)])
                run.command = Mock()
                with patch('ios.time.sleep'):
                    self.assertEqual(run._reveal_input('editor.body'), changed)
                self.assertEqual(run.ui.call_count, 3)
                run.command.assert_not_called()

    def test_unsettled_input_fails_after_bounded_observations_without_tapping(self):
        run = object.__new__(ProductRun)
        run.ui = Mock(side_effect=[{'screen': {'width': 375, 'height': 667}, 'entries': [
            {'uniqueId': 'editor.title', 'frame': {'x': 20, 'y': 200 + attempt, 'width': 335, 'height': 34}},
        ]} for attempt in range(20)])
        run.command = Mock()
        with patch('ios.time.sleep'), self.assertRaisesRegex(VerificationError, 'editor.title-present'):
            run._focus_input('editor.title')
        self.assertEqual(run.ui.call_count, 20)
        run.command.assert_not_called()

    def test_editor_viewport_excludes_the_navigation_bar_and_keyboard_accessory(self):
        data = {'screen': {'height': 667}, 'entries': [
            {'role': 'Group', 'uniqueId': '新規作成', 'frame': {'y': 46, 'height': 54}},
            {'uniqueId': 'editor.title', 'frame': {'y': 65, 'height': 20}},
            {'uniqueId': 'editor.keyboard.help', 'frame': {'y': 355, 'height': 44}},
        ]}
        self.assertEqual(editor_viewport(data), (100, 355))
        data['entries'].append({'role': 'StaticText', 'label': '閉じると下書きに残り、保存すると使えます。',
                                'frame': {'y': 110, 'height': 16}})
        self.assertEqual(editor_viewport(data), (136, 355))

    def test_workspace_routes_back_and_clears_only_when_requested(self):
        root = {'entries': [{'uniqueId': 'navigation.settings'}, {'uniqueId': 'search.clear'}]}
        run = object.__new__(ProductRun)
        run.ui = Mock(return_value={'entries': [{'uniqueId': 'BackButton'}]})
        run.tap = Mock()
        run.wait_ui = Mock(return_value=root)
        run.workspace(clear_query=True)
        self.assertEqual([call.args[0] for call in run.tap.call_args_list], ['BackButton', 'search.clear'])
        run.tap.reset_mock()
        run.ui.return_value = root
        run.workspace()
        run.tap.assert_not_called()

    def test_missing_workspace_route_fails_without_tapping_an_invented_target(self):
        run = object.__new__(ProductRun)
        run.ui = Mock(return_value={'entries': []})
        run.tap = Mock()
        with self.assertRaises(VerificationError):
            run.workspace()
        run.tap.assert_not_called()

    def test_settings_uses_the_workspace_control_and_waits_for_destination(self):
        run = object.__new__(ProductRun)
        run.workspace = Mock(return_value={'entries': [{'uniqueId': 'navigation.settings'}]})
        run.tap = Mock()
        run.wait_ui = Mock(return_value={'entries': [{'uniqueId': 'settings.about'}]})
        run.open_settings()
        run.workspace.assert_called_once_with()
        run.tap.assert_called_once_with('navigation.settings')
        self.assertEqual(run.wait_ui.call_args.args[0], 'settings-route')


class WorkspaceKeyboardGeometryTests(unittest.TestCase):
    def narrow_editor(self):
        return {'screen': {'width': 375, 'height': 667}, 'entries': [
            {'uniqueId': '文章を編集', 'role': 'Group', 'region': {'kind': 'Top'},
             'frame': {'x': 0, 'y': 46, 'width': 375, 'height': 54}},
            {'uniqueId': 'workspace.editor.close', 'role': 'Button',
             'frame': {'x': 20, 'y': 50, 'width': 72, 'height': 36}},
            {'uniqueId': 'workspace.editor.title', 'role': 'TextArea',
             'frame': {'x': 32, 'y': 272, 'width': 311, 'height': 48}},
            {'uniqueId': 'workspace.editor.body', 'role': 'TextArea',
             'frame': {'x': 32, 'y': 408, 'width': 311, 'height': 260}},
            {'role': 'Group', 'frame': {'x': 0, 'y': 399, 'width': 331, 'height': 54}},
            {'uniqueId': 'delete', 'label': '削除', 'role': 'Button',
             'frame': {'x': 298, 'y': 450, 'width': 73, 'height': 54}},
            {'uniqueId': 'Return', 'label': '改行', 'role': 'Button',
             'frame': {'x': 293, 'y': 551, 'width': 73, 'height': 108}},
            {'label': 'か', 'role': 'Button', 'frame': {'x': 151, 'y': 450, 'width': 73, 'height': 54}},
        ]}

    def test_normalized_keyboard_excludes_its_candidate_group_without_a_keyboard_role(self):
        from product_ui import workspace_keyboard_top, workspace_viewport
        data = self.narrow_editor()
        self.assertEqual(workspace_keyboard_top(data), 399)
        self.assertEqual(workspace_viewport(data), (100, 399))
        self.assertNotIn('Keyboard', {entry['role'] for entry in data['entries']})

    def test_only_a_large_exposed_input_intersection_is_tapped(self):
        from product_ui import workspace_entry, workspace_input_point, workspace_visible
        data = self.narrow_editor()
        with self.assertRaisesRegex(VerificationError, '44pt'):
            workspace_input_point(data, 'workspace.editor.body')
        body = workspace_entry(data, 'workspace.editor.body')
        body['frame']['y'] = 200
        self.assertTrue(workspace_visible(data, body))
        self.assertEqual(workspace_input_point(data, 'workspace.editor.body'), (187.5, 299.5))
        body['frame']['y'] = 370
        self.assertFalse(workspace_visible(data, body))
        with self.assertRaises(VerificationError):
            workspace_input_point(data, 'workspace.editor.body')
        self.assertTrue(workspace_visible(data, workspace_entry(data, 'workspace.editor.close')))
        self.assertFalse(workspace_visible(data, {'role': 'Button',
            'frame': {'x': 32, 'y': 360, 'width': 311, 'height': 50}}))

    def test_scroll_uses_the_observed_form_gutter_and_never_crosses_the_keyboard(self):
        from product_ui import WorkspaceRun, workspace_viewport
        data = self.narrow_editor()
        run = object.__new__(WorkspaceRun)
        run.args = SimpleNamespace(device='narrow-owned')
        run.command = Mock()
        run.scroll_workspace(data)
        argv = run.command.call_args.args[0]
        top, bottom = workspace_viewport(data)
        for flag in ('--from', '--to'):
            x, y = map(float, argv[argv.index(flag) + 1].split(','))
            self.assertEqual(x, 16)
            self.assertGreater(y, top)
            self.assertLess(y, bottom)
            self.assertLess(x, 32)
        self.assertEqual(argv[-2:], ['--device', 'narrow-owned'])

    def test_english_letter_rows_are_not_missed_when_delete_is_on_a_later_row(self):
        from product_ui import workspace_keyboard_top
        data = self.narrow_editor()
        data['entries'] = [entry for entry in data['entries'] if entry.get('label') != 'か']
        next(entry for entry in data['entries'] if entry.get('uniqueId') == 'delete')['frame']['y'] = 558
        data['entries'].append({'uniqueId': 'q', 'label': 'q', 'role': 'Button',
                                'frame': {'x': 2, 'y': 450, 'width': 34, 'height': 54}})
        self.assertEqual(workspace_keyboard_top(data), 399)

    def test_clipped_long_guidance_keeps_its_observed_side_gutter(self):
        from product_ui import workspace_scroll_gutter
        data = {'screen': {'width': 375, 'height': 667}, 'entries': [
            {'role': 'StaticText', 'uniqueId': 'workspace.settings.keyboardGuide',
             'region': {'kind': 'Top'}, 'frame': {'x': 16, 'y': -1069, 'width': 343, 'height': 1768}}]}
        self.assertEqual(workspace_scroll_gutter(data), 8)

    def test_missing_safe_gutter_fails_instead_of_swiping_inside_a_text_view(self):
        from product_ui import WorkspaceRun
        data = self.narrow_editor()
        for entry in data['entries']:
            if entry['role'] == 'TextArea':
                entry['frame'].update(x=0, width=375)
        run = object.__new__(WorkspaceRun)
        run.args = SimpleNamespace(device='narrow-owned')
        run.command = Mock()
        with self.assertRaisesRegex(VerificationError, 'gutter'):
            run.scroll_workspace(data)
        run.command.assert_not_called()

    def test_native_paste_resolves_an_exposed_point_instead_of_using_the_full_field_center(self):
        from product_ui import WorkspaceRun
        data = self.narrow_editor()
        next(entry for entry in data['entries'] if entry.get('uniqueId') == 'workspace.editor.body')['frame']['y'] = 200
        run = object.__new__(WorkspaceRun)
        run._focus_workspace_input = Mock(return_value=data)
        with patch('product_ui.ProductRun.paste_text', return_value='observed') as paste:
            self.assertEqual(run.paste_text('body', ['--target-id', 'workspace.editor.body'], lambda _: True), 'observed')
        self.assertEqual(paste.call_args.args[1], ['--target-x', '187.5', '--target-y', '299.5'])

    def test_native_search_uses_its_fully_exposed_observed_34pt_frame(self):
        from product_ui import workspace_entry, workspace_input_point, workspace_visible
        data = self.narrow_editor()
        data['entries'].append({'uniqueId': 'workspace.search', 'role': 'TextField',
                                'frame': {'x': 16, 'y': 126, 'width': 343, 'height': 34}})
        search = workspace_entry(data, 'workspace.search')
        self.assertTrue(workspace_visible(data, search))
        self.assertEqual(workspace_input_point(data, 'workspace.search'), (187.5, 143))
        for y in (99, 370):
            search['frame']['y'] = y
            self.assertFalse(workspace_visible(data, search))
            with self.assertRaisesRegex(VerificationError, 'fully exposed'):
                workspace_input_point(data, 'workspace.search')

    def test_search_at_actual_navigation_group_bottom_needs_no_invented_clearance(self):
        from product_ui import workspace_entry, workspace_input_point, workspace_viewport, workspace_visible
        data = {'screen': {'x': 0, 'y': 0, 'width': 402, 'height': 874}, 'entries': [
            {'uniqueId': 'workspace.settings', 'role': 'Button',
             'frame': {'x': 20, 'y': 66, 'width': 36, 'height': 36}},
            {'uniqueId': 'workspace.create', 'role': 'Button',
             'frame': {'x': 346, 'y': 66, 'width': 36, 'height': 36}},
            {'uniqueId': 'nibble', 'role': 'Group', 'region': {'kind': 'Top'},
             'frame': {'x': 0, 'y': 62, 'width': 402, 'height': 106}},
            {'uniqueId': 'workspace.search', 'role': 'TextField',
             'frame': {'x': 16, 'y': 168, 'width': 370, 'height': 34}},
        ]}
        self.assertEqual(workspace_viewport(data), (168, 874))
        self.assertTrue(workspace_visible(data, workspace_entry(data, 'workspace.search')))
        self.assertEqual(workspace_input_point(data, 'workspace.search'), (201, 185))
        workspace_entry(data, 'workspace.search')['frame']['y'] = 167
        self.assertFalse(workspace_visible(data, workspace_entry(data, 'workspace.search')))

    def test_content_controls_cannot_overlap_navigation_but_toolbar_actions_remain_visible(self):
        from product_ui import workspace_entry, workspace_visible
        data = self.narrow_editor()
        self.assertTrue(workspace_visible(data, workspace_entry(data, 'workspace.editor.close')))
        content = {'uniqueId': 'workspace.trash', 'role': 'Button',
                   'frame': {'x': 16, 'y': 82, 'width': 343, 'height': 156}}
        self.assertFalse(workspace_visible(data, content))
        content['frame']['y'] = 100
        self.assertTrue(workspace_visible(data, content))
        content['frame']['x'] = 33
        self.assertFalse(workspace_visible(data, content))
        toolbar = copy.deepcopy(workspace_entry(data, 'workspace.editor.close'))
        toolbar['frame']['y'] = -1
        self.assertFalse(workspace_visible(data, toolbar))

    def test_reveal_waits_for_inertia_then_reveals_again_if_control_settles_under_navigation(self):
        from product_ui import WorkspaceRun

        def observation(y):
            return {'screen': {'width': 375, 'height': 667}, 'entries': [
                {'role': 'Heading', 'region': {'kind': 'Top'},
                 'frame': {'x': 129, 'y': 55, 'width': 118, 'height': 26}},
                {'uniqueId': 'workspace.settings.close', 'role': 'Button',
                 'frame': {'x': 272, 'y': 50, 'width': 83, 'height': 36}},
                {'uniqueId': 'workspace.trash', 'role': 'Button',
                 'frame': {'x': 16, 'y': y, 'width': 343, 'height': 156}},
            ]}

        run = object.__new__(WorkspaceRun)
        run.args = SimpleNamespace(device='owned')
        run.ui = Mock(side_effect=[observation(y) for y in (221, 130, 82, 82, 140, 140, 140)])
        run.command = Mock()
        with patch('ios.time.sleep'):
            settled = run.reveal_workspace('workspace.trash')
        self.assertEqual(settled['entries'][-1]['frame']['y'], 140)
        self.assertEqual(run.ui.call_count, 7)
        argv = run.command.call_args.args[0]
        self.assertEqual(argv[:2], ['sim-use', 'swipe'])
        # A tall, clipped control on the SE3 oscillated under the former fast
        # 60%-viewport gesture. Revealing uses the measured 30% reading step.
        self.assertEqual(float(argv[argv.index('--from') + 1].split(',')[0]), 8)
        self.assertAlmostEqual(float(argv[argv.index('--from') + 1].split(',')[1]), 86 + (667 - 86) * .35)
        self.assertAlmostEqual(float(argv[argv.index('--to') + 1].split(',')[1]), 86 + (667 - 86) * .65)
        self.assertEqual(argv[argv.index('--duration') + 1], '.7')

    def test_reveal_uses_the_same_short_slow_step_to_bring_up_a_control_below_screen(self):
        from product_ui import WorkspaceRun

        def observation(y):
            return {'screen': {'width': 375, 'height': 667}, 'entries': [
                {'uniqueId': 'workspace.settings.close', 'role': 'Button',
                 'frame': {'x': 272, 'y': 50, 'width': 83, 'height': 36}},
                {'uniqueId': 'workspace.trash', 'role': 'Button',
                 'frame': {'x': 16, 'y': y, 'width': 343, 'height': 156}},
            ]}

        run = object.__new__(WorkspaceRun)
        run.args = SimpleNamespace(device='owned')
        run.ui = Mock(side_effect=[observation(y) for y in (552, 300, 300, 300)])
        run.command = Mock()
        with patch('ios.time.sleep'):
            self.assertEqual(run.reveal_workspace('workspace.trash')['entries'][-1]['frame']['y'], 300)
        self.assertEqual(run.command.call_count, 1)
        argv = run.command.call_args.args[0]
        self.assertAlmostEqual(float(argv[argv.index('--from') + 1].split(',')[1]), 86 + (667 - 86) * .65)
        self.assertAlmostEqual(float(argv[argv.index('--to') + 1].split(',')[1]), 86 + (667 - 86) * .35)
        self.assertEqual(argv[argv.index('--duration') + 1], '.7')

    def test_reveal_requires_both_target_frame_and_viewport_to_settle(self):
        from product_ui import WorkspaceRun
        first, changed = self.narrow_editor(), self.narrow_editor()
        next(entry for entry in changed['entries'] if entry.get('role') == 'Group'
             and entry['frame']['y'] == 399)['frame']['y'] = 380
        run = object.__new__(WorkspaceRun)
        run.ui = Mock(side_effect=[first, copy.deepcopy(first), changed, copy.deepcopy(changed)])
        run.command = Mock()
        with patch('ios.time.sleep'):
            self.assertEqual(run.reveal_workspace('workspace.editor.title'), changed)
        self.assertEqual(run.ui.call_count, 4)
        run.command.assert_not_called()

    def test_absent_lazy_target_is_found_above_after_observing_the_settings_bottom(self):
        from product_ui import WorkspaceRun

        def observation(identifier, y, height=900):
            return {'screen': {'width': 375, 'height': 667}, 'entries': [
                {'uniqueId': 'workspace.settings.close', 'role': 'Button',
                 'frame': {'x': 272, 'y': 50, 'width': 83, 'height': 36}},
                {'uniqueId': identifier, 'role': 'Button' if identifier == 'workspace.trash' else 'StaticText',
                 'frame': {'x': 16, 'y': y, 'width': 343, 'height': height}},
            ]}

        bottom = observation('workspace.settings.privacy', -678)
        reordered_bottom = copy.deepcopy(bottom)
        reordered_bottom['entries'].reverse()
        found = observation('workspace.trash', 300, 156)
        run = object.__new__(WorkspaceRun)
        run.args = SimpleNamespace(device='owned')
        run.ui = Mock(side_effect=[observation('workspace.settings.privacy', -422), bottom,
                                   reordered_bottom, observation('workspace.settings.privacy', -350),
                                   found, copy.deepcopy(found), copy.deepcopy(found)])
        run.command, run.tap = Mock(), Mock()
        with patch('ios.time.sleep'):
            self.assertEqual(run.reveal_workspace('workspace.trash'), found)
        self.assertEqual(run.ui.call_count, 7)
        directions = []
        for call in run.command.call_args_list:
            argv = call.args[0]
            start = list(map(float, argv[argv.index('--from') + 1].split(',')))
            end = list(map(float, argv[argv.index('--to') + 1].split(',')))
            self.assertEqual((start[0], end[0]), (8, 8))
            self.assertTrue(all(86 < y < 667 for y in (start[1], end[1])))
            self.assertEqual(argv[argv.index('--duration') + 1], '.7')
            directions.append(start[1] < end[1])
        self.assertEqual(directions, [False, False, True, True])
        run.tap.assert_not_called()

    def test_missing_target_stops_after_observed_content_stalls_in_both_directions(self):
        from product_ui import WorkspaceRun
        data = self.narrow_editor()
        run = object.__new__(WorkspaceRun)
        run.ui = Mock(return_value=data)
        run.scroll_workspace, run.tap = Mock(), Mock()
        with self.assertRaisesRegex(VerificationError, 'Element is not reachable: workspace.trash'):
            run.reveal_workspace('workspace.trash', attempts=24)
        self.assertEqual(run.ui.call_count, 3)
        self.assertEqual([call.kwargs for call in run.scroll_workspace.call_args_list],
                         [{'up': False, 'reading': True}, {'up': True, 'reading': True}])
        run.tap.assert_not_called()

    def test_default_budget_can_pass_twelve_viewports_then_reverse_to_a_lazy_target(self):
        from product_ui import WorkspaceRun

        def observation(step):
            return {'screen': {'width': 375, 'height': 667}, 'entries': [
                {'uniqueId': 'workspace.settings.close', 'role': 'Button',
                 'frame': {'x': 272, 'y': 50, 'width': 83, 'height': 36}},
                {'role': 'StaticText', 'label': '最大文字サイズの長い説明',
                 'frame': {'x': 16, 'y': -400 - step * 320, 'width': 343, 'height': 7300}},
            ]}

        found = observation(0)
        found['entries'].append({'uniqueId': 'workspace.trash', 'role': 'Button',
                                  'frame': {'x': 16, 'y': 300, 'width': 343, 'height': 156}})
        run = object.__new__(WorkspaceRun)
        run.ui = Mock(side_effect=[*[observation(step) for step in range(21)], observation(20),
                                   *[observation(step) for step in range(19, -1, -1)],
                                   found, copy.deepcopy(found), copy.deepcopy(found)])
        run.scroll_workspace, run.tap = Mock(), Mock()
        with patch('ios.time.sleep'):
            self.assertEqual(run.reveal_workspace('workspace.trash'), found)
        self.assertEqual(run.ui.call_count, 45)
        directions = [call.kwargs['up'] for call in run.scroll_workspace.call_args_list]
        self.assertEqual(directions, [False] * 21 + [True] * 21)
        self.assertTrue(all(call.kwargs['reading'] for call in run.scroll_workspace.call_args_list))
        run.tap.assert_not_called()

    def test_absent_target_exploration_still_obeys_the_observation_budget(self):
        from product_ui import WorkspaceRun
        observations = []
        for attempt in range(4):
            data = self.narrow_editor()
            next(entry for entry in data['entries'] if entry.get('uniqueId') == 'workspace.editor.title')['frame']['y'] -= attempt
            observations.append(data)
        run = object.__new__(WorkspaceRun)
        run.ui = Mock(side_effect=observations)
        run.scroll_workspace, run.tap = Mock(), Mock()
        with self.assertRaisesRegex(VerificationError, 'Element is not reachable'):
            run.reveal_workspace('workspace.trash', attempts=4)
        self.assertEqual(run.ui.call_count, 4)
        self.assertEqual(run.scroll_workspace.call_count, 3)
        run.tap.assert_not_called()

    def test_perpetually_moving_control_fails_without_tapping(self):
        from product_ui import WorkspaceRun
        run = object.__new__(WorkspaceRun)
        observations = []
        for attempt in range(21):
            data = self.narrow_editor()
            next(entry for entry in data['entries'] if entry.get('uniqueId') == 'workspace.editor.title')['frame']['y'] += attempt
            observations.append(data)
        run.ui = Mock(side_effect=observations)
        run.command = Mock()
        with patch('ios.time.sleep'), self.assertRaisesRegex(VerificationError, 'reveal-settled'):
            run.reveal_workspace('workspace.editor.title')
        self.assertEqual(run.ui.call_count, 21)
        run.command.assert_not_called()

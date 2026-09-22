"""Observed editor input shared by product UI checks; assertions stay in each scenario."""
from ios import Run, VerificationError


TAB_LABELS = {'navigation.tab.library': '一覧', 'navigation.tab.search': '検索', 'navigation.tab.settings': '設定'}


def native_tabs(data):
    """Resolve test selectors to observed native tabs without changing raw AX data."""
    if data.get('appPackage') != 'nibble.9uiLe.com':
        return {}
    resolved = {}
    for selector, label in TAB_LABELS.items():
        matches = [entry for entry in data['entries']
                   if entry.get('label') == label
                   and (entry.get('uniqueId') == selector or entry.get('role') == 'RadioButton')]
        if len(matches) > 1:
            raise VerificationError('Ambiguous native tab: ' + label)
        if matches:
            resolved[selector] = matches[0]
    return resolved


class ProductRun(Run):
    def tap(self, identifier):
        if identifier not in TAB_LABELS:
            return super().tap(identifier)
        entry = native_tabs(self.ui('resolve-' + identifier)).get(identifier)
        if entry is None:
            raise VerificationError('Native tab is not visible: ' + identifier)
        frame = entry['frame']
        self.command(['sim-use', 'tap', '-x', str(frame['x'] + frame['width'] / 2),
                      '-y', str(frame['y'] + frame['height'] / 2), '--device', self.args.device])


def identifiers(data):
    return {entry.get("uniqueId", "") for entry in data["entries"]} | native_tabs(data).keys()


def editor_viewport(data):
    entries = data['entries']
    top = max((entry['frame']['y'] + entry['frame']['height'] for entry in entries
               if entry.get('role') == 'Group' and entry.get('uniqueId') in
               ('新規作成', '項目を編集', '共有から保存')), default=0)
    bottom = min((entry['frame']['y'] for entry in entries
                  if entry.get('uniqueId') in ('editor.keyboard.help', 'editor.help')), default=data['screen']['height'])
    return top, bottom


def paste_editor(run, identifier, text, replace=False):
    def reflected(data):
        value = next((e.get("value", "") for e in data["entries"] if e.get("uniqueId") == identifier), "")
        # AX may collapse whitespace; each scenario checks saved/copied bytes separately.
        return "".join(value.split()) == "".join(text.split())

    def focus_target(at_end=False):
        def point(data):
            frame = next(e["frame"] for e in data["entries"] if e.get("uniqueId") == identifier)
            top, bottom = editor_viewport(data)
            top, bottom = max(top, frame['y']), min(bottom, frame['y'] + frame['height'])
            if bottom <= top:
                raise VerificationError("The input field is covered by fixed controls: " + identifier)
            # These short fixtures leave trailing space. Avoid long-pressing
            # inside a word, which selects a fragment instead of the menu.
            return frame["x"] + frame["width"] * (0.95 if at_end else 0.5), (top + bottom) / 2

        data = run.wait_ui(identifier + "-focus-target", lambda data: identifier in identifiers(data))
        for attempt in range(4):
            frame = next(e['frame'] for e in data['entries'] if e.get('uniqueId') == identifier)
            top, bottom = editor_viewport(data)
            if frame['y'] >= top and frame['y'] < bottom:
                break
            start, end = top + (bottom - top) * .35, top + (bottom - top) * .75
            if frame['y'] >= bottom:
                start, end = end, start
            x = data['screen']['width'] * .35
            run.command(['sim-use', 'swipe', '--from', f'{x},{start}', '--to', f'{x},{end}',
                         '--duration', '.4', '--post-delay', '.5', '--device', run.args.device])
            data = run.ui(identifier + f'-revealed-{attempt}')
        x, y = point(data)
        run.command(["sim-use", "tap", "-x", str(x), "-y", str(y), "--duration", "0.05",
                     "--post-delay", ".5", "--device", run.args.device])
        data = run.wait_ui(identifier + "-focused", lambda data: identifier in identifiers(data)
                       and "editor.keyboard.dismiss" in identifiers(data))
        x, y = point(data)
        return ["--target-x", str(x), "--target-y", str(y)]

    target = focus_target(at_end=replace)
    if replace:
        for attempt in range(2):
            try:
                run.command(["sim-use", "paste", "--replace", "--via-menu", *target,
                             "--device", run.args.device, text])
                run.wait_ui(identifier + "-pasted", reflected)
                return
            except VerificationError as error:
                if "Edit menu 'Select All' item did not appear" not in str(error):
                    raise
                run.manifest["commands"][-1]["handled_error"] = {
                    "reason": "sim-use 0.14.0 cannot select Select All in the compact Japanese menu; use the observed native menu",
                    "assertion": "edited_copy_utf8_exact",
                }
                run.save()
                current = run.ui(identifier + f"-replace-menu-{attempt}")
                if any(entry.get("label") in ("すべてを選択", "Select All") for entry in current["entries"]):
                    break
                disclosure = next((entry for entry in current["entries"]
                                   if entry.get("role") == "Button" and entry.get("label") in ("進む", "Next")), None)
                if disclosure is not None:
                    run.command(["sim-use", "tap", "--label", disclosure["label"], "--element-type", "Button",
                                 "--device", run.args.device])
                    run.wait_ui(identifier + "-expanded-edit-menu", lambda data: any(
                        entry.get("label") in ("すべてを選択", "Select All") for entry in data["entries"]))
                    break
                # The initial gesture can just focus the field. Retry once
                # after observing it; do not accept an absent menu as success.
                if attempt == 1:
                    raise
        # sim-use 0.14.0 opens the native menu but cannot match this
        # runtime's Japanese Select All label. Verify and operate that menu.
        for labels in (("すべてを選択", "Select All"), ("カット", "Cut")):
            data = run.wait_ui(identifier + "-" + labels[0], lambda data: any(
                entry.get("label") in labels for entry in data["entries"]))
            item = next(entry["label"] for entry in data["entries"] if entry.get("label") in labels)
            run.command(["sim-use", "tap", "--label", item, "--device", run.args.device])
        target = focus_target()
    run.paste_text(text, target, reflected, name=identifier + "-paste")

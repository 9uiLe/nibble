"""Conservative Swift syntax rules for explicit task-start capabilities.

No type/effect inference: storage names and startTask are reserved. Unsupported
syntax fails closed; adding an event boundary requires policy tests and review.
"""

from tree_sitter_language_pack import get_parser
from swift_equatable_policy import equatable_violations

PARSER = get_parser("swift")
STORES = {"ViewTaskStore": "tasks", "TaskSlot": "taskSlot"}
MEMBERS = {
    "tasks": {"start", "cancel", "cancelAll", "waitForIdle", "awaitCompletion", "isRunning", "runningCount"},
    "taskSlot": {"replace", "cancel", "close", "cancelAndWaitForIdle", "waitForIdle"},
}
# Reviewed product callbacks invoked synchronously by Button actions only.
PRODUCT_EVENTS = {"SnippetRow": "perform", "LibraryNotice": "restore"}
SCOPES = {"function_declaration", "lambda_literal", "computed_property", "willset_didset_block", "init_declaration", "deinit_declaration", "class_declaration"}


def text(node):
    return node.text.decode() if node else ""


def walk(node):
    yield node
    for child in node.children:
        yield from walk(child)


def ancestor(node, kinds):
    node = node.parent
    while node:
        if node.type in kinds:
            return node
        node = node.parent
    return None


def name(node):
    return text(node.child_by_field_name("name"))


def attributes(node):
    return {text(c) for m in node.named_children if m.type == "modifiers" for c in m.named_children if c.type == "attribute"}


def owner_kind(node):
    owner = ancestor(node, {"class_declaration"})
    if not owner or name(owner).endswith("Model") or "@Observable" in attributes(owner):
        return None
    inherited = {text(c).split(".")[-1] for c in owner.named_children if c.type == "inheritance_specifier"}
    if "View" in inherited:
        return "view"
    if "UIViewController" in inherited:
        return "controller"
    if name(owner).endswith("TaskOwner") and "@MainActor" in attributes(owner):
        return "owner"
    return None


def is_test(node):
    return node.type == "function_declaration" and any(a == "@Test" or a.startswith("@Test(") for a in attributes(node))


def is_async(node):
    return any(c.type == "async" for c in node.children)


def called_identifier(call):
    callee = call.named_children[0]
    if callee.type == "simple_identifier":
        return text(callee)
    if callee.type == "navigation_expression":
        suffix = callee.child_by_field_name("suffix")
        return text(suffix).lstrip(".")
    return ""


def direct_call(node):
    """Find a call only if node is its callee, never an argument or alias."""
    expression = node
    if node.parent.type == "navigation_suffix":
        expression = node.parent.parent
    if expression.parent.type == "call_expression" and expression.parent.named_children[0] == expression:
        return expression.parent
    return None


def event_closure(node):
    parent = node.parent
    label = None
    if parent.type == "value_argument":
        label = text(parent.child_by_field_name("name"))
        suffix = parent.parent.parent
    elif parent.type == "call_suffix":
        suffix = parent
        # Only the first trailing closure is an unlabeled action. Later ones are
        # labels/content and never task boundaries.
        lambdas = [c for c in suffix.named_children if c.type == "lambda_literal"]
        if not lambdas or lambdas[0] != node:
            return False
    else:
        return False
    call = suffix.parent
    if call.type != "call_expression":
        return False
    callee = called_identifier(call)
    if callee in PRODUCT_EVENTS:
        # Require the explicit label; an unlabeled/content closure is not an event.
        return label == PRODUCT_EVENTS[callee]
    if callee == "Button":
        if label is not None:
            return label == "action"
        arguments = [c for c in suffix.named_children if c.type == "value_arguments"]
        return not any(name(a) == "action" for args in arguments for a in args.named_children)
    if callee in {"onAppear", "onDisappear", "onChange", "onOpenURL"}:
        return label in {None, "perform"}
    return callee in {"sheet", "fullScreenCover"} and label == "onDismiss"


def start_context(node, storage=None):
    scope = ancestor(node, SCOPES)
    if not scope:
        return False
    if is_test(scope):
        return True
    if not owner_kind(node):
        return False
    if scope.type == "lambda_literal":
        return owner_kind(node) in {"view", "controller"} and event_closure(scope)
    if scope.type == "function_declaration":
        if name(scope) == "startTask":
            return storage != "tasks" or not is_async(scope)
        return (owner_kind(node) == "controller" and name(scope) in {"viewDidLoad", "viewDidAppear", "viewWillAppear"}
                and "override" in text(scope).split("func", 1)[0].split() and not is_async(scope))
    return False


def boundary_violations(source, tokens):
    # tree-sitter-swift lacks Swift 6.2's isolated deinit modifier. Mask only
    # that keyword (preserving UTF-8 byte offsets); still parse/check its body.
    data = bytearray(source.encode())
    for first, second in zip(tokens, tokens[1:]):
        if first.text == "isolated" and second.text == "deinit":
            offset = len(source[:first.offset].encode())
            data[offset:offset + len("isolated")] = b" " * len("isolated")
    root = PARSER.parse(bytes(data)).root_node
    if root.has_error:
        bad = next(n for n in walk(root) if n.type == "ERROR" or n.is_missing)
        raise ValueError(f"Unsupported or malformed Swift syntax at {bad.start_point.row + 1}:{bad.start_point.column + 1}")
    found = []

    def reject(node, message):
        prefix = source.encode()[:node.start_byte].decode()
        found.append((prefix.count("\n") + 1, len(prefix.rsplit("\n", 1)[-1]) + 1, message))

    for node in walk(root):
        value = text(node).strip("`")
        if node.type not in {"simple_identifier", "type_identifier"}:
            continue
        if value in STORES:
            call = direct_call(node)
            prop = call.parent if call else None
            valid = (prop is not None and prop.type == "property_declaration"
                     and name(prop) == STORES[value] and call in prop.named_children
                     and len([c for c in prop.named_children if c.type == "pattern"]) == 1)
            if valid:
                scope = ancestor(prop, SCOPES)
                valid = bool(scope and (is_test(scope) or (scope.type == "class_declaration" and owner_kind(prop)
                             and "private" in text(prop).split("=", 1)[0].split())))
            if not valid:
                reject(node, f"{value} must be a private direct {STORES[value]} property of a View, UIViewController or @MainActor *TaskOwner (or a local in @Test); no aliases or injection.")
        elif value in MEMBERS:
            # The only binding is the approved direct constructor; all other
            # references must be direct method calls on tasks / self.tasks.
            prop = node.parent.parent if node.parent.type == "pattern" else None
            if prop and prop.type == "property_declaration":
                constructors = [c for c in prop.named_children if c.type == "call_expression" and called_identifier(c) in STORES]
                if constructors and STORES[called_identifier(constructors[0])] == value:
                    continue
            receiver = node
            if node.parent.type == "navigation_suffix":
                receiver = node.parent.parent
                if text(receiver) != "self." + value:
                    reject(node, "Task storage cannot escape its owner; use tasks / taskSlot or self.tasks / self.taskSlot directly.")
                    continue
            navigation = receiver.parent
            if navigation.type != "navigation_expression" or navigation.named_children[0] != receiver:
                reject(node, "Task storage cannot be aliased, passed, returned, captured or reassigned.")
                continue
            suffix = navigation.child_by_field_name("suffix")
            member = text(suffix).lstrip(".")
            call = navigation.parent
            if call.type != "call_expression" or call.named_children[0] != navigation or member not in MEMBERS[value]:
                reject(node, "Use direct supported Tasking calls; method references and aliases are prohibited.")
            elif member in {"start", "replace"} and not start_context(node, storage=value):
                reject(node, "Task creation is allowed only at explicit startTask, UI event/lifecycle, or @Test boundaries; operations must await their work.")
        elif value == "startTask":
            if node.parent.type == "function_declaration" and node == node.parent.child_by_field_name("name"):
                func = node.parent
                valid = owner_kind(func) is not None and ancestor(func, SCOPES).type == "class_declaration"
                # ViewTaskStore boundaries are synchronous. TaskSlot.replace is
                # actor-isolated, so a dedicated TaskOwner may expose async startTask.
                if is_async(func):
                    owner = ancestor(func, {"class_declaration"})
                    valid = valid and owner_kind(func) == "owner" and any(text(c) == "TaskSlot" for c in walk(owner))
                if not valid:
                    reject(node, "startTask is reserved for explicit UI/task owners; ordinary operations must be async and await completion.")
            elif not direct_call(node) or not start_context(node):
                reject(node, "Call startTask directly from a UI event/lifecycle, another startTask, or @Test; do not hide or alias task starts.")
    equatable_violations(root, reject)
    return found

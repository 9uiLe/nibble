"""Production View composition: named types, protocol witnesses and one View per file.

This is a syntax contract. It checks explicit View/ToolbarContent results and
ViewBuilder declarations; Swift remains responsible for resolving types.
"""
from pathlib import Path
from tree_sitter_language_pack import get_parser
from swift_equatable_policy import VIEW_BASES, inherited, spelling, walk, attributes, attribute_name

PARSER = get_parser('swift')
BODY_PROTOCOLS = VIEW_BASES | {'EquatableBodyView', 'ViewModifier', 'ToolbarContent', 'App', 'Scene'}
STYLE_PROTOCOLS = {'ButtonStyle', 'PrimitiveButtonStyle', 'LabelStyle', 'ToggleStyle', 'ProgressViewStyle'}


def production_source(path):
    parts = Path(path).parts
    return (len(parts) > 2 and parts[0] == 'app'
            and (parts[1] in {'Nibble', 'NibbleShare', 'NibbleKeyboard', 'Shared'}
                 or parts[1] == 'Packages' and 'Sources' in parts))


def structure_violations(source, path):
    if not production_source(path):
        return []
    root = PARSER.parse(source.encode()).root_node
    found = []

    def reject(node, message):
        found.append((node.start_point.row + 1, node.start_point.column + 1, message))

    views = [n for n in walk(root) if n.type == 'class_declaration'
             and inherited(n).intersection(VIEW_BASES | {'EquatableBodyView'})]
    for view in views:
        if len(views) > 1:
            reject(view, 'Declare one production SwiftUI View per file.')
        if spelling(view.child_by_field_name('name')) != Path(path).stem:
            reject(view, 'Name the file after its production SwiftUI View.')

    for node in walk(root):
        if node.type not in {'function_declaration', 'property_declaration'}:
            continue
        if node.type == 'property_declaration' and not node.child_by_field_name('computed_value'):
            continue
        # Do not inspect a member's implementation or parameter closures as its result type.
        header = [c for c in node.named_children
                  if c.type in {'type_annotation', 'opaque_type', 'user_type', 'existential_type'}]
        explicit_view = any(spelling(t) in {'View', 'ToolbarContent', 'Scene'}
                            for c in header for t in walk(c) if t.type == 'type_identifier')
        builder = any(attribute_name(a) == 'ViewBuilder' for a in attributes(node))
        if not (explicit_view or builder):
            continue
        owner = node.parent
        while owner and owner.type != 'class_declaration':
            owner = owner.parent
        bases = inherited(owner) if owner else set()
        name = spelling(node.child_by_field_name('name'))
        witness = ((name == 'body' and bool(bases & BODY_PROTOCOLS))
                   or name == 'equatableBody' and 'EquatableBodyView' in bases
                   or name == 'makeBody' and bool(bases & STYLE_PROTOCOLS))
        if not witness:
            reject(node, 'Define display content as a View type; View-returning helpers and computed properties are prohibited.')
    return found

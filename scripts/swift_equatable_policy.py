"""Conservative AppMacros syntax for value-only SwiftUI comparison boundaries.

This is not type/effect analysis. Custom equality gates, aliases and excluded
inputs are rejected; the compiler checks generated witnesses and Sendability.
"""


def walk(node):
    yield node
    for child in node.children:
        yield from walk(child)


def text(node):
    return node.text.decode() if node else ""


def spelling(node):
    return text(node).replace("`", "").strip()


def inherited(node):
    bases = set()
    for child in node.named_children:
        if child.type == "inheritance_specifier":
            base = child.child_by_field_name("inherits_from")
            identifiers = [spelling(c) for c in base.named_children if c.type == "type_identifier"] if base else []
            if identifiers:
                bases.add(identifiers[-1])
    return bases


def attributes(node):
    return [c for m in node.named_children if m.type == "modifiers"
            for c in m.named_children if c.type == "attribute"]


def attribute_name(node):
    types = [spelling(c) for c in walk(node) if c.type == "type_identifier"]
    return types[-1] if types else ""


def equatable_violations(root, reject):
    for node in walk(root):
        value = spelling(node)
        if node.type in {"type_identifier", "simple_identifier"}:
            if value == "EquatableBodyView":
                parent = node.parent
                while parent and parent.type == "user_type":
                    parent = parent.parent
                if not (parent and parent.type == "inheritance_specifier"
                        and parent.parent.type == "class_declaration"
                        and any(c.type == "struct" for c in parent.parent.children)):
                    reject(node, "Declare EquatableBodyView directly on a struct; aliases, refined protocols and extensions are prohibited.")
            if value in {"Equatable", "View"} and node.parent.type in {"user_type", "protocol_composition_type"}:
                parent = node.parent
                while parent and parent.type not in {"typealias_declaration", "class_declaration", "protocol_declaration", "source_file", "function_declaration"}:
                    parent = parent.parent
                if parent and parent.type == "typealias_declaration":
                    reject(node, "Do not alias View or Equatable; keep comparison conformance visible at its declaration.")

        if node.type not in {"class_declaration", "protocol_declaration"}:
            continue
        bases = inherited(node)
        attrs = attributes(node)
        macro = any(attribute_name(a) == "Equatable" for a in attrs)
        body = node.child_by_field_name("body")
        properties = [c for c in body.named_children if c.type == "property_declaration"] if body else []
        is_extension = any(c.type == "extension" for c in node.children)
        is_struct = any(c.type == "struct" for c in node.children)
        gate = "EquatableBodyView" in bases
        # A body in an extension can override the library gate in another file.
        for prop in properties:
            name = spelling(prop.child_by_field_name("name"))
            if name == "equatableBody" and not gate:
                reject(prop, "equatableBody belongs directly to an @Equatable EquatableBodyView struct.")
            if name == "body" and (gate or is_extension):
                reject(prop, "Keep body on the View declaration; EquatableBodyView must use the library's body and declare equatableBody instead.")
        if node.type == "protocol_declaration" and "View" in bases:
            reject(node, "Declare View directly on concrete views; refined View protocols can hide comparison boundaries.")
        if is_extension and "Equatable" in bases:
            reject(node, "Declare equality on the type, not in an extension; SwiftUI comparison must use AppMacros.")
        body_is_view = any(spelling(p.child_by_field_name("name")) == "body"
                           and any(c.type == "opaque_type" and any(spelling(t) == "View" for t in walk(c)) for c in walk(p))
                           for p in properties)
        if ("View" in bases or body_is_view) and (macro or "Equatable" in bases) and not gate:
            reject(node, "Use @Equatable with EquatableBodyView for SwiftUI comparison; an ordinary View can omit the comparison gate.")
        if gate and (not macro or not is_struct):
            reject(node, "EquatableBodyView requires @Equatable directly on its struct.")
        if not gate:
            continue
        if "View" in bases or "Equatable" in bases:
            reject(node, "EquatableBodyView supplies View and Equatable; do not add a separate conformance.")
        if not any(spelling(p.child_by_field_name("name")) == "equatableBody" for p in properties):
            reject(node, "Declare equatableBody in the same struct as EquatableBodyView.")
        stored = []
        for prop in properties:
            if prop.child_by_field_name("computed_value"):
                continue
            modifiers = [c for m in prop.named_children if m.type == "modifiers" for c in m.named_children]
            if any(spelling(m) in {"static", "class"} for m in modifiers):
                continue
            stored.append(prop)
            binding = next((c for c in prop.named_children if c.type == "value_binding_pattern"), None)
            if (spelling(binding) != "let" or attributes(prop)
                    or any(m.type == "ownership_modifier" for m in modifiers)):
                reject(prop, "Comparison views accept plain let values only; state, bindings, wrappers and mutable storage stay in the owning View.")
            if any(c.type in {"function_type", "lambda_literal"} for c in walk(prop)):
                reject(prop, "Do not store closures in comparison views; keep actions outside the gate so callbacks cannot become stale.")
        if not stored:
            reject(node, "A comparison view must have compared value inputs; an always-equal gate is prohibited.")

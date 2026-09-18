"""AppMacros coverage and safe comparison boundaries for every owned SwiftUI View.

Value gates compare all inputs. Other views retain SwiftUI-managed state and
refresh opaque parent inputs with a private, per-instance revision. This is
syntax validation; the compiler checks types and macro-generated witnesses.
"""

VIEW_BASES = {"View", "UIViewRepresentable", "UIViewControllerRepresentable",
              "NSViewRepresentable", "NSViewControllerRepresentable"}
OWNED_WRAPPERS = {"State", "StateObject", "Environment", "EnvironmentObject",
                  "AppStorage", "SceneStorage", "FocusState", "AccessibilityFocusState",
                  "GestureState", "Namespace", "ScaledMetric"}


def stored_properties(body):
    if not body:
        return []
    result = []
    for child in body.named_children:
        if child.type == "property_declaration":
            if child.child_by_field_name("computed_value"):
                continue
            modifiers = [c for m in child.named_children if m.type == "modifiers" for c in m.named_children]
            if not any(spelling(m) in {"static", "class"} for m in modifiers):
                result.append(child)
        elif child.type not in {"function_declaration", "class_declaration", "init_declaration", "deinit_declaration"}:
            result.extend(stored_properties(child))
    return result


def has_input_revision(properties):
    # Require an immutable, private default, so callers cannot reuse a revision
    # with a different binding, callback, model or generic content.
    return bool(properties) and "".join(text(properties[0]).split()) == "privateletinputRevision=UUID()"



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
    allowed_exclusions = set()
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
            if value in VIEW_BASES | {"Equatable"} and node.parent.type in {"user_type", "protocol_composition_type"}:
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
        if node.type == "protocol_declaration" and VIEW_BASES.intersection(bases):
            reject(node, "Declare View directly on concrete views; refined View protocols can hide comparison boundaries.")
        if is_extension and "Equatable" in bases:
            reject(node, "Declare equality on the type, not in an extension; SwiftUI comparison must use AppMacros.")
        body_is_view = any(spelling(p.child_by_field_name("name")) == "body"
                           and any(c.type == "opaque_type" and any(spelling(t) == "View" for t in walk(c)) for c in walk(p))
                           for p in properties)
        is_view = bool(VIEW_BASES.intersection(bases)) or body_is_view or gate
        if is_view and (not macro or not is_struct):
            reject(node, "Every concrete SwiftUI View, including representables, requires @Equatable on its struct.")
        if is_view and not gate:
            if not VIEW_BASES.intersection(bases):
                reject(node, "Declare View conformance directly so its comparison isolation is visible.")
            stored_inputs = stored_properties(body)
            revision = has_input_revision(stored_inputs)
            opaque = [p for p in stored_inputs
                      if not (revision and spelling(p.child_by_field_name("name")) == "inputRevision")
                      and not any(attribute_name(a) in OWNED_WRAPPERS for a in attributes(p))]
            if opaque and not revision:
                reject(node, "Parent inputs require private let inputRevision = UUID(); value-only content can use EquatableBodyView instead.")
            if revision and macro and is_struct:
                for prop in stored_inputs:
                    binding = next((c for c in prop.named_children if c.type == "value_binding_pattern"), None)
                    if spelling(binding) == "let" and spelling(prop.child_by_field_name("name")) != "inputRevision":
                        allowed_exclusions.update(a.start_byte for a in attributes(prop) if attribute_name(a) == "SkipEquatable")
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

    for node in walk(root):
        if node.type == "attribute" and attribute_name(node) == "SkipEquatable" and node.start_byte not in allowed_exclusions:
            reject(node, "SkipEquatable is limited to immutable parent inputs of an @Equatable View with a private per-instance inputRevision.")

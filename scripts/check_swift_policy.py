#!/usr/bin/env python3
"""Enforce Tasking, ScopedAnimation and AppMacros entry points in repository-owned Swift sources.

Lexical API checks and tree-sitter boundary checks are not Swift type
resolution. See docs/library-policy.md for the enforced syntax and limitations.
"""

import argparse
from dataclasses import dataclass
from pathlib import Path
from swift_task_boundary import boundary_violations
import re


@dataclass(frozen=True)
class Token:
    text: str
    offset: int


LITERAL_START = re.compile(r'(\#*)("""|"|/)')


class SwiftLexer:
    def __init__(self, source):
        self.source = source
        self.index = 0
        self.tokens = []

    def fail(self, message):
        raise ValueError(f"{message} at character {self.index}")

    def comment(self):
        depth = 1
        self.index += 2
        while self.index < len(self.source):
            if self.source.startswith("/*", self.index):
                depth += 1
                self.index += 2
            elif self.source.startswith("*/", self.index):
                depth -= 1
                self.index += 2
                if depth == 0:
                    return
            else:
                self.index += 1
        self.fail("Unterminated block comment")

    def literal(self, hashes, delimiter):
        self.index += len(hashes) + len(delimiter)
        ending = delimiter + hashes
        escape = "\\" + hashes
        while self.index < len(self.source):
            if self.source.startswith(ending, self.index):
                self.index += len(ending)
                return
            if self.source.startswith(escape, self.index):
                self.index += len(escape)
                if self.source.startswith("(", self.index):
                    self.index += 1
                    self.code(interpolation=True)
                else:
                    self.index += 1
            else:
                self.index += 1
        self.fail("Unterminated string or regex literal")

    def code(self, interpolation=False):
        depth = 0
        while self.index < len(self.source):
            at = self.index
            if self.source.startswith("//", at):
                end = self.source.find("\n", at)
                self.index = len(self.source) if end < 0 else end + 1
                continue
            if self.source.startswith("/*", at):
                self.comment()
                continue
            literal = LITERAL_START.match(self.source, at)
            if literal:
                hashes, delimiter = literal.groups()
                previous = self.tokens[-1].text if self.tokens else ""
                # Bare regex literals can begin at an expression boundary; a slash
                # after an operand is division. Extended regex literals use #/ ... /#.
                if delimiter != "/" or hashes or previous in {"", "=", "(", "[", ",", ":", "return"}:
                    self.literal(hashes, delimiter)
                    continue
            char = self.source[at]
            if char.isspace():
                self.index += 1
                continue
            if char == "`":
                end = self.source.find("`", at + 1)
                if end < 0:
                    self.fail("Unterminated escaped identifier")
                self.tokens.append(Token(self.source[at + 1:end], at))
                self.index = end + 1
                continue
            if char.isalpha() or char == "_":
                self.index += 1
                while self.index < len(self.source) and (self.source[self.index].isalnum() or self.source[self.index] == "_"):
                    self.index += 1
                self.tokens.append(Token(self.source[at:self.index], at))
                continue
            if interpolation:
                if char == "(":
                    depth += 1
                elif char == ")":
                    if depth == 0:
                        self.index += 1
                        return
                    depth -= 1
            self.tokens.append(Token(char, at))
            self.index += 1
        if interpolation:
            self.fail("Unterminated interpolation")

    def scan(self):
        self.code()
        return self.tokens


# Tasking does not replace structured concurrency or cooperative task primitives.
TASK_PRIMITIVES = {"sleep", "yield", "checkCancellation", "isCancelled", "currentPriority"}
UNMANAGED_TYPES = {
    "DispatchQueue", "DispatchWorkItem", "DispatchSource", "OperationQueue",
    "BlockOperation", "Thread", "Timer",
}
ANIMATION_SYMBOLS = {
    "withAnimation", "withTransaction", "Transaction", "UIViewPropertyAnimator",
    "UIViewImplicitlyAnimating", "CAAnimation", "CABasicAnimation",
    "CAKeyframeAnimation", "CAAnimationGroup", "CATransaction", "NSAnimationContext",
}
RIVE_LEGACY_SYMBOLS = {"RiveViewModel", "RiveView", "RiveModel", "RiveFile", "RiveStateMachineInstance", "RiveSMIInput"}
ANIMATION_MEMBERS = {"animation", "transaction", "phaseAnimator", "keyframeAnimator"}
UIKIT_ANIMATION_MEMBERS = {"animate", "animateKeyframes", "transition", "performWithoutAnimation", "setAnimationsEnabled", "beginAnimations", "commitAnimations"}
GENERATED = {".git", ".build", ".direnv", "DerivedData", "artifacts", "build"}


def violations(source):
    tokens = SwiftLexer(source).scan()
    found = []
    for index, token in enumerate(tokens):
        previous = tokens[index - 1].text if index else ""
        receiver = tokens[index - 2].text if index > 1 else ""
        next_index = index + 1
        if token.text == "Task" and next_index < len(tokens) and tokens[next_index].text == "<":
            depth = 0
            while next_index < len(tokens):
                value = tokens[next_index].text
                depth += (value == "<") - (value == ">")
                next_index += 1
                if depth == 0:
                    break
        following = [item.text for item in tokens[next_index:next_index + 2]]
        message = None
        if token.text == "Task" and not (len(following) == 2 and following[0] == "." and following[1] in TASK_PRIMITIVES):
            message = "Use Tasking ViewTaskStore / TaskingCore TaskSlot instead of raw Task creation, handles, or aliases."
        elif token.text in UNMANAGED_TYPES:
            message = "Use Tasking for unstructured work; raw scheduling types are prohibited."
        elif token.text in RIVE_LEGACY_SYMBOLS:
            message = "Use the new Rive Apple API and Data Binding; Legacy entry points are prohibited."
        elif token.text in ANIMATION_SYMBOLS:
            message = "Use ScopedAnimation AnimationScope / animationBarrier instead of raw animation transactions."
        elif previous == "." and token.text in ANIMATION_MEMBERS:
            # Require the explicit library type for multi-trigger factories. The
            # shorthand .animation(...) is intentionally reserved by this policy.
            if not (token.text == "animation" and receiver == "AnimationTrigger"):
                message = "Use AnimationScope or explicit AnimationTrigger.animation; raw animation/transaction modifiers are prohibited."
        elif previous == "." and receiver == "UIView" and token.text in UIKIT_ANIMATION_MEMBERS:
            message = "Use ScopedAnimation for product animation; raw UIKit animation entry points are prohibited."
        elif token.text == "EquatableView" or (previous == "." and token.text in {"equatable", "equatableBody"}):
            message = "Use AppMacros @Equatable + EquatableBodyView with all value inputs compared; direct gates and aliases are prohibited."
        elif token.text == "func" and following == ["=", "="]:
            message = "Use generated equality (AppMacros for SwiftUI views); handwritten == witnesses are prohibited."
        if message:
            line = source.count("\n", 0, token.offset) + 1
            column = token.offset - source.rfind("\n", 0, token.offset)
            found.append((line, column, message))
    return found if found else boundary_violations(source, tokens)


def swift_files(root):
    for directory, folders, files in root.walk(follow_symlinks=False):
        folders[:] = sorted(name for name in folders if name not in GENERATED and name != "result" and not name.startswith("result-"))
        for name in folders:
            if (directory / name).is_symlink():
                raise ValueError(f"Source directory symlinks are not supported: {directory / name}")
        for name in sorted(files):
            path = directory / name
            # Path.walk lists directory symlinks in files when follow_symlinks=False.
            if name not in GENERATED and name != "result" and not name.startswith("result-") and path.is_symlink() and path.is_dir():
                raise ValueError(f"Source directory symlinks are not supported: {path}")
            if path.suffix == ".swift":
                if path.is_symlink():
                    raise ValueError(f"Swift source symlinks are not supported: {path}")
                yield path


def check(root):
    count, errors = 0, []
    for path in swift_files(root):
        count += 1
        try:
            errors.extend(f"{path.relative_to(root)}:{line}:{column}: error: {message}" for line, column, message in violations(path.read_text()))
        except (ValueError, UnicodeError) as error:
            errors.append(f"{path.relative_to(root)}: error: Cannot lint Swift source: {error}")
    if count == 0:
        errors.append("error: No Swift sources found; check the repository root.")
    return count, errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    try:
        count, errors = check(args.root.resolve())
    except (OSError, ValueError) as error:
        print(f"error: Swift policy check failed: {error}")
        return 1
    if errors:
        print("\n".join(errors))
        return 1
    print(f"Swift library policy passed: {count} source files; Tasking, ScopedAnimation and AppMacros entry points enforced.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

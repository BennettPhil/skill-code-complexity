#!/usr/bin/env python3
"""Code complexity analyzer - stdlib only.

Computes cyclomatic complexity and function length for Python, JS, and TS files.
"""

import argparse
import ast
import json
import os
import re
import sys
from dataclasses import dataclass, asdict
from typing import List


@dataclass
class FunctionMetric:
    file: str
    function: str
    complexity: int
    lines: int


# ======================== Python analyzer ========================


class _PythonComplexityVisitor(ast.NodeVisitor):
    """Walk a Python AST and collect per-function complexity."""

    _DECISION_NODES = (
        ast.If,
        ast.For,
        ast.While,
        ast.ExceptHandler,
        ast.With,
        ast.Assert,
        ast.IfExp,
    )

    def __init__(self, filepath: str):
        self.filepath = filepath
        self.metrics: List[FunctionMetric] = []

    def _complexity_of(self, node: ast.AST) -> int:
        """Cyclomatic complexity of a function body (base = 1)."""
        complexity = 1
        for child in ast.walk(node):
            if isinstance(child, self._DECISION_NODES):
                complexity += 1
            if isinstance(child, ast.BoolOp):
                complexity += len(child.values) - 1
            if isinstance(child, ast.comprehension):
                complexity += len(child.ifs)
        return complexity

    def _func_lines(self, node: ast.AST) -> int:
        """Line count of function body."""
        lines = set()
        for child in ast.walk(node):
            if hasattr(child, 'lineno'):
                lines.add(child.lineno)
            if hasattr(child, 'end_lineno') and child.end_lineno is not None:
                for ln in range(child.lineno, child.end_lineno + 1):
                    lines.add(ln)
        if not lines:
            return 0
        return max(lines) - min(lines) + 1

    def _visit_function(self, node):
        name = node.name
        complexity = self._complexity_of(node)
        lines = self._func_lines(node)
        self.metrics.append(FunctionMetric(
            file=self.filepath,
            function=name,
            complexity=complexity,
            lines=lines,
        ))
        self.generic_visit(node)

    def visit_FunctionDef(self, node):
        self._visit_function(node)

    def visit_AsyncFunctionDef(self, node):
        self._visit_function(node)


def analyze_python(filepath: str) -> List[FunctionMetric]:
    """Analyze a Python file using the ast module."""
    with open(filepath, 'r', encoding='utf-8', errors='replace') as fh:
        source = fh.read()
    try:
        tree = ast.parse(source, filename=filepath)
    except SyntaxError:
        print(f"WARNING: syntax error in {filepath}, skipping", file=sys.stderr)
        return []
    visitor = _PythonComplexityVisitor(filepath)
    visitor.visit(tree)
    return visitor.metrics


# ======================== JS/TS analyzer ========================

_JS_DECISION_PATTERNS = [
    re.compile(r'\bif\s*\('),
    re.compile(r'\belse\s+if\s*\('),
    re.compile(r'\bfor\s*\('),
    re.compile(r'\bwhile\s*\('),
    re.compile(r'\bcase\s+'),
    re.compile(r'\bcatch\s*\('),
    re.compile(r'&&'),
    re.compile(r'\|\|'),
    re.compile(r'\?[^?.{}]'),
]

_JS_FUNC_START = re.compile(
    r'(?:'
    r'(?:export\s+)?(?:default\s+)?(?:async\s+)?function\s+(\w+)'
    r'|'
    r'(?:export\s+)?(?:const|let|var)\s+(\w+)\s*=\s*(?:async\s+)?(?:\([^)]*\)|[a-zA-Z_]\w*)\s*=>'
    r'|'
    r'(?:(?:async|static|get|set|public|private|protected)\s+)*(\w+)\s*\([^)]*\)\s*\{'
    r')'
)


def _count_js_decisions(lines: List[str]) -> int:
    """Count decision points in a block of JS/TS source lines."""
    count = 1
    for line in lines:
        stripped = re.sub(r'//.*$', '', line)
        stripped = re.sub(r'/\*.*?\*/', '', stripped)
        for pat in _JS_DECISION_PATTERNS:
            count += len(pat.findall(stripped))
    return count


def analyze_js(filepath: str) -> List[FunctionMetric]:
    """Analyze a JS/TS file using regex heuristics."""
    with open(filepath, 'r', encoding='utf-8', errors='replace') as fh:
        source_lines = fh.readlines()

    metrics: List[FunctionMetric] = []
    i = 0
    while i < len(source_lines):
        line = source_lines[i]
        m = _JS_FUNC_START.search(line)
        if m:
            func_name = m.group(1) or m.group(2) or m.group(3)
            if not func_name or func_name in ('if', 'else', 'for', 'while', 'switch', 'catch', 'return'):
                i += 1
                continue
            start = i
            depth = 0
            found_open = False
            j = i
            while j < len(source_lines):
                for ch in source_lines[j]:
                    if ch == '{':
                        depth += 1
                        found_open = True
                    elif ch == '}':
                        depth -= 1
                if found_open and depth <= 0:
                    break
                j += 1
            end = j
            body = source_lines[start:end + 1]
            complexity = _count_js_decisions(body)
            line_count = len(body)
            metrics.append(FunctionMetric(
                file=filepath,
                function=func_name,
                complexity=complexity,
                lines=line_count,
            ))
            i = end + 1
        else:
            i += 1
    return metrics


# ======================== Dispatcher ========================

_EXT_MAP = {
    '.py': analyze_python,
    '.js': analyze_js,
    '.jsx': analyze_js,
    '.ts': analyze_js,
    '.tsx': analyze_js,
}


def collect_files(paths: List[str]) -> List[str]:
    """Expand directories into supported source files."""
    result = []
    for p in paths:
        if os.path.isdir(p):
            for root, _dirs, files in os.walk(p):
                for fname in sorted(files):
                    ext = os.path.splitext(fname)[1]
                    if ext in _EXT_MAP:
                        result.append(os.path.join(root, fname))
        elif os.path.isfile(p):
            result.append(p)
        else:
            print(f"ERROR: path not found: {p}", file=sys.stderr)
    return result


def analyze_file(filepath: str) -> List[FunctionMetric]:
    ext = os.path.splitext(filepath)[1]
    analyzer = _EXT_MAP.get(ext)
    if analyzer is None:
        return []
    return analyzer(filepath)


# ======================== Formatters ========================


def format_text(metrics: List[FunctionMetric]) -> str:
    if not metrics:
        return "No functions found."
    col_file = max(len(m.file) for m in metrics)
    col_file = max(col_file, 4)
    col_func = max(len(m.function) for m in metrics)
    col_func = max(col_func, 8)

    header = f"{'File':<{col_file}}  {'Function':<{col_func}}  {'Complexity':>10}  {'Lines':>5}"
    sep = '\u2500' * len(header)
    lines = [header, sep]
    for m in metrics:
        lines.append(
            f"{m.file:<{col_file}}  {m.function:<{col_func}}  "
            f"{m.complexity:>10}  {m.lines:>5}"
        )
    return '\n'.join(lines)


def format_json(metrics: List[FunctionMetric]) -> str:
    return json.dumps([asdict(m) for m in metrics], indent=2)


# ======================== Main ========================


def main():
    parser = argparse.ArgumentParser(
        description='Analyze code complexity of source files.'
    )
    parser.add_argument('paths', nargs='*', default=['.'],
                        help='Files or directories to analyze')
    parser.add_argument('--threshold', type=int, default=None,
                        help='Fail (exit 1) if any function exceeds this complexity')
    parser.add_argument('--format', dest='fmt', choices=['text', 'json'],
                        default='text', help='Output format')
    args = parser.parse_args()

    files = collect_files(args.paths)
    if not files:
        if args.fmt == 'json':
            print('[]')
        else:
            print("No supported files found.")
        sys.exit(0)

    all_metrics: List[FunctionMetric] = []
    for fpath in files:
        all_metrics.extend(analyze_file(fpath))

    all_metrics.sort(key=lambda m: (-m.complexity, -m.lines))

    if args.fmt == 'json':
        print(format_json(all_metrics))
    else:
        print(format_text(all_metrics))

    if args.threshold is not None and all_metrics:
        violations = [m for m in all_metrics if m.complexity > args.threshold]
        if violations:
            print(
                f"\nTHRESHOLD EXCEEDED: {len(violations)} function(s) "
                f"have complexity > {args.threshold}",
                file=sys.stderr,
            )
            sys.exit(1)


if __name__ == '__main__':
    main()

---
name: code-complexity
description: >
  A code complexity analyzer that computes cyclomatic complexity, cognitive
  complexity, and function length metrics for Python, JavaScript, and TypeScript
  source files. Outputs a ranked list of the most complex functions with
  threshold-based pass/fail for CI integration.
version: 0.1.0
license: Apache-2.0
---

# code-complexity

Analyze source files to measure function-level complexity metrics:

- **Cyclomatic complexity** – counts decision points (branches, loops, boolean operators).
- **Function length** – number of source lines in the function body.

Supported languages: **Python**, **JavaScript**, **TypeScript**.

## Quick Start

```bash
# Analyze a single file
./scripts/run.sh path/to/file.py

# Analyze a directory recursively
./scripts/run.sh src/

# CI mode – fail if any function has complexity > 10
./scripts/run.sh --threshold=10 src/

# JSON output
./scripts/run.sh --format=json src/
```

## Output

A ranked table (highest complexity first):

```
File                          Function              Complexity  Lines
────────────────────────────────────────────────────────────────────────
src/engine.py                 process_events              14      87
src/engine.py                 dispatch                     9      42
src/utils.py                  parse_config                 3      18
```

## CI Integration

Use `--threshold=N` to set a maximum allowed cyclomatic complexity.
The tool exits with code **1** if any function exceeds the threshold,
making it suitable for CI pipelines and pre-commit hooks.

## Methodology

### Python
Uses the `ast` module for accurate parsing. Decision points counted:
`if`, `elif`, `for`, `while`, `except`, `and`, `or`, `assert`, `with`,
ternary (`IfExp`), and comprehension filters.

### JavaScript / TypeScript
Uses regex-based heuristics. Tokens counted as decision points:
`if`, `else if`, `for`, `while`, `case`, `catch`, `&&`, `||`, `?` (ternary).
Function boundaries detected via `function`, arrow functions, and class methods.

# code-complexity -- Usage Examples

## 1. Analyze a single Python file

```bash
./scripts/run.sh myapp/views.py
```

Output:
```
File              Function            Complexity  Lines
──────────────────────────────────────────────────────────
myapp/views.py    handle_upload               8     45
myapp/views.py    validate_form               5     28
myapp/views.py    index                       1      6
```

## 2. Scan an entire project

```bash
./scripts/run.sh src/ lib/ tests/
```

All `.py`, `.js`, `.jsx`, `.ts`, and `.tsx` files under those directories are
analyzed recursively.

## 3. CI gate with threshold

```bash
./scripts/run.sh --threshold=10 src/
```

- Exit code **0**: all functions have complexity <= 10.
- Exit code **1**: at least one function exceeds the threshold.

Typical CI integration (GitHub Actions):

```yaml
- name: Check code complexity
  run: |
    .soup/skills/code-complexity/scripts/run.sh --threshold=15 src/
```

## 4. JSON output for tooling

```bash
./scripts/run.sh --format=json src/ > complexity-report.json
```

```json
[
  {
    "file": "src/engine.py",
    "function": "process_events",
    "complexity": 14,
    "lines": 87
  },
  {
    "file": "src/utils.js",
    "function": "parseConfig",
    "complexity": 6,
    "lines": 32
  }
]
```

## 5. Combine with other tools

Pipe JSON output to `jq` for custom queries:

```bash
# Top 5 most complex functions
./scripts/run.sh --format=json src/ | jq '.[0:5]'

# Functions with complexity > 10
./scripts/run.sh --format=json src/ | jq '[.[] | select(.complexity > 10)]'

# Total complexity score
./scripts/run.sh --format=json src/ | jq '[.[].complexity] | add'
```

## 6. Pre-commit hook

Add to `.pre-commit-config.yaml` or a git hook:

```bash
#!/usr/bin/env bash
# .git/hooks/pre-commit
changed_files=$(git diff --cached --name-only --diff-filter=ACM | grep -E '\.(py|js|ts|jsx|tsx)$')
if [ -n "$changed_files" ]; then
    .soup/skills/code-complexity/scripts/run.sh --threshold=15 $changed_files
fi
```

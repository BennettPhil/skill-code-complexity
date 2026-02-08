#!/usr/bin/env bash
# Entry point for the code-complexity skill.
# Forwards all arguments to the Python analyzer.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec python3 "${SCRIPT_DIR}/analyze.py" "$@"

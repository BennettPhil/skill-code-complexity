#!/usr/bin/env bash
# Comprehensive tests for the code-complexity analyzer.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANALYZE="${SCRIPT_DIR}/analyze.py"
PASS=0
FAIL=0
TMPDIR_BASE="$(mktemp -d /tmp/code-complexity-test.XXXXXX)"

cleanup() {
    rm -rf "${TMPDIR_BASE}"
}
trap cleanup EXIT

pass() {
    PASS=$((PASS + 1))
    echo "  PASS: $1"
}

fail() {
    FAIL=$((FAIL + 1))
    echo "  FAIL: $1"
    if [ -n "${2:-}" ]; then
        echo "        $2"
    fi
}

# ===================== Test 1: Simple Python function =====================

echo "Test 1: Simple Python function (low complexity)"
cat > "${TMPDIR_BASE}/simple.py" << 'EOF'
def greet(name):
    return f"Hello, {name}!"
EOF

OUTPUT="$(python3 "${ANALYZE}" "${TMPDIR_BASE}/simple.py" 2>&1)"
if echo "$OUTPUT" | grep -qF -- "greet"; then
    pass "function 'greet' detected"
else
    fail "function 'greet' not found" "$OUTPUT"
fi

# Complexity should be 1 (no branches)
if echo "$OUTPUT" | grep -qF -- "         1"; then
    pass "complexity is 1"
else
    fail "expected complexity 1" "$OUTPUT"
fi

# ===================== Test 2: Complex Python function ====================

echo "Test 2: Complex Python function (high complexity)"
cat > "${TMPDIR_BASE}/complex.py" << 'PYEOF'
def process(data):
    result = []
    for item in data:
        if item is None:
            continue
        elif isinstance(item, list):
            for sub in item:
                if sub > 0 and sub < 100:
                    result.append(sub)
                elif sub >= 100 or sub == 0:
                    result.append(0)
        else:
            try:
                val = int(item)
                while val > 10:
                    val = val // 2
                result.append(val)
            except (ValueError, TypeError):
                pass
    return result

def simple_add(a, b):
    return a + b
PYEOF

OUTPUT="$(python3 "${ANALYZE}" "${TMPDIR_BASE}/complex.py" 2>&1)"
if echo "$OUTPUT" | grep -qF -- "process"; then
    pass "function 'process' detected"
else
    fail "function 'process' not found" "$OUTPUT"
fi
if echo "$OUTPUT" | grep -qF -- "simple_add"; then
    pass "function 'simple_add' detected"
else
    fail "function 'simple_add' not found" "$OUTPUT"
fi

# process should appear before simple_add (higher complexity first)
PROC_LINE="$(echo "$OUTPUT" | grep -nF -- "process" | head -1 | cut -d: -f1)"
SIMPLE_LINE="$(echo "$OUTPUT" | grep -nF -- "simple_add" | head -1 | cut -d: -f1)"
if [ -n "$PROC_LINE" ] && [ -n "$SIMPLE_LINE" ] && [ "$PROC_LINE" -lt "$SIMPLE_LINE" ]; then
    pass "ranked by complexity (process before simple_add)"
else
    fail "ranking order incorrect" "process at line ${PROC_LINE:-?}, simple_add at line ${SIMPLE_LINE:-?}"
fi

# ===================== Test 3: Async Python function ======================

echo "Test 3: Async Python function"
cat > "${TMPDIR_BASE}/async_funcs.py" << 'PYEOF'
import asyncio

async def fetch_data(url):
    if url.startswith("http"):
        return await asyncio.sleep(1)
    else:
        raise ValueError("bad url")
PYEOF

OUTPUT="$(python3 "${ANALYZE}" "${TMPDIR_BASE}/async_funcs.py" 2>&1)"
if echo "$OUTPUT" | grep -qF -- "fetch_data"; then
    pass "async function 'fetch_data' detected"
else
    fail "async function 'fetch_data' not found" "$OUTPUT"
fi

# ===================== Test 4: JavaScript file ============================

echo "Test 4: JavaScript file with functions"
cat > "${TMPDIR_BASE}/sample.js" << 'EOF'
function calculateScore(items) {
    let score = 0;
    for (let i = 0; i < items.length; i++) {
        if (items[i].type === 'bonus') {
            score += 10;
        } else if (items[i].type === 'penalty') {
            score -= 5;
        } else {
            score += 1;
        }
    }
    return score;
}

function getName() {
    return "test";
}
EOF

OUTPUT="$(python3 "${ANALYZE}" "${TMPDIR_BASE}/sample.js" 2>&1)"
if echo "$OUTPUT" | grep -qF -- "calculateScore"; then
    pass "JS function 'calculateScore' detected"
else
    fail "JS function 'calculateScore' not found" "$OUTPUT"
fi
if echo "$OUTPUT" | grep -qF -- "getName"; then
    pass "JS function 'getName' detected"
else
    fail "JS function 'getName' not found" "$OUTPUT"
fi

# ===================== Test 5: TypeScript file ============================

echo "Test 5: TypeScript file"
cat > "${TMPDIR_BASE}/sample.ts" << 'EOF'
function validate(input: string): boolean {
    if (input.length === 0) {
        return false;
    }
    if (input.length > 100 || input.includes("<")) {
        return false;
    }
    return true;
}
EOF

OUTPUT="$(python3 "${ANALYZE}" "${TMPDIR_BASE}/sample.ts" 2>&1)"
if echo "$OUTPUT" | grep -qF -- "validate"; then
    pass "TS function 'validate' detected"
else
    fail "TS function 'validate' not found" "$OUTPUT"
fi

# ===================== Test 6: Threshold pass =============================

echo "Test 6: Threshold pass (all under threshold)"
python3 "${ANALYZE}" --threshold=50 "${TMPDIR_BASE}/simple.py" > /dev/null 2>&1 && THRESHOLD_RC=0 || THRESHOLD_RC=$?
if [ "$THRESHOLD_RC" -eq 0 ]; then
    pass "exit code 0 when all functions under threshold"
else
    fail "expected exit 0 but got $THRESHOLD_RC"
fi

# ===================== Test 7: Threshold fail =============================

echo "Test 7: Threshold fail (some over threshold)"
OUTPUT="$(python3 "${ANALYZE}" --threshold=1 "${TMPDIR_BASE}/complex.py" 2>&1 || true)"
python3 "${ANALYZE}" --threshold=1 "${TMPDIR_BASE}/complex.py" > /dev/null 2>&1 && THRESHOLD_RC=0 || THRESHOLD_RC=$?
if [ "$THRESHOLD_RC" -eq 1 ]; then
    pass "exit code 1 when function exceeds threshold"
else
    fail "expected exit 1 but got $THRESHOLD_RC"
fi
if echo "$OUTPUT" | grep -qF -- "THRESHOLD EXCEEDED"; then
    pass "threshold exceeded message printed"
else
    fail "threshold exceeded message not found" "$OUTPUT"
fi

# ===================== Test 8: Empty file =================================

echo "Test 8: Empty file"
touch "${TMPDIR_BASE}/empty.py"
OUTPUT="$(python3 "${ANALYZE}" "${TMPDIR_BASE}/empty.py" 2>&1)"
RC=$?
if [ "$RC" -eq 0 ]; then
    pass "empty file does not cause error"
else
    fail "empty file caused exit $RC" "$OUTPUT"
fi
if echo "$OUTPUT" | grep -qF -- "No functions found"; then
    pass "empty file shows 'No functions found'"
else
    fail "expected 'No functions found' message" "$OUTPUT"
fi

# ===================== Test 9: Non-existent file ==========================

echo "Test 9: Non-existent file error"
OUTPUT="$(python3 "${ANALYZE}" "${TMPDIR_BASE}/does_not_exist.py" 2>&1)"
if echo "$OUTPUT" | grep -qF -- "ERROR"; then
    pass "non-existent file produces ERROR message"
else
    fail "expected ERROR for missing file" "$OUTPUT"
fi

# ===================== Test 10: JSON output format ========================

echo "Test 10: JSON output format"
OUTPUT="$(python3 "${ANALYZE}" --format=json "${TMPDIR_BASE}/simple.py" 2>&1)"
VALID_JSON="$(echo "$OUTPUT" | python3 -c "import sys,json; json.load(sys.stdin); print('yes')" 2>/dev/null || echo "no")"
if [ "$VALID_JSON" = "yes" ]; then
    pass "JSON output is valid JSON"
else
    fail "JSON output is not valid JSON" "$OUTPUT"
fi
if echo "$OUTPUT" | grep -qF -- '"function": "greet"'; then
    pass "JSON contains function name"
else
    fail "JSON missing function name" "$OUTPUT"
fi
if echo "$OUTPUT" | grep -qF -- '"complexity"'; then
    pass "JSON contains complexity field"
else
    fail "JSON missing complexity field" "$OUTPUT"
fi

# ===================== Test 11: Directory scanning ========================

echo "Test 11: Directory scanning"
mkdir -p "${TMPDIR_BASE}/subdir"
cp "${TMPDIR_BASE}/simple.py" "${TMPDIR_BASE}/subdir/"
cp "${TMPDIR_BASE}/sample.js" "${TMPDIR_BASE}/subdir/"

OUTPUT="$(python3 "${ANALYZE}" "${TMPDIR_BASE}/subdir" 2>&1)"
if echo "$OUTPUT" | grep -qF -- "greet"; then
    pass "directory scan found Python function"
else
    fail "directory scan missed Python function" "$OUTPUT"
fi
if echo "$OUTPUT" | grep -qF -- "calculateScore"; then
    pass "directory scan found JS function"
else
    fail "directory scan missed JS function" "$OUTPUT"
fi

# ===================== Test 12: JSON empty output =========================

echo "Test 12: JSON output for empty file"
OUTPUT="$(python3 "${ANALYZE}" --format=json "${TMPDIR_BASE}/empty.py" 2>&1)"
if [ "$OUTPUT" = "[]" ]; then
    pass "JSON output for empty file is []"
else
    fail "expected [] for empty file JSON" "$OUTPUT"
fi

# ===================== Summary ============================================

echo ""
echo "==============================="
echo "Results: ${PASS} passed, ${FAIL} failed"
echo "==============================="

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0

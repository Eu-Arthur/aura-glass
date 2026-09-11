#!/usr/bin/env bash
# Assert aura-glass-bench executes hardware checks, scoring, and auto-tuning.
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$REPO_ROOT/bin/aura-glass"
BENCH_BIN="$REPO_ROOT/bin/aura-glass-bench"

fail=0
note() { printf '  %s\n' "$*"; fail=1; }

# 1. Check executable and help
[ -x "$BENCH_BIN" ] || note "bin/aura-glass-bench is not executable"
out_help="$("$BENCH_BIN" --help)" || note "aura-glass-bench --help failed"
[[ "$out_help" == *"aura-glass-bench"* ]] || note "--help output missing command name"

# 2. Check standard run with --quick
out_bench="$("$BENCH_BIN" --quick)" || note "aura-glass-bench --quick failed"
[[ "$out_bench" == *"Aura Glass GPU Benchmark"* ]] || note "missing benchmark card header"
[[ "$out_bench" == *"Hardware:"* ]] || note "missing Hardware field"
[[ "$out_bench" == *"Score:"* ]] || note "missing Score field"
[[ "$out_bench" == *"Rating:"* ]] || note "missing Rating field"

# 3. Check JSON output schema
json_bench="$("$BENCH_BIN" --json --quick)" || note "aura-glass-bench --json failed"
printf '%s' "$json_bench" | python3 -c '
import json, sys
data = json.load(sys.stdin)
assert "score" in data, "missing score in json"
assert "tier" in data, "missing tier in json"
assert "gpu" in data, "missing gpu object"
assert "tuning" in data, "missing tuning object"
assert "recommended_mode" in data["tuning"], "missing recommended_mode in tuning"
score = data["score"]
assert 0 <= score <= 100, f"score out of bounds: {score}"
' || note "benchmark JSON schema validation failed"

# 4. Check --tune mode
out_tune="$("$BENCH_BIN" --quick --tune)" || note "aura-glass-bench --tune failed"
[[ "$out_tune" == *"Hardware Auto-Tuning Analysis"* ]] || note "missing auto-tuning analysis header"

# 5. Check CLI delegation via aura-glass
out_cli_bench="$("$CLI" bench --quick)" || note "aura-glass bench delegation failed"
[[ "$out_cli_bench" == *"Aura Glass GPU Benchmark"* ]] || note "CLI bench delegation missing output"

if [ "$fail" -eq 1 ]; then
    printf 'check-bench.sh: FAILED\n' >&2
    exit 1
fi
printf 'check-bench.sh: passed (benchmark scoring, JSON schema, & auto-tuning verified)\n'

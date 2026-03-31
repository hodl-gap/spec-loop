#!/bin/bash
# run_spec.sh — Two-phase spec runner
# Phase 1: Interactive test co-design with human
# Phase 2: Autonomous build loop (Ralph-pattern fresh context)
#
# Usage: ./run_spec.sh path/to/SPEC.md [max_iterations]
#
# Dependencies: claude CLI

set -euo pipefail

SPEC_PATH="${1:?Usage: ./run_spec.sh path/to/SPEC.md [max_iterations]}"
MAX_ITERATIONS="${2:-20}"
ITER_TIMEOUT="${3:-600}"  # Per-iteration timeout in seconds (default: 10 min)
SPEC_DIR="$(dirname "$(realpath "$SPEC_PATH")")"
SPEC_NAME="$(basename "$SPEC_PATH" .md)"
PROJECT_DIR="${SPEC_DIR}/${SPEC_NAME}-project"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROMPT_TEMPLATE="${SCRIPT_DIR}/PROMPT_phase2.md"

# Resolve spec path to absolute
SPEC_PATH="$(realpath "$SPEC_PATH")"

# Run log: one JSON line per iteration, always written locally
RUN_ID="$(date +%Y%m%d_%H%M%S)_$$"
RUN_LOG="$PROJECT_DIR/run_log.jsonl"

echo "============================================"
echo "  Spec Runner"
echo "  Spec:       $SPEC_PATH"
echo "  Project:    $PROJECT_DIR"
echo "  Max iters:  $MAX_ITERATIONS"
echo "  Run ID:     $RUN_ID"
echo "  Log:        $RUN_LOG"
echo "============================================"
echo ""

# Create project directory if needed
mkdir -p "$PROJECT_DIR" 2>/dev/null || true

# ─────────────────────────────────────────────
# Logging helpers
# ─────────────────────────────────────────────

log_event() {
    # Appends a JSON line to run_log.jsonl
    # Usage: log_event '{"iteration": 1, "status": "done", ...}'
    echo "$1" >> "$RUN_LOG"
}

upload_to_braintrust() {
    # Uploads run_log.jsonl to Braintrust project logs if API key is set
    if [ -z "${BRAINTRUST_API_KEY:-}" ]; then
        return
    fi
    if ! command -v python3 >/dev/null 2>&1; then
        echo "  (skipping Braintrust upload: python3 not found)"
        return
    fi
    echo "  Uploading run log to Braintrust..."
    python3 -c "
import json, os, sys
try:
    import braintrust
except ImportError:
    print('  (skipping: pip install braintrust to enable uploads)')
    sys.exit(0)

logger = braintrust.init_logger(project='spec-runner')
log_path = '$RUN_LOG'
with open(log_path) as f:
    events = [json.loads(line) for line in f if line.strip()]

for event in events:
    logger.log(
        input={'spec': event.get('spec', ''), 'iteration': event.get('iteration', 0)},
        output={'status': event.get('status', ''), 'files_changed': event.get('files_changed', False)},
        metadata={
            'run_id': '$RUN_ID',
            'project_dir': '$PROJECT_DIR',
            'duration_s': event.get('duration_s', 0),
            'exit_reason': event.get('exit_reason', ''),
            'iteration': event.get('iteration', 0),
            'phase': event.get('phase', 'build'),
        },
        tags=['spec-runner', event.get('status', 'unknown')],
    )
logger.flush()
print(f'  Uploaded {len(events)} events to Braintrust (project: spec-runner)')
" 2>&1 || echo "  (Braintrust upload failed, local log preserved)"
}

# ─────────────────────────────────────────────
# Phase 1: Interactive test co-design
# ─────────────────────────────────────────────

if [ ! -d "$PROJECT_DIR/tests" ] || [ -z "$(ls -A "$PROJECT_DIR/tests" 2>/dev/null)" ]; then
    echo "=== Phase 1: Co-design test suite (interactive) ==="
    echo "An interactive Claude session will open."
    echo "Review and approve the proposed tests, then exit the session."
    echo ""
    echo "Press Enter to start..."
    read -r

    claude --add-dir "$SPEC_DIR" \
        --permission-mode acceptEdits \
        --append-system-prompt "The user has invoked /spec-eval on $SPEC_PATH with project directory $PROJECT_DIR. Start Step 0 (spec sufficiency check) immediately. When tests are saved, tell the user to exit so Phase 2 can start." \
        "Run /spec-eval on $SPEC_PATH — project directory is $PROJECT_DIR"

    # Verify tests were created
    if [ ! -d "$PROJECT_DIR/tests" ] || [ -z "$(ls -A "$PROJECT_DIR/tests" 2>/dev/null)" ]; then
        echo ""
        echo "ERROR: No tests found in $PROJECT_DIR/tests/"
        echo "Phase 1 must produce test scripts before Phase 2 can run."
        echo "Re-run this script to try again."
        exit 1
    fi

    echo ""
    echo "============================================"
    echo "  Phase 1 complete!"
    echo "  Tests saved to $PROJECT_DIR/tests/"
    echo "  Starting Phase 2 (autonomous build) in 5 seconds..."
    echo "  Press Ctrl+C now to abort if tests need changes."
    echo "============================================"
    echo ""
    sleep 5
else
    echo "=== Phase 1: Skipped (tests already exist in $PROJECT_DIR/tests/) ==="
    echo ""
fi

# ─────────────────────────────────────────────
# Phase 1.5: Environment probe
# ─────────────────────────────────────────────
# Read manifest.json, check which dependencies are available,
# write env_available.json so Phase 2 knows what to skip.

MANIFEST="$PROJECT_DIR/tests/manifest.json"
ENV_FILE="$PROJECT_DIR/env_available.json"

if [ -f "$MANIFEST" ]; then
    echo "=== Phase 1.5: Environment probe ==="

    # Probe common dependencies
    HAS_PSQL=$(which psql >/dev/null 2>&1 && echo true || echo false)
    HAS_DOCKER=$(which docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 && echo true || echo false)
    HAS_NPM=$(which npm >/dev/null 2>&1 && echo true || echo false)
    HAS_NODE=$(which node >/dev/null 2>&1 && echo true || echo false)
    HAS_PYTHON=$(which python3 >/dev/null 2>&1 && echo true || echo false)
    HAS_ALEMBIC=$(which alembic >/dev/null 2>&1 || python3 -c "import alembic" 2>/dev/null && echo true || echo false)
    HAS_DOTENV=$( [ -f "$PROJECT_DIR/.env" ] && grep -qv '=$' "$PROJECT_DIR/.env" 2>/dev/null && echo true || echo false)

    cat > "$ENV_FILE" <<ENVJSON
{
  "postgresql": $HAS_PSQL,
  "docker": $HAS_DOCKER,
  "npm": $HAS_NPM,
  "node": $HAS_NODE,
  "python3": $HAS_PYTHON,
  "alembic": $HAS_ALEMBIC,
  "dotenv": $HAS_DOTENV
}
ENVJSON

    echo "  Environment:"
    echo "    postgresql: $HAS_PSQL"
    echo "    docker:     $HAS_DOCKER"
    echo "    npm:        $HAS_NPM"
    echo "    node:       $HAS_NODE"
    echo "    alembic:    $HAS_ALEMBIC"
    echo "    .env keys:  $HAS_DOTENV"

    # Check which tests have unmet requirements.
    # Only defer for INFRASTRUCTURE that can't be auto-installed (postgresql,
    # docker, etc). Python packages (scipy, requests) are pip-installable —
    # Phase 2 should install them, not skip the tests.
    if command -v python3 >/dev/null 2>&1; then
        SKIP_INFO=$(python3 -c "
import json, sys
manifest = json.load(open('$MANIFEST'))
env = json.load(open('$ENV_FILE'))
tests = manifest.get('tests', [])

# These are infrastructure — can't be pip-installed
INFRA_DEPS = {'postgresql', 'psql', 'docker', 'npm', 'node', 'redis',
              'kafka', 'mongodb', 'mysql', 'nginx', 'dotenv'}

skipped = []
for t in tests:
    reqs = t.get('requires', [])
    # Only check infra deps against env; ignore pip-installable packages
    infra_missing = [r for r in reqs if r in INFRA_DEPS and not env.get(r, False)]
    if infra_missing:
        skipped.append(f\"  {t['file']}: needs {', '.join(infra_missing)}\")
        t['deferred'] = True
        t['deferred_reason'] = f\"missing infra: {', '.join(infra_missing)}\"
    else:
        t.pop('deferred', None)
        t.pop('deferred_reason', None)
if skipped:
    print(f'Deferring {len(skipped)} tests (infrastructure unavailable):')
    for s in skipped:
        print(s)
else:
    print('All test dependencies available.')
json.dump(manifest, open('$MANIFEST', 'w'), indent=2)
" 2>&1) || SKIP_INFO="(manifest parse skipped)"
        echo ""
        echo "  $SKIP_INFO"
    fi
    echo ""
else
    echo "=== Phase 1.5: Skipped (no manifest.json) ==="
    echo ""
fi

# ─────────────────────────────────────────────
# Phase 2: Autonomous build loop
# ─────────────────────────────────────────────

echo "=== Phase 2: Autonomous build loop ==="
echo "Starting up to $MAX_ITERATIONS iterations with fresh context each."
echo ""

RUN_START=$(date +%s)
log_event "{\"run_id\": \"$RUN_ID\", \"phase\": \"start\", \"spec\": \"$SPEC_PATH\", \"project\": \"$PROJECT_DIR\", \"max_iterations\": $MAX_ITERATIONS, \"timestamp\": \"$(date -Iseconds)\"}"

# Initialize git if not already a repo (for rollback safety)
if [ ! -d "$PROJECT_DIR/.git" ]; then
    (cd "$PROJECT_DIR" && git init -q && git add -A && git commit -q -m "Initial: tests from Phase 1" 2>/dev/null) || true
fi

# Build the Phase 2 prompt from template
PROMPT=$(sed \
    -e "s|{{SPEC_PATH}}|$SPEC_PATH|g" \
    -e "s|{{PROJECT_DIR}}|$PROJECT_DIR|g" \
    "$PROMPT_TEMPLATE")

# Circuit breaker: track consecutive iterations with no file changes
STAGNANT_COUNT=0
MAX_STAGNANT=3

for i in $(seq 1 "$MAX_ITERATIONS"); do
    ITER_START=$(date +%s)
    echo "--- Iteration $i / $MAX_ITERATIONS [$(date '+%H:%M:%S')] ---"

    # Snapshot file state before iteration (for stall detection)
    BEFORE_HASH=$(cd "$PROJECT_DIR" && find . -name '.git' -prune -o -type f -print0 | sort -z | xargs -0 md5sum 2>/dev/null | md5sum)

    echo "  Starting claude (timeout: ${ITER_TIMEOUT}s, budget: \$5)..."
    OUTPUT=$(timeout "$ITER_TIMEOUT" claude --print \
        --dangerously-skip-permissions \
        --max-budget-usd 5 \
        --add-dir "$SPEC_DIR" \
        --add-dir "$PROJECT_DIR" \
        -p "$PROMPT" \
        2>&1 | tee /dev/stderr) || {
        EXIT_CODE=$?
        if [ "$EXIT_CODE" -eq 124 ]; then
            echo ""
            echo "WARNING: Iteration $i timed out after ${ITER_TIMEOUT}s"
        else
            echo ""
            echo "WARNING: Iteration $i exited with code $EXIT_CODE"
        fi
        OUTPUT=""
    }

    # Check for completion
    if echo "$OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
        (cd "$PROJECT_DIR" && git add -A && git commit -q -m "Iteration $i: COMPLETE — all tests pass" 2>/dev/null) || true
        TOTAL_DURATION=$(( $(date +%s) - RUN_START ))
        log_event "{\"run_id\": \"$RUN_ID\", \"phase\": \"build\", \"iteration\": $i, \"status\": \"complete\", \"duration_s\": $ITER_DURATION, \"total_duration_s\": $TOTAL_DURATION, \"spec\": \"$SPEC_PATH\", \"timestamp\": \"$(date -Iseconds)\"}"
        upload_to_braintrust
        echo ""
        echo "============================================"
        echo "  COMPLETE — all tests pass"
        echo "  Iterations used: $i / $MAX_ITERATIONS"
        echo "  Project: $PROJECT_DIR"
        echo "============================================"
        exit 0
    fi

    # Check for blocked
    if echo "$OUTPUT" | grep -q "<promise>BLOCKED</promise>"; then
        (cd "$PROJECT_DIR" && git add -A && git commit -q -m "Iteration $i: BLOCKED" 2>/dev/null) || true
        TOTAL_DURATION=$(( $(date +%s) - RUN_START ))
        log_event "{\"run_id\": \"$RUN_ID\", \"phase\": \"build\", \"iteration\": $i, \"status\": \"blocked\", \"duration_s\": $ITER_DURATION, \"total_duration_s\": $TOTAL_DURATION, \"spec\": \"$SPEC_PATH\", \"timestamp\": \"$(date -Iseconds)\"}"
        upload_to_braintrust
        echo ""
        echo "============================================"
        echo "  BLOCKED — agent cannot proceed"
        echo "  Check $PROJECT_DIR/progress.txt for details"
        echo "  Iterations used: $i / $MAX_ITERATIONS"
        echo "============================================"
        exit 2
    fi

    # Git commit after each iteration (for rollback safety)
    (cd "$PROJECT_DIR" && git add -A && git commit -q -m "Iteration $i" 2>/dev/null) || true

    # Circuit breaker: detect stalls (no file changes)
    AFTER_HASH=$(cd "$PROJECT_DIR" && find . -name '.git' -prune -o -type f -print0 | sort -z | xargs -0 md5sum 2>/dev/null | md5sum)
    if [ "$BEFORE_HASH" = "$AFTER_HASH" ]; then
        STAGNANT_COUNT=$((STAGNANT_COUNT + 1))
        echo "WARNING: No file changes detected ($STAGNANT_COUNT/$MAX_STAGNANT stagnant)"
        if [ "$STAGNANT_COUNT" -ge "$MAX_STAGNANT" ]; then
            echo ""
            TOTAL_DURATION=$(( $(date +%s) - RUN_START ))
            log_event "{\"run_id\": \"$RUN_ID\", \"phase\": \"build\", \"iteration\": $i, \"status\": \"stalled\", \"duration_s\": $ITER_DURATION, \"total_duration_s\": $TOTAL_DURATION, \"spec\": \"$SPEC_PATH\", \"timestamp\": \"$(date -Iseconds)\"}"
            upload_to_braintrust
            echo ""
            echo "============================================"
            echo "  STALLED — $MAX_STAGNANT iterations with no changes"
            echo "  Check $PROJECT_DIR/progress.txt for details"
            echo "  Iterations used: $i / $MAX_ITERATIONS"
            echo "============================================"
            exit 3
        fi
    else
        STAGNANT_COUNT=0
    fi

    ITER_END=$(date +%s)
    ITER_DURATION=$((ITER_END - ITER_START))
    FILES_CHANGED=$( [ "$BEFORE_HASH" != "$AFTER_HASH" ] && echo true || echo false )
    log_event "{\"run_id\": \"$RUN_ID\", \"phase\": \"build\", \"iteration\": $i, \"status\": \"continue\", \"duration_s\": $ITER_DURATION, \"files_changed\": $FILES_CHANGED, \"spec\": \"$SPEC_PATH\", \"timestamp\": \"$(date -Iseconds)\"}"
    echo "--- Iteration $i done (${ITER_DURATION}s) [$(date '+%H:%M:%S')] ---"
    echo ""
done

TOTAL_DURATION=$(( $(date +%s) - RUN_START ))
log_event "{\"run_id\": \"$RUN_ID\", \"phase\": \"build\", \"iteration\": $MAX_ITERATIONS, \"status\": \"max_iterations\", \"total_duration_s\": $TOTAL_DURATION, \"spec\": \"$SPEC_PATH\", \"timestamp\": \"$(date -Iseconds)\"}"
upload_to_braintrust
echo ""
echo "============================================"
echo "  MAX ITERATIONS reached ($MAX_ITERATIONS)"
echo "  Check $PROJECT_DIR/progress.txt for status"
echo "============================================"
exit 1

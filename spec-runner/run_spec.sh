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
SPEC_DIR="$(dirname "$(realpath "$SPEC_PATH")")"
SPEC_NAME="$(basename "$SPEC_PATH" .md)"
PROJECT_DIR="${SPEC_DIR}/${SPEC_NAME}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROMPT_TEMPLATE="${SCRIPT_DIR}/PROMPT_phase2.md"

# Resolve spec path to absolute
SPEC_PATH="$(realpath "$SPEC_PATH")"

echo "============================================"
echo "  Spec Runner"
echo "  Spec:       $SPEC_PATH"
echo "  Project:    $PROJECT_DIR"
echo "  Max iters:  $MAX_ITERATIONS"
echo "============================================"
echo ""

# Create project directory if needed
mkdir -p "$PROJECT_DIR"

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
        "Use /spec-eval on $SPEC_PATH — the project directory is $PROJECT_DIR"

    # Verify tests were created
    if [ ! -d "$PROJECT_DIR/tests" ] || [ -z "$(ls -A "$PROJECT_DIR/tests" 2>/dev/null)" ]; then
        echo "ERROR: No tests found in $PROJECT_DIR/tests/"
        echo "Phase 1 must produce test scripts before Phase 2 can run."
        exit 1
    fi

    echo ""
    echo "Tests saved to $PROJECT_DIR/tests/"
    echo ""
else
    echo "=== Phase 1: Skipped (tests already exist in $PROJECT_DIR/tests/) ==="
    echo ""
fi

# ─────────────────────────────────────────────
# Phase 2: Autonomous build loop
# ─────────────────────────────────────────────

echo "=== Phase 2: Autonomous build loop ==="
echo "Starting up to $MAX_ITERATIONS iterations with fresh context each."
echo ""

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
    echo "--- Iteration $i / $MAX_ITERATIONS ---"

    # Snapshot file state before iteration (for stall detection)
    BEFORE_HASH=$(cd "$PROJECT_DIR" && find . -name '.git' -prune -o -type f -print0 | sort -z | xargs -0 md5sum 2>/dev/null | md5sum)

    OUTPUT=$(claude --print \
        --dangerously-skip-permissions \
        --max-budget-usd 5 \
        --add-dir "$SPEC_DIR" \
        --add-dir "$PROJECT_DIR" \
        -p "$PROMPT" \
        2>&1 | tee /dev/stderr) || true

    # Check for completion
    if echo "$OUTPUT" | grep -q "<promise>COMPLETE</promise>"; then
        (cd "$PROJECT_DIR" && git add -A && git commit -q -m "Iteration $i: COMPLETE — all tests pass" 2>/dev/null) || true
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

    echo "--- Iteration $i done, continuing... ---"
    echo ""
done

echo ""
echo "============================================"
echo "  MAX ITERATIONS reached ($MAX_ITERATIONS)"
echo "  Check $PROJECT_DIR/progress.txt for status"
echo "============================================"
exit 1

#!/bin/bash
# Install claude-tools: spec-runner + eval skills
# Usage: ./install.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Installing claude-tools..."

# Spec runner
mkdir -p ~/.claude/spec-runner
cp -r "$SCRIPT_DIR/spec-runner/"* ~/.claude/spec-runner/
chmod +x ~/.claude/spec-runner/run_spec.sh

# Skills
mkdir -p ~/.claude/skills/spec-eval ~/.claude/skills/eval-creator
cp -r "$SCRIPT_DIR/skills/spec-eval/"* ~/.claude/skills/spec-eval/
cp -r "$SCRIPT_DIR/skills/eval-creator/"* ~/.claude/skills/eval-creator/

echo ""
echo "Installed:"
echo "  ~/.claude/spec-runner/run_spec.sh    — autonomous spec builder"
echo "  ~/.claude/skills/spec-eval/          — interactive test co-design"
echo "  ~/.claude/skills/eval-creator/       — post-hoc skill evaluation"
echo ""
echo "Usage:"
echo "  ~/.claude/spec-runner/run_spec.sh path/to/YOUR_SPEC.md"
echo ""
echo "Requirements: claude CLI installed and authenticated"

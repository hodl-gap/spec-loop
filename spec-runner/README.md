# Spec Runner

Two-phase tool for building projects from specification documents.

## Usage

```bash
./run_spec.sh path/to/YOUR_SPEC.md [max_iterations]
```

## How it works

**Phase 1 (Interactive):** Opens a Claude Code session with the `/spec-eval` skill.
You and Claude co-design a test suite from your spec — reviewing proposed checks,
adjusting thresholds, adding edge cases. Tests are saved to `<project>/tests/`.

**Phase 2 (Autonomous):** A bash loop runs `claude --print` with fresh context on
each iteration. Each iteration reads the spec, tests, and progress log, then builds
the next task. Loops until all tests pass or max iterations reached.

## Requirements

- `claude` CLI installed and authenticated
- `/spec-eval` skill installed (`~/.claude/skills/spec-eval/`)

## File structure

```
spec-runner/
├── run_spec.sh          # The loop harness
├── PROMPT_phase2.md     # Prompt template for autonomous iterations
└── README.md            # This file
```

## What it produces

```
your-project/
├── tests/
│   ├── manifest.json         # Test metadata (created in Phase 1)
│   ├── test_step1.py         # Acceptance tests (created in Phase 1)
│   └── test_step2.py
├── tasks.json                # Task decomposition (created in Phase 2, iteration 1)
├── progress.txt              # Append-only iteration log
└── src/                      # Project code (built by Phase 2)
```

## Spec requirements

Your spec.md should have:
- Clear steps with concrete outputs
- Verifiable acceptance criteria (thresholds, data shapes, existence checks)
- Input/output descriptions per step

Works best with data pipeline specs, API integration workflows, and automation
blueprints. Not suitable for subjective/qualitative outputs (use `/eval-creator`
for those).

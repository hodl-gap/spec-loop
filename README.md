# Claude Tools

Portable toolkit for spec-driven development with Claude Code.

## What's included

| Tool | Purpose |
|------|---------|
| **spec-runner** | Two-phase autonomous project builder: interactive test co-design (Phase 1) + Ralph-pattern build loop with fresh context per iteration (Phase 2) |
| **spec-eval** | CC skill that co-designs a test suite from any .md spec through interactive conversation. Includes spec sufficiency checking. |
| **eval-creator** | CC skill for post-hoc evaluation of existing skills using Braintrust traces. Human-AI rubric co-design with binary pass/fail assertions. |

## Install

```bash
git clone <this-repo>
cd claude-tools
./install.sh
```

Requires: `claude` CLI installed and authenticated. No other dependencies.

## Usage

### Build a project from a spec

```bash
~/.claude/spec-runner/run_spec.sh path/to/YOUR_SPEC.md [max_iterations]
```

Phase 1 opens an interactive Claude session where you co-design tests from the spec.
Phase 2 runs an autonomous bash loop — fresh `claude --print` context per iteration,
building until all tests pass.

### Evaluate an existing skill

Open Claude Code and say:
```
evaluate the recent-research skill
```

The eval-creator skill triggers and walks you through trace review, category
emergence, assertion design, and iterative grading.

## Architecture

```
spec-runner/run_spec.sh
  │
  ├─ Phase 1: claude (interactive)
  │    └─ /spec-eval skill
  │         ├─ Step 0: Spec sufficiency check (5-element checklist)
  │         ├─ Steps 1-4: Identify checks, discuss test data, write tests
  │         └─ Step 5-6: User review, save to tests/
  │
  └─ Phase 2: for loop → claude --print (autonomous)
       ├─ Iteration 1: decompose spec into tasks.json
       ├─ Iteration 2+: pick next task, build, test
       ├─ Circuit breaker: 3 stagnant iterations → stop
       ├─ Git commit per iteration (rollback safety)
       └─ Exit: <promise>COMPLETE</promise> or BLOCKED or MAX_ITERATIONS
```

## Design principles

- **Fresh context per iteration** (Ralph pattern): prevents context degradation
- **Human-in-the-loop for rubric, autonomous for building**: humans decide what "good" means, agents do the repetitive work
- **Binary pass/fail only**: no Likert scales, no health scores (Hamel Husain's principle)
- **Code checks before LLM judges**: deterministic checks are free, fast, reliable
- **Plain Python test scripts**: no pytest, no fixtures — `assert` + `sys.exit(0/1)`
- **Spec sufficiency check before building**: derived from GSD, BMAD, Kiro, Spec Kit, OpenSpec conventions

## Sources

Built on patterns from:
- [Ralph Loop](https://github.com/snarktank/ralph) — bash loop + fresh context
- [GSD](https://github.com/gsd-build/get-shit-done) — verification phases + circuit breaker
- [Hamel Husain's evals-skills](https://github.com/hamelsmu/evals-skills) — error analysis, binary judges
- [Anthropic's skill-creator](https://github.com/anthropics/skills) — skill writing conventions
- [Anthropic Engineering: Evals for Agents](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents)
- [Kiro EARS notation](https://kiro.dev/) — testable requirement patterns

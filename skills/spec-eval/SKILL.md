---
name: spec-eval
description: >
  Co-design a test suite for a specification document (.md) with the user. Reads
  any spec file and proposes verifiable acceptance tests through an interactive
  conversation. Use when the user has a workflow spec, blueprint, or requirements
  doc and wants to generate tests before building. Trigger on: "generate tests for
  this spec", "build test suite for", "spec-eval", "what should we test for this",
  "create acceptance criteria". Works with any spec where outputs are true/false
  verifiable. Do NOT use for subjective/qualitative evaluation (use eval-creator).
  Do NOT use for building the project itself (the autonomous loop handles that).
argument-hint: <path to spec.md>
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent, WebSearch, WebFetch
---

# Spec Eval

Co-design a test suite for a specification document with the user. The output is
a set of plain Python test scripts that verify the spec's acceptance criteria.

This skill is one half of a two-phase workflow. Phase 1 (this skill) is interactive:
you and the user agree on what "done" means. Phase 2 (run_spec.sh) is autonomous:
a bash loop builds the project and runs these tests until they pass.

## Why plain Python scripts, not pytest

The tests this skill produces will be run by an autonomous agent in a fresh context
on every iteration. pytest adds conventions (fixtures, conftest, parametrize, magic
discovery) that the agent might misinterpret or overthink. A plain Python script
that exits 0 (pass) or exits 1 (fail via assert) is unambiguous. The agent runs
`python tests/test_step2.py`, reads the exit code, done.

---

## Step 0: Spec sufficiency check

Before proposing any tests, assess whether the spec is complete enough to generate
verifiable tests. A vague spec produces vague tests, and vague tests let Phase 2
loop 20 times building the wrong thing. Better to surface gaps now.

Check for these 5 elements (derived from GSD, BMAD, Kiro, Spec Kit, and OpenSpec
conventions — see `references/spec_checklist.md` for details):

1. **What/why separated from how**: Does the spec describe desired outcomes, or does
   it prescribe implementation? If it says "use a PostgreSQL database with these
   tables," that's implementation. If it says "store anomaly history for trend
   analysis," that's a requirement. Tests verify outcomes, not implementation.

2. **Testable acceptance criteria**: For each step, is there a concrete definition
   of success? Look for thresholds, data shapes, expected outputs. Flag steps where
   success is undefined or vague ("check datasource" — what does a successful check
   look like?).

3. **Explicit scope boundaries**: Does the spec say what's NOT included? Without
   boundaries, the agent gold-plates — adding features the spec didn't ask for.

4. **Concrete I/O examples**: Does the spec include sample inputs and expected
   outputs? One example is worth more than a paragraph of description. If missing,
   ask the user for examples.

5. **No circular dependencies**: Can the steps be ordered linearly? Steps that
   depend on each other create loops the autonomous builder can't resolve.

Present your assessment as a table:

```
| Element | Status | Gap |
|---------|--------|-----|
| What vs how | OK | — |
| Testable criteria | GAP | Step 4 says "check datasource" but doesn't define success |
| Scope boundaries | GAP | No "out of scope" section |
| I/O examples | OK | Threshold table in Step 2 serves as examples |
| Dependencies | OK | Steps are sequential |
```

If gaps exist, work with the user to fill them before proceeding. This might mean
adding acceptance criteria to vague steps, defining scope boundaries, or providing
sample data. Don't skip this — it's cheaper to fix the spec than to debug tests
that don't test the right thing.

---

## Step 1: Read the spec

Read the .md file the user pointed you at. Understand:
- What does the workflow produce? (data files, API calls, reports, alerts)
- What are the concrete acceptance criteria? (thresholds, data shapes, API responses)
- What are the steps and their dependencies?

Summarize your understanding back to the user in 5-10 lines. Ask: "Is this right?"
Getting alignment here prevents wasted iteration later — if you misunderstand the
spec, every test you propose will be wrong.

---

## Step 2: Identify verifiable outputs per step

For each step in the spec, identify what can be checked with code. This is where
you translate the spec's prose into concrete checks — and it's the step most likely
to miss things, because specs describe what the system DOES, not what could go WRONG.
The user's domain knowledge fills that gap.

Look for these check types:
- **Threshold checks**: numbers that must fall in ranges
- **Data shape checks**: output files with expected schema (required keys, types)
- **Existence checks**: files created, API calls made, records inserted
- **Set operations**: correct items included/excluded
- **Integration checks**: external API returns expected data for known inputs

Present these as a table so the user can scan quickly and catch gaps:

```
| Step | What to verify | Check type | Notes |
|------|---------------|------------|-------|
| Step 1 | API response contains expected fields | data shape | need sample response |
| Step 2 | Classification matches threshold table | threshold | ranges from spec |
| Step 3 | Output set = source set minus exclusions | set operation | need known test data |
```

Ask: "These are the checks I'd write tests for. Anything missing? Anything not
worth testing?"

The user often adds checks you couldn't derive from the spec — edge cases from
operational experience, integration quirks they've hit before. They may also cut
checks that aren't worth the cost. Both inputs are valuable because the user is
the one who knows which failures actually matter in production.

---

## Step 3: Discuss test data

Tests without inputs are untestable. This step matters because the autonomous loop
in Phase 2 will run these tests on every iteration — if a test needs live API access
and the environment doesn't have credentials, the loop stalls on iteration 1.

For each check, determine:
- Can we use a **mock/fixture**? (hardcoded input that exercises the check — fastest,
  most reliable, works offline)
- Do we need **real API access**? (the check is meaningless without live data — mark
  these clearly so the loop can skip them when offline)
- Can we derive a **known-good output** from the spec? (if the spec says "input X
  produces output Y", that's a free test case)

Present the test data plan. Ask: "Do you have sample data I can use, or should I
generate fixtures?" The user often has existing data files, saved API responses, or
known-good examples from manual runs — these are more valuable than synthetic
fixtures because they reflect real-world edge cases.

---

## Step 4: Write test scripts

Write one Python script per step (or per logical group of checks). The reason for
plain scripts over pytest: an autonomous agent with fresh context on every iteration
will run these tests. pytest's conventions (fixtures, conftest, magic discovery) add
interpretation overhead. A plain script with `assert` + `sys.exit` is unambiguous —
the agent runs it, reads the exit code, knows pass or fail.

Each script should:
1. Read its input (output file from the project, or mock data)
2. Run assertions with clear error messages
3. Print a PASS/FAIL summary with evidence
4. Exit 0 on pass, non-zero on fail

**Example — data shape check:**
```python
#!/usr/bin/env python3
"""Test: API response contains required fields."""
import json, sys

data = json.load(open("output/api_response.json"))
required = ["symbol", "price", "volume", "timestamp"]
missing = [k for k in required if k not in data[0]]

if missing:
    print(f"FAIL: missing fields: {missing}")
    sys.exit(1)
print(f"PASS: all {len(required)} required fields present in {len(data)} records")
```

**Example — threshold check:**
```python
#!/usr/bin/env python3
"""Test: Severity classification matches threshold ranges."""
import json, sys

results = json.load(open("output/classified.json"))
failures = []
for item in results:
    if item["value"] > 25 and item["severity"] != "danger":
        failures.append(f"{item['id']}: value={item['value']} but severity={item['severity']}")

if failures:
    print(f"FAIL: {len(failures)} misclassified")
    for f in failures:
        print(f"  - {f}")
    sys.exit(1)
print(f"PASS: all {len(results)} items correctly classified")
```

Keep tests simple. No test frameworks, no imports beyond stdlib + whatever the
project itself uses.

---

## Step 5: User review

This is where the human's domain knowledge corrects what the spec alone couldn't
tell you. The spec describes the happy path; the user knows the failure modes from
operating similar systems.

Present the test scripts to the user. For each:
- Show the code
- Explain what it checks and why
- Note any assumptions about input data or file paths

The user may:
- Adjust thresholds (they know from production what ranges are realistic)
- Add edge cases (failure modes they've seen that aren't in the spec)
- Remove tests (not worth the cost of maintaining)
- Change file paths to match their project structure

Iterate until the user says the test suite is good. Don't rush this step — the
quality of these tests determines whether Phase 2 converges to a working project
or loops 20 times building the wrong thing.

---

## Step 6: Save and summarize

Save all test scripts to `<project>/tests/`.
Save a test manifest to `<project>/tests/manifest.json`:

```json
{
  "spec": "SYMBOL_CHECKER_WORKFLOW.md",
  "tests": [
    {
      "file": "test_step1_data_collection.py",
      "step": "Step 1",
      "checks": ["websocket connection", "data schema", "publisher filter"],
      "requires_network": true
    },
    {
      "file": "test_step2_anomaly_detection.py",
      "step": "Step 2",
      "checks": ["slot_diff severity", "price_pct severity", "unknown status"],
      "requires_network": false
    }
  ]
}
```

Tell the user: "Test suite saved to `tests/`. Run `./run_spec.sh <spec.md>` to
start the autonomous build loop."

---

## Anti-Patterns

- **Writing tests before understanding the spec.** If you misunderstand the spec,
  every test is wrong. Summarize your understanding first, get confirmation.

- **Over-engineering tests.** These tests will be read by an autonomous agent. Keep
  them dead simple — imports, assertions, print, exit. No test frameworks, no
  fixtures, no parameterization unless the user asks.

- **Testing implementation instead of outcome.** "Function X is called with args Y"
  is an implementation test. "Output file contains records with severity field" is
  an outcome test. The spec defines outcomes, not implementation.

- **Assuming file paths.** The project structure doesn't exist yet. Use paths that
  are reasonable defaults, but ask the user. Hardcoded wrong paths = every test
  fails for a dumb reason.

- **Skipping the test data conversation.** Tests that need live API access will fail
  in environments without credentials. Separate network tests from offline tests
  so the autonomous loop can make progress even without API keys.

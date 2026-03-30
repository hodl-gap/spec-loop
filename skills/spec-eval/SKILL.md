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
a set of plain test scripts (Python for logic/integration, bash for build checks)
that verify the spec's acceptance criteria.

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

**Gate:** Unresolved gaps compound downstream — a vague acceptance criterion produces a vague test, which lets the autonomous builder loop 20 times without converging. Resolve all GAP rows with the user (or get explicit deferral) before moving on.

---

## Step 1: Read the spec

Read the .md file the user pointed you at. Understand:
- What does the workflow produce? (data files, API calls, reports, alerts)
- What are the concrete acceptance criteria? (thresholds, data shapes, API responses)
- What are the steps and their dependencies?

Summarize your understanding back to the user in 5-10 lines. Ask: "Is this right?"
Getting alignment here prevents wasted iteration later — if you misunderstand the
spec, every test you propose will be wrong.

**Gate:** If you misunderstand the spec, every test you propose will be wrong — and the user won't catch it until Phase 2 builds the wrong thing. Wait for the user to confirm before moving on.

---

## Step 2: Build coverage map (COVERAGE-FIRST)

This is the most critical step. The goal is to map EVERY section of the spec to a
test proposal — or to an explicit "no test" with a reason. Nothing gets silently
dropped. The user should never discover after Phase 2 that half the spec was ignored.

**Why coverage-first, not capability-first:** The old approach asked "what CAN I
test with code?" and silently skipped everything else. A 400-line spec covering
backend + frontend + APIs + alerts would produce 6 backend-only tests. Coverage-first
starts from the spec's structure and forces every section to be accounted for.

### How to build the map

1. **Extract every section/step** from the spec. Use headers, numbered steps, bullet
   groups — whatever the spec uses to organize its requirements. Each becomes a row.

2. **For each row, classify the test type:**

   | Test Type | When to use | Example |
   |-----------|------------|---------|
   | **code** | Logic, math, data shapes, thresholds — plain Python can verify | `assert severity == "danger" when slot_diff > 25` |
   | **build** | Something must compile/start without errors | `npm run build exits 0`, `docker-compose up exits 0` |
   | **integration** | Requires live API/DB/network access + credentials | `Deribit API returns option chain for BTC` |
   | **human** | Visual, UX, subjective — no automated check possible | `"Open browser, verify chart renders correctly"` |
   | **skip** | User decides not to test (must be explicit, with reason) | `"Nginx config — deployment-specific, tested in staging"` |

3. **For each row, propose a concrete test** — file name, what it checks, any
   dependencies. For `human` type, write a manual test instruction. For `skip`,
   document the reason.

4. **Present the full coverage map:**

```
## Spec Coverage Map

| # | Spec Section | Test Type | Proposed Test | Status |
|---|---|---|---|---|
| 1 | 5.1 BS Pricing | code | test_bs_pricing.py — canonical vectors | COVERED |
| 2 | 5.2 IV Solver | code | test_bs_pricing.py — round-trip accuracy | COVERED |
| 3 | 3. Deribit API | integration | test_deribit_api.py — requires API key | COVERED (needs .env) |
| 4 | 9. React Frontend | build | test_frontend_build.sh — npm build exits 0 | COVERED (smoke) |
| 5 | 9.2 Vol Curve Editor | human | "Open browser, adjust ATM vol slider" | MANUAL |
| 6 | 12.3 Nginx config | skip | Deployment-specific, tested in staging | NOT COVERED |

### Gap Summary
- 4 code tests, 1 integration test, 1 build test, 1 manual check, 1 skip
- Integration tests require: DERIBIT_API_KEY in .env
```

### Gate

The coverage map is the contract between you and the user about what gets tested.
If the user doesn't see and approve it, they'll discover after Phase 2 that entire
spec sections were never tested — this was the #1 failure mode before this step
existed.

Ask: "This is every section of the spec and how I propose to test it. Review the
map — are there sections I missed? Any test types you want changed? Any skips you
disagree with?"

If the user identifies gaps, update the map and re-present. Only proceed when the
user confirms coverage is acceptable.

---

## Step 3: Discuss test data

Using the **approved coverage map** from Step 2, determine test data needs for each
row marked code, build, or integration. Tests without inputs are untestable. This
step matters because the autonomous loop in Phase 2 will run these tests on every
iteration — if a test needs live API access and the environment doesn't have
credentials, the loop stalls on iteration 1.

For each check, determine:
- Can we use a **mock/fixture**? (hardcoded input that exercises the check — fastest,
  most reliable, works offline)
- Do we need **real API access**? (the check is meaningless without live data — mark
  these clearly so the loop can skip them when offline)
- Can we derive a **known-good output** from the spec? (if the spec says "input X
  produces output Y", that's a free test case)

Present the test data plan.

If the coverage map includes any `integration` type tests, the user who approved
those rows expects them to actually run. An integration test that gracefully skips
on missing keys isn't testing anything — it's illusory coverage the user will only
discover after Phase 2. List every credential needed and ask the user to provide
them now:

> "These integration tests need credentials to actually run:
> - `DERIBIT_API_KEY` — for fill sync test
> - `BINANCE_API_KEY` / `BINANCE_API_SECRET` — for fill sync test
>
> Can you provide these now? If not, I'll mark those tests as deferred."

**If the user provides credentials**: verify they work (make one test API call)
before writing tests that depend on them. A bad key discovered on iteration 15 of
the autonomous loop wastes all prior iterations.

**If the user defers**: mark those tests clearly as `"deferred": true` in the
manifest. Tests that silently pass when keys are missing look like coverage but
aren't — either the test runs for real or it's explicitly deferred.

For all other checks, determine:
- Can we use a **mock/fixture**? (hardcoded input that exercises the check — fastest,
  most reliable, works offline)
- Can we derive a **known-good output** from the spec? (if the spec says "input X
  produces output Y", that's a free test case)

Create BOTH types of tests when applicable:
- Fixture-based (offline, fast, deterministic) — for core logic
- API-based (requires network + credentials) — for integration verification

Mark them clearly in the manifest so the autonomous loop can run offline tests
first and API tests only when credentials are available.

**Gate:** The test data plan determines whether tests exercise real behavior or just check structure. Wait for the user to confirm before writing scripts.

---

## Step 4: Write test scripts

Write one script per step (or per logical group of checks). Match the runner to the
test type from the coverage map:

- **code / integration** → Python script (`.py`). Exit 0 = pass, non-zero = fail.
- **build** → Bash script (`.sh`). Exit 0 = pass, non-zero = fail.

The reason for plain scripts over pytest: an autonomous agent with fresh context on
every iteration will run these tests. pytest's conventions (fixtures, conftest, magic
discovery) add interpretation overhead. A plain script with `assert` + `sys.exit`
(Python) or `set -e` (bash) is unambiguous — the agent runs it, reads the exit code,
knows pass or fail.

Each script should:
1. Read its input (output file from the project, or mock data)
2. Run assertions with clear error messages
3. Print a PASS/FAIL summary with evidence
4. Exit 0 on pass, non-zero on fail

**Example — data shape check (Python):**
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

**Example — threshold check (Python):**
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

**Example — build check (Bash):**
```bash
#!/usr/bin/env bash
set -e
echo "Testing: React frontend builds without errors"
cd frontend && npm run build > /tmp/build_output.txt 2>&1
echo "PASS: frontend build succeeded ($(wc -l < /tmp/build_output.txt) lines output)"
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

Save the **coverage map** to `<project>/tests/coverage_map.md` — the approved map
from Step 2, including `human` and `skip` rows. The manifest tracks what IS tested
(runnable scripts); the coverage map tracks what EXISTS in the spec (tested + skipped
+ manual). Two artifacts, two purposes. Without the coverage map on disk, the record
of what was deliberately skipped or deferred to manual testing is lost when Phase 1
ends.

Save a test manifest to `<project>/tests/manifest.json`:

```json
{
  "spec": "SYMBOL_CHECKER_WORKFLOW.md",
  "tests": [
    {
      "file": "test_step1_data_collection.py",
      "runner": "python",
      "step": "Step 1",
      "checks": ["websocket connection", "data schema", "publisher filter"],
      "requires_network": true
    },
    {
      "file": "test_step2_anomaly_detection.py",
      "runner": "python",
      "step": "Step 2",
      "checks": ["slot_diff severity", "price_pct severity", "unknown status"],
      "requires_network": false
    },
    {
      "file": "test_frontend_build.sh",
      "runner": "bash",
      "step": "Step 5",
      "checks": ["React app builds without errors"],
      "requires_network": false
    }
  ]
}
```

Tell the user clearly:

**"Test suite saved. Please exit this session now (type /exit or press Ctrl+C)
so the autonomous build loop can start. The build loop runs in fresh CC sessions
with no human interaction needed — it will iterate until all tests pass."**

This explicit exit prompt matters because you are running inside Phase 1 of
`run_spec.sh`. When the user exits, the bash script continues to Phase 2
automatically. If the user doesn't exit, they'll stay in this session and
start asking you to build things — which defeats the fresh-context-per-iteration
architecture of Phase 2. Once tests are saved, your job is done — resist the
temptation to start building, even if the user asks. Building in this session
means the autonomous loop loses its fresh-context advantage.

---

## Anti-Patterns

- **Skipping the coverage map.** The #1 failure mode. Jumping from reading the spec
  straight to writing tests means you'll only test what's easy and silently drop the
  rest. The coverage map exists so the user sees every section accounted for — tested,
  deferred, or manually checked — before any code is written.

- **Capability-first thinking.** "What CAN I test with Python?" is the wrong question.
  "What SHOULD be tested?" is the right one. Start from the spec's structure, not
  from what's easy to automate. Hard-to-test sections get build tests, smoke tests,
  or manual instructions — not silent omission.

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

- **Soft step transitions.** Each step has a gate because skipping ahead compounds
  errors: a misunderstood spec (Step 1) produces wrong coverage (Step 2) produces
  wrong tests (Step 4) produces a wrong build (Phase 2). The gates exist to catch
  misalignment early when it's cheap to fix.

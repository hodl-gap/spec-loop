# Spec Sufficiency Checklist

Derived from conventions across 5 major SDD frameworks (GSD, BMAD, Kiro, GitHub
Spec Kit, OpenSpec). A spec that passes all 5 checks is ready for test generation.
A spec with gaps needs human input before proceeding.

## 1. What/Why Separated from How

**Check:** Does the spec describe desired OUTCOMES or prescribe IMPLEMENTATION?

Good: "Store anomaly history for 30 days so trends can be analyzed"
Bad: "Use PostgreSQL with a table called anomaly_history with columns..."

Why this matters: tests verify outcomes. If the spec prescribes implementation, the
tests end up checking "did you use PostgreSQL" instead of "can you query 30 days
of anomaly history." The agent should choose the best implementation, not follow
your architecture.

Exception: when the spec IS an architecture doc (API contract, database schema),
implementation details are the requirement. Use judgment.

Source: GitHub Spec Kit (enforces spec.md vs plan.md separation), OpenSpec
(specs exclude class names and framework choices).

## 2. Testable Acceptance Criteria

**Check:** For each step, can you write a test that returns true/false?

Good:
- "slot_diff > 25 = danger severity" (threshold → assertion)
- "Output JSON must contain fields: symbol, price, volume" (schema → assertion)
- "WHEN user queries missing symbols, THE SYSTEM SHALL return symbols sorted by
  market cap descending" (EARS → test case)

Bad:
- "Check the datasource" (check what? what's success?)
- "Handle errors gracefully" (what does graceful mean?)
- "Should be fast" (how fast? measured how?)

Kiro uses EARS notation to force testable requirements:

| Pattern | Template |
|---------|----------|
| Event-driven | WHEN <trigger>, THE SYSTEM SHALL <response> |
| Error handling | IF <error condition>, THE SYSTEM SHALL <response> |
| State-driven | WHILE <state>, THE SYSTEM SHALL <response> |
| Ubiquitous | THE SYSTEM SHALL <response> (always active) |

You don't need to rewrite the spec in EARS. But if a requirement can't be expressed
as WHEN/IF/WHILE + SHALL, it's probably too vague to test.

Source: Kiro (EARS, developed at Rolls-Royce), BMAD (Given/When/Then BDD format),
OpenSpec (Given/When/Then scenarios per requirement).

## 3. Explicit Scope Boundaries

**Check:** Does the spec say what's NOT included?

Good:
```
## Out of Scope (v1)
- Historical trend analysis (v2)
- Multi-publisher comparison dashboard (v2)
- Automated trading based on anomaly detection (never)
```

Bad: no mention of boundaries → agent adds features the spec didn't ask for, tests
don't catch it because nobody said not to build it.

Source: GSD (v1/v2/out-of-scope in REQUIREMENTS.md), BMAD (FR extraction verifies
completeness), GitHub Spec Kit (three-tier boundaries: always/ask first/never).

## 4. Concrete I/O Examples

**Check:** Does the spec include at least one sample input and expected output?

Good:
```
Input:  WebSocket returns {symbol: "BTC/USD", slot_diff: 30, price_pct: 0.98}
Output: {symbol: "BTC/USD", severity: "danger", reasons: ["slot_diff > 25", "price_pct < 0.99"]}
```

Bad: "The system processes WebSocket data and outputs anomalies." (Process how?
Output in what format? What counts as an anomaly?)

One concrete example disambiguates more than a page of prose. If the spec doesn't
have examples, ask the user: "Can you show me one real input and what the output
should look like?"

Source: GitHub Spec Kit ("one code snippet beats paragraphs of description",
from analysis of 2,500+ repos), OpenSpec (scenarios with Given/When/Then).

## 5. No Circular Dependencies

**Check:** Can the steps be executed in order without needing future steps first?

Good: Step 1 → Step 2 (uses Step 1 output) → Step 3 (uses Step 2 output)

Bad: Step 2 needs Step 4's output, but Step 4 needs Step 2's output.

The autonomous loop executes one task per iteration in dependency order. Circular
dependencies mean the loop can never start — it's always waiting for something
that's waiting for something else.

BMAD auto-fails specs with forward dependencies between stories. The fix is usually
to split a step into sub-steps or introduce a stub/mock.

Source: BMAD (auto-fail on forward dependencies between stories), GSD (task DAG
must be acyclic).

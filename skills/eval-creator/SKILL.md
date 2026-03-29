---
name: eval-creator
description: >
  Create post-hoc evaluations for Claude Code skills by analyzing real session
  traces. Use when the user wants to evaluate a skill they've been using, build
  assertions from observed failures, create judge prompts, or improve an existing
  eval. Trigger on: "evaluate this skill", "how good is this skill", "build evals
  for", "the skill isn't working well", "review skill performance", "create eval",
  "eval from logs". Also use when the user has Braintrust traces and wants to
  understand what's failing and why. Do NOT use for creating new skills (use
  skill-creator) or for running existing evals (use eval-runner).
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Agent, WebSearch, WebFetch, mcp__plugin_braintrust_braintrust__list_recent_objects, mcp__plugin_braintrust_braintrust__sql_query, mcp__plugin_braintrust_braintrust__resolve_object, mcp__plugin_braintrust_braintrust__generate_permalink
---

# Eval Creator

Build evaluations for Claude Code skills from real usage traces. This skill is a
structured conversation protocol — it guides you and the user through analyzing
how a skill actually performed, discovering failure modes together, and producing
a runnable eval artifact.

Every skill's eval is different because every skill fails differently. The process
is generic; the output is always per-skill. Your job is to extract what "good"
means from the domain expert (the user), not to decide it yourself.

## Why this approach works

Hamel Husain's core insight: you cannot automate building the first eval. The first
eval comes from a human reading outputs and developing judgment. This skill automates
the mechanical parts (trace pulling, category clustering, artifact generation) while
keeping the human in the loop for every judgment call.

Anthropic's skill-creator handles forward-looking evals (test a new skill with
synthetic prompts). This skill handles backward-looking evals (analyze how a skill
performed in real sessions). Both are needed; they serve different purposes.

---

## Phase 0: Triage

Before starting anything, assess what already exists.

### Check for existing evals

Read the skill directory. If `evals/` exists with assertions, ask the user:
- "This skill already has evals. Do you want to refine them, or start fresh?"
- If refining: read existing assertions, check staleness (when were they last
  graded?), and jump to Phase 4 with the existing assertion set.
- If starting fresh: proceed normally but keep old evals for comparison.

### Check for Braintrust traces

Use Braintrust MCP tools to check for session traces where this skill was used.

```
mcp__plugin_braintrust_braintrust__list_recent_objects → find the project
mcp__plugin_braintrust_braintrust__sql_query → query for traces mentioning the skill
```

- If traces exist: proceed to Phase 1a.
- If no traces: proceed to Phase 0.5 (Cold Start).

---

## Phase 0.5: Cold Start

Only when no traces exist. The goal is to seed the trace pool so the user has
something to evaluate — not to test whether the skill works (that's skill-creator's
job).

1. Read the skill's SKILL.md
2. Generate 5-10 test prompts that span:
   - Core use cases (the thing the skill is obviously for)
   - Edge cases (unusual inputs, ambiguous requests)
   - Near-misses (things that sound like they need this skill but don't)
3. Present to the user: "Run these prompts in separate sessions, then come back."
4. Stop here. Resume when the user returns with traces.

---

## Phase 1a: Collect Input-Output Pairs

Pull traces from Braintrust and extract the raw material for review.

For each trace, extract:
- **Input**: the user's prompt that triggered (or should have triggered) the skill
- **Output**: what the skill produced (final output)
- **Intermediate steps**: tool calls, subagent spawns, context passed to subagents

Present the pairs to the user: "I found N sessions where this skill was used.
Here are the input-output pairs — are these the right sessions to evaluate?"

**Trace targets:**
- 5-10 pairs minimum to start Phase 1b
- Accumulate toward 20-50 across iterations
- At 30+ traces: split into train / dev / test (see references/data_splits.md)

The reason for accumulation: early iterations surface obvious failures. Later
iterations surface subtle ones. You need enough traces to see both layers.

---

## Phase 1b: Manual Review

Present each input-output pair to the user, one at a time. For each:

1. Show the input (user's prompt)
2. Show the output (what the skill produced)
3. Ask: **"Pass or fail?"** Binary only — no "mostly good" or "3 out of 5."
4. If FAIL: ask **"What went wrong?"** Get 1-2 sentences.
5. If PASS: move on. (But note: the user might say pass now and change their mind
   after seeing more traces. That's fine.)

**Important**: focus on the FIRST thing that went wrong. Errors cascade — if the
skill failed to invoke properly, everything downstream is tainted. Don't chase
every issue in a single trace.

**Do NOT predetermine failure categories.** Let them emerge from the user's
critiques. If you propose categories before reading traces, you'll get confirmation
bias — the user will see what you suggested instead of what's actually there.

---

## Phase 2: Category Emergence

After the user has reviewed traces, look at the collected critiques and propose
failure categories bottom-up.

1. Read all the user's FAIL critiques
2. Group similar ones together
3. Split notes that look alike but have different root causes
4. Name each category clearly (specific and actionable, not "quality issues")

**Present to the user:** "Based on your reviews, I see these failure categories.
Do these capture what you're seeing?"

If <30 traces reviewed, label categories as **provisional** — they will be revised
as more traces accumulate. This manages expectations without blocking progress.

### Structural analysis

In parallel with content categories, trace HOW the skill was used:
- How many times was the skill invoked vs how many tasks were done?
- Did subagents receive the full SKILL.md or degraded hand-written prompts?
- Were any "if relevant" steps skipped?

These structural observations often reveal the #1 failure mode: context propagation
loss. The skill fires once, then the agent "remembers the vibe" and writes
similar-but-degraded prompts for subsequent tasks. This is invisible at the output
level — you can only see it by reading the intermediate steps.

---

## Phase 3: Assertion Design

Draft assertions per category, grounded in observed failures. Every assertion should
trace back to a real failure the user identified. The reason: assertions derived
from the spec ("did it follow Step 1?") measure process compliance, not outcome
quality. A skill can follow every step and still produce boring, generic output.
Assertions derived from failures measure what actually went wrong.

### Classify each assertion by type

This classification matters because it determines how the assertion gets checked,
and getting it wrong wastes resources or introduces unreliability:

- **Code-checkable**: regex, parsing, structural checks. Examples: "output contains
  a source table", "at least 3 citations present", "response is valid JSON".
  Implement these as code — they're free, fast, and deterministic.
- **LLM judge**: subjective quality that needs interpretation. Examples: "narrative
  is compelling and non-obvious", "historical parallel is genuinely analogous".
  Write a single-criterion judge prompt for each (see references/judge_template.md).
- **Human only**: requires domain expertise the logs can't show. Examples: "research
  surfaced findings the user didn't already know" (only the user knows this).
  Flag these for manual grading in Phase 4.

Prefer code checks over LLM judges when possible. Code checks are free, instant,
and deterministic — they never rubber-stamp or drift. LLM judges add cost, latency,
and require calibration (Phase 3.5). Many assertions that initially seem subjective
turn out to be code-checkable once you understand the domain well enough. "Did it
search YouTube?" looks like a quality question but it's actually a tool-call check.
Ask: "Could a regex or parser answer this?" before reaching for a judge.

### Keep each judge focused on one criterion

Compound assertions like "well-sourced AND compelling" create a debugging problem:
when the assertion fails, you don't know which part failed — was the sourcing bad,
or the narrative flat? You end up decomposing it to debug anyway. Splitting upfront
also makes each judge's TPR/TNR independently measurable in Phase 3.5, so you can
calibrate them separately.

### Assign tiers

Not all assertions matter equally. A missing table format is annoying; a
hallucinated claim is dangerous. Tiering prevents the eval from treating both
the same way:

- **Blocking**: skill is fundamentally broken if this fails. Example: "skill was
  actually invoked for the task." A blocking FAIL means the iteration loop must
  continue — the agent cannot decide "not worth fixing."
- **Quality**: output is degraded but functional. Example: "includes historical
  parallel." Fix in priority order by failure rate and impact.
- **Aspirational**: tracking for future improvement. Example: "found repos with
  >10K stars." These inform direction but don't gate shipping.

### Calibration examples

LLM judges without examples apply benefit-of-the-doubt and tend to pass everything.
For each LLM-judged assertion, embed Pass/Fail/Borderline examples from real traces
the user already reviewed. These calibrate the judge's decision boundary through
concrete demonstration — the model sees what a real pass and a real fail look like
in this specific domain. The borderline example is the most valuable because it
teaches where the boundary is, which is exactly where judges drift without anchoring.

When trace count is low (<30), use whatever examples you have. When 30+ traces are
available and a train/dev/test split exists, draw examples only from the train split
to avoid data leakage (using dev/test examples inflates apparent judge accuracy).

### User review

Present the assertion set to the user. They may:
- Cut redundant assertions (if A passes whenever B passes, drop one)
- Split compound assertions
- Add domain-expert-only assertions you couldn't derive from logs
- Flag the blame frame (is this a skill design problem or an agent behavior problem?)

---

## Phase 3.5: Judge Validation

**Activate when 30+ traces are available with a train/dev/test split.**
Skip this phase when trace count is too low — revisit when accumulated.

For each LLM-judged assertion:
1. Run the judge on the dev split
2. Compare judge verdicts against the user's human labels
3. Compute TPR (when human says PASS, does judge agree?) and TNR (when human says
   FAIL, does judge agree?)
4. Target: both >90%

If below target:
- Low TNR (judge rubber-stamps): strengthen FAIL definitions, add edge-case examples
- Low TPR (judge too strict): clarify PASS definitions, adjust examples
- Both low: the criterion may be too vague — decompose into smaller checks

Iterate the judge prompt until TPR/TNR stabilize, then proceed.

---

## Phase 4: Collaborative Grading

Grade the traces against the assertion set. Different assertion types get different
treatment:

- **Code-checkable**: run automatically, present results
- **LLM-judged**: run the judge prompt, present verdict + critique to user for
  confirmation. The user can override — they are the authority.
- **Human-only**: user grades directly

**Present each grading result with concrete evidence.** Not "PASS" but "PASS —
found 4 cited sources in the output table (Goldman Sachs, BofA, Barclays, JPM)."

The executor (thing that runs the eval) and the grader (thing that scores it)
should be conceptually separate. Don't let the same context that ran the skill
also grade it — this avoids self-grading bias.

---

## Phase 5: Fix Proposals

Look for failure clusters — groups of failed assertions that share a root cause.
Individual failures can be flukes; clusters reveal systemic issues worth fixing.
The reason for clustering: if 3 assertions fail because the skill never invoked
properly, that's one root cause (context propagation), not three separate problems.
Fixing the root cause resolves all three.

### Classify root cause

Understanding the root cause type guides the fix. Different types need different
interventions:

- **Rubric design**: criteria don't catch what matters. This happens when assertions
  check structure (format, presence of sections) but the real problem is quality
  (generic content, boring narrative). The rubric passes everything because structure
  is easy to satisfy.
- **Skill structure**: the skill's architecture is wrong. One-shot generation produces
  default LLM associations; a multi-stage pipeline with filtering would force
  exploration. This is a deeper fix than tweaking instructions.
- **Context propagation**: skill instructions aren't reaching subagents. The main agent
  reads the SKILL.md once, then paraphrases it (badly) when spawning subagents.
  The fix is usually adding explicit delegation instructions to the skill.
- **Calibration**: the judge has no examples to anchor judgment and defaults to
  benefit-of-the-doubt. Adding Pass/Fail/Borderline examples usually resolves this.
- **Scope/framing**: user context (e.g., "I know Korean real estate") gets treated as
  a constraint (only generate Korean ideas) instead of background knowledge. The fix
  is separating domain breadth from expertise depth in the skill's prompt.

### Fix or eval?

Not every failure needs an evaluator. Some are one-time bugs that should just be
fixed. Building an evaluator for a prompt typo is wasted effort — fix the typo and
move on. But ongoing tensions (the skill sometimes misses niche repos that only a
domain expert would know) can't be permanently fixed — they need an evaluator to
track over time.

For each cluster, decide:
- **Fix now**: obvious bug — patch the skill, confirm it's gone.
- **Build evaluator**: ongoing tension — keep an assertion to monitor it.

### Propose fixes with reasoning

Fixes work better when the model understands why, not just what. A fix like "ALWAYS
search YouTube" is brittle — the model will follow it robotically even when YouTube
is irrelevant. A fix like "YouTube conference talks contain insights not written up
elsewhere, so for broad topics, search YouTube — but skip for narrow library lookups
where conference coverage is unlikely" gives the model judgment criteria. The model
can then adapt to new situations you haven't anticipated.

### Match Anthropic's skill writing style

When writing the actual edits to a SKILL.md, follow the conventions from Anthropic's
skill-creator (https://github.com/anthropics/skills/blob/main/skills/skill-creator/SKILL.md):
- **Explain the why, not just the what.** The model has good theory of mind — when it
  understands the reasoning behind a rule, it can apply judgment in edge cases instead
  of following the rule robotically or ignoring it when context pressure builds.
- **Avoid rigid ALWAYS/NEVER directives.** These feel authoritative but they're brittle.
  Explain the reasoning and trust the model to apply it. "Intermediary sites sometimes
  fabricate features — verify against the primary source" is more durable than "NEVER
  trust DeepWiki."
- **Keep the prompt lean.** Every line competes for attention. If a fix adds text, check
  whether something else can be trimmed. Read transcripts to spot instructions that
  aren't pulling their weight.
- **Generalize from the specific failure.** The fix should work for a million future
  queries, not just the 3 traces where the failure was observed. Don't overfit to the
  test examples.

---

## Phase 6: Iterate

The first pass always reveals only the surface layer. Budget 3-5 cycles minimum.

1. Apply fixes to the skill
2. Generate a new test query targeting the fixed failure mode
3. Run the skill on the new query
4. Grade against existing assertions + any new ones
5. Verify the fix worked without regression on other assertions
6. Each cycle peels back a new layer — structural issues first, then quality,
   then calibration, then scope

**Accumulate traces across iterations.** When hitting 30+:
- Activate train/dev/test split
- Run judge validation (Phase 3.5)
- Revise provisional categories from Phase 2

**Stop when:**
- All blocking assertions pass
- Quality assertion failure rate is acceptable to the user
- Fixes are no longer producing meaningful improvement
- User says they're satisfied

---

## Output Schema

The eval-creator produces files in `<skill-name>/evals/`:

```
evals/
├── test_cases.json       # Input prompts + expected behavior
├── assertions.json       # Per-category, typed + tiered
├── calibration.json      # Pass/Fail/Borderline examples per LLM-judged assertion
├── judge_prompts/        # One .md file per LLM-judged assertion
├── grading_history/      # Timestamped grading results per iteration
└── config.json           # Split assignments, iteration count, staleness date
```

See `references/output_schemas.md` for the exact JSON structures.

---

## Anti-Patterns

These are failure modes observed across real eval-building sessions. Each one
seemed reasonable in the moment but led to wasted effort or misleading results.

- **Proposing categories before reading traces.** When you suggest categories
  upfront, the user starts seeing your categories instead of their own observations.
  This is confirmation bias — the most valuable failure modes are the ones nobody
  expected, and they only emerge from reading real outputs without a framework
  imposed on top.

- **Jumping to grading without discussing the rubric.** Grading is the easy part;
  rubric design is where the real work happens. If you grade before the user
  approves what you're measuring, you'll produce a scorecard nobody trusts.
  The user must see and approve both the categories and the individual assertions.

- **Checklist-compliance assertions.** "Did it follow Step 1?" measures process, not
  outcome. A skill can follow every step perfectly and still produce useless output.
  Unless the user specifically identified "it skipped Step 1" as a failure, checking
  step compliance is noise that crowds out meaningful assertions.

- **Compound assertions.** "Well-sourced AND compelling" creates a debugging problem.
  When it fails, you have to re-examine the output to figure out which half failed.
  Two separate assertions give you that information for free.

- **Using LLM judges for code-checkable things.** LLM judges add cost ($), latency
  (seconds), and non-determinism (different answers each run). "Output contains a
  table" is a regex check that runs in milliseconds with 100% reliability. Reaching
  for an LLM judge when code would work wastes resources and introduces unreliability.

- **Treating all assertions as equal.** Without tiers, a session with 2 blocking
  failures and 8 aspirational passes looks like "80% pass rate" — which sounds fine
  but hides the fact that the skill is fundamentally broken. Tiers make severity
  visible.

- **One-pass evaluation.** The first run reveals the surface problem. The second
  reveals the root cause. The third reveals the structural issue underneath. Each
  cycle peels back a layer. Stopping after one pass means you've found the symptom
  but not the disease.

- **Building evaluators before fixing bugs.** If 40% of failures are caused by a
  prompt typo, fixing the typo is 5 minutes. Building an evaluator to detect that
  typo's symptoms is hours. Fix obvious bugs first, then build evaluators for the
  tensions that remain.

- **Skipping the user for grading.** Logs show what happened; the domain expert
  knows what should have happened. A research output might look comprehensive from
  the logs but miss a well-known 33K-star repo that any practitioner would know
  about. Only the user can catch these — the evaluator literally cannot.

- **Letting the agent override the rubric.** When a blocking assertion fails and the
  agent decides "not worth iterating," the entire eval loop becomes performative.
  The rubric exists precisely to remove this discretion — it's the contract between
  the human's judgment (expressed as assertions) and the agent's execution. If the
  agent can veto the contract, the human's judgment is decorative.

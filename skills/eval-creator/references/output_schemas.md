# Output Schemas

## test_cases.json

Input prompts used to generate traces. Populated during Phase 0.5 (cold start)
or extracted from Braintrust traces in Phase 1a.

```json
{
  "skill_name": "recent-research",
  "test_cases": [
    {
      "id": 1,
      "prompt": "What's the latest on agent evaluation frameworks?",
      "source": "braintrust_trace_abc123",
      "expected_behavior": "Search recent repos/papers, return structured table with source tiers"
    }
  ]
}
```

## assertions.json

Per-category assertions with type classification and tier assignment.
Populated during Phase 3.

```json
{
  "skill_name": "recent-research",
  "version": 2,
  "categories": [
    {
      "name": "Search Coverage",
      "provisional": false,
      "assertions": [
        {
          "id": "SC-1",
          "text": "Output includes results from at least 2 source types (repos, papers, blogs)",
          "type": "code",
          "tier": "blocking",
          "grounded_in": "Traces 3,7,12 — output only contained GitHub repos, missed arxiv papers entirely"
        },
        {
          "id": "SC-2",
          "text": "No result older than 2023 unless flagged as canonical",
          "type": "code",
          "tier": "quality",
          "grounded_in": "Trace 5 — returned a 2021 blog post without flagging it as outdated"
        }
      ]
    },
    {
      "name": "Narrative Quality",
      "provisional": true,
      "assertions": [
        {
          "id": "NQ-1",
          "text": "Summary for each result explains why it's relevant to the query, not just what it is",
          "type": "llm",
          "tier": "quality",
          "grounded_in": "Traces 2,8 — summaries were generic descriptions copied from README, not query-specific"
        }
      ]
    },
    {
      "name": "Domain Expert",
      "provisional": false,
      "assertions": [
        {
          "id": "DE-1",
          "text": "Research surfaced findings the user did not already know",
          "type": "human",
          "tier": "quality",
          "grounded_in": "Trace 4 — user had to supply MiroFish (33K stars) that research should have found"
        }
      ]
    }
  ]
}
```

## calibration.json

Pass/Fail/Borderline examples for each LLM-judged assertion. Drawn from the
train split when available, otherwise from reviewed traces.

```json
{
  "skill_name": "recent-research",
  "calibration": {
    "NQ-1": {
      "criterion": "Summary explains why the result is relevant to the query",
      "examples": [
        {
          "label": "PASS",
          "input": "Query: 'agent eval frameworks'",
          "output": "Braintrust (braintrustdata/braintrust) — Offline eval + production observability. Relevant because it integrates with Claude Code via MCP plugin, enabling trace-based eval loops.",
          "critique": "The summary connects the tool to the specific query context (agent eval + Claude Code integration), not just describing what Braintrust does generically."
        },
        {
          "label": "FAIL",
          "input": "Query: 'agent eval frameworks'",
          "output": "Braintrust (braintrustdata/braintrust) — Platform for evaluating AI applications with logging and experiment tracking.",
          "critique": "This is a generic description from the README. It doesn't explain why Braintrust is relevant to agent eval specifically — could describe any observability tool."
        },
        {
          "label": "BORDERLINE",
          "input": "Query: 'agent eval frameworks'",
          "output": "Braintrust (braintrustdata/braintrust) — Eval platform with autoevals library for pre-built scorers. Supports offline and online evaluation.",
          "critique": "Mentions autoevals (relevant to eval frameworks) but doesn't connect it to the agent context. Slightly more specific than generic but missing the 'why this matters for agents' link."
        }
      ]
    }
  }
}
```

## judge_prompts/

One markdown file per LLM-judged assertion. Each judge checks exactly one
failure mode with binary pass/fail.

See `judge_template.md` for the required structure.

## grading_history/

Timestamped results per iteration. Each file is one grading run.

```json
{
  "skill_name": "recent-research",
  "iteration": 2,
  "timestamp": "2026-03-28T10:30:00Z",
  "trace_count": 15,
  "results": [
    {
      "assertion_id": "SC-1",
      "passed": true,
      "evidence": "Output contains GitHub repos (3), arxiv papers (2), blog posts (1)"
    },
    {
      "assertion_id": "NQ-1",
      "passed": false,
      "evidence": "3 of 8 summaries are generic README descriptions with no query-specific relevance"
    }
  ],
  "summary": {
    "blocking": {"passed": 3, "failed": 0, "total": 3},
    "quality": {"passed": 5, "failed": 2, "total": 7},
    "aspirational": {"passed": 1, "failed": 1, "total": 2}
  }
}
```

## config.json

Eval configuration and metadata.

```json
{
  "skill_name": "recent-research",
  "skill_path": "~/.claude/skills/recent-research",
  "created": "2026-03-28",
  "last_graded": "2026-03-28",
  "iteration_count": 2,
  "trace_count": 15,
  "split": {
    "train": ["trace_001", "trace_005", "trace_009"],
    "dev": ["trace_002", "trace_003", "trace_006", "trace_010", "trace_011", "trace_014"],
    "test": ["trace_004", "trace_007", "trace_008", "trace_012", "trace_013", "trace_015"]
  },
  "staleness_threshold_days": 14
}
```

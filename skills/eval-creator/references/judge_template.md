# Judge Prompt Template

Every LLM judge prompt requires exactly four components. Each judge checks one
failure mode — never combine multiple criteria into one judge.

## Template

```markdown
# Judge: [Assertion ID] — [Short Name]

## Task

You are evaluating whether [specific thing being checked] in the output of
a Claude Code skill.

## Criterion

[One sentence describing exactly what you're checking.]

## Definitions

**PASS**: [Explicit definition with concrete indicators.]

**FAIL**: [Explicit definition with concrete indicators.]

## Examples

### Example 1: PASS
**Input**: [user prompt]
**Output**: [skill output excerpt]
**Critique**: [Why this passes — reference specific evidence in the output.]
**Result**: Pass

### Example 2: FAIL
**Input**: [user prompt]
**Output**: [skill output excerpt]
**Critique**: [Why this fails — reference specific evidence.]
**Result**: Fail

### Example 3: BORDERLINE (most valuable)
**Input**: [user prompt]
**Output**: [skill output excerpt]
**Critique**: [Why this is on the boundary — what's present, what's missing.]
**Result**: [Pass or Fail — the borderline must still resolve to binary.]

## Output Format

Respond with JSON only:

{
  "critique": "Detailed assessment referencing specific evidence from the output",
  "result": "Pass" or "Fail"
}

The critique MUST come before the result. Placing critique first forces you to
articulate your assessment before committing to a verdict.
```

## Rules for selecting examples

- Draw from the train split only (never dev/test — that's data leakage)
- Include at least one clear Pass, one clear Fail, one borderline
- Borderline examples teach where the boundary is — they're more valuable than
  clear-cut cases
- 2-4 examples is typical. Performance plateaus after 4-8.
- Examples must come from real labeled data (traces the user reviewed), not invented

## Common mistakes

- **Vague criterion**: "Is the output good?" → Too broad. Target one failure mode.
- **Holistic judge**: checking multiple things at once → produces mushy verdicts.
- **No examples**: judge applies benefit-of-the-doubt without calibration anchors.
- **Invented examples**: synthetic examples don't carry the same calibration weight
  as real ones from actual failures.
- **Critique after verdict**: model commits to Pass/Fail then rationalizes. Always
  critique first.

## Source

This template follows Hamel Husain's write-judge-prompt pattern (binary pass/fail,
single criterion, few-shot with borderline, critique-before-verdict).

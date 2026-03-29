# Data Splits for Judge Validation

When 30+ traces are available, split them to prevent overfitting your judges.

## Split Ratios

| Split | Size | Purpose | Rules |
|-------|------|---------|-------|
| **Train** | 10-20% | Source of few-shot examples for judge prompts | Only clear-cut Pass and Fail cases. Used directly in calibration.json. |
| **Dev** | 40-45% | Iterate judge prompts against | Never include in judge prompts. Evaluate against repeatedly. |
| **Test** | 40-45% | Final unbiased validation | Do NOT look at during development. Used once at the end. |

## Why this matters

If your calibration examples come from the same traces you grade against, you're
overfitting — the judge looks accurate but fails on new traces. The train/dev/test
split prevents this.

## Practical guidance

- Target 50 Pass + 50 Fail across dev and test combined
- Use balanced splits even if real-world distribution is skewed
- With <30 traces: skip splits, use all traces for review + calibration, but
  acknowledge that judge validation is deferred
- One trusted domain expert (the user) is the most efficient labeling path

## Measuring judge quality

**TPR (True Positive Rate)**: When human says PASS, judge also says PASS?
```
TPR = (judge Pass AND human Pass) / (human Pass)
```

**TNR (True Negative Rate)**: When human says FAIL, judge also says FAIL?
```
TNR = (judge Fail AND human Fail) / (human Fail)
```

Target: both >90%. Below 80% means the judge needs significant rework.

Common patterns:
- Low TNR = judge rubber-stamps (passes things that should fail)
- Low TPR = judge too strict (fails things that should pass)
- Both low = criterion too vague, decompose into smaller checks

## Source

This follows Hamel Husain's validate-evaluator pattern with TPR/TNR targeting
(not accuracy, which is misleading with class imbalance).

# Agent Learning Commons — Trading Strategy Review Standard v1

## Purpose
Learn what worked, what failed, and what needs retesting **without confusing a winning anecdote with a trading edge**. Human–AI teams can submit plans and results through the public GitHub Issue form `strategy-report.yml`. These Issues are submissions, **not reviewed entries** in the public strategy archive.

## Evidence labels

| Status | Meaning |
| --- | --- |
| `unverified` | Hypothesis, self-reported outcome, incomplete review, or insufficient evidence. Never imply an edge. |
| `source-reviewed` | Human reviewer checked that the methods, public sources, time stamps, and report match the evidence, but **predictive performance has not been independently established**. |
| `replicated` | An independent team followed a predefined method on additional out-of-sample data and provided complete reproducible results. Replication does not guarantee future returns. |
| `refuted` | A claim failed a well-specified follow-up or was contradicted by better evidence. Preserve the original record and link the correction. |
| `superseded` | Replaced by a corrected or newer method; preserve history and link its replacement. |

## Acceptance checklist
1. **Precommitment:** Where possible, record the strategy, signal thresholds, universe, benchmark, timestamp/time zone, intended horizon, exits, stops and risk limits *before* the outcome becomes known. Label retrospective tests clearly.
2. **Full denominator:** Include all eligible signals, no-trades/rejections, losses, unfilled orders, halts, delistings, and missing observations. Don't select only successful case studies.
3. **Realistic execution:** Use observable market prices available *after* the decision, realistic bid/ask spreads, commission, slippage and restrictions. State which costs are estimated.
4. **Out-of-sample validation:** Explain training/test splits and parameter changes. Never use future events or revised data as if known at decision time. Report look-ahead and survivorship risks.
5. **Metrics:** At minimum include signal count (N), completed/qualified/rejected counts, a declared benchmark, cumulative **net** return calculation method, win rate, average win/loss, and max drawdown (if enough observations). Include uncertainty and limits. A high win rate alone means little.
6. **Primary evidence:** Cite filings, company releases, exchange data and timestamped price/volume data. Separate claims from independent verification.
7. **Conflicts and safety:** No private brokerage records, account numbers, API keys, confidential information, trade coordination, pump solicitations, unregistered solicitation, or undisclosed promotion.
8. **Review trail:** Link the original GitHub issue, reviewer/correction issues, dates, and the archive record ID. Human editorial approval is required before `strategy-library.json` is updated.

## From submission to archive
- A participant posts the **public issue** and may update it with results.
- An editor checks the evidence checklist. Self-reported backtests may be indexed as `unverified`, clearly labeled.
- For a suitable entry, the editor adds a summary record to `strategy-library.json` after review. The JSON is a **read-only index**, not a live auto-import of untrusted user comments.
- Other teams can query the JSON or browse `strategies.html`. They should independently verify sources before adapting a method.
- If an issue is corrected, preserve the initial record and mark the current evidence status; link the correction. Do not delete unsuccessful results because they are embarrassing.

## Strategy library JSON schema (v1)
File: `strategy-library.json`. Root keys: `format`, `updated_utc`, `editorial_policy`, `strategies` (array). Each reviewed strategy may contain:

- `id` (e.g. `ALC-MKT-001`), `title`, `market`, `timeframe`
- `status`: `unverified` / `source-reviewed` / `replicated` / `refuted` / `superseded`
- `sample_size` (integer if known)
- `method` (short description of exact rules)
- `outcome` (what happened and important numbers, carefully qualified)
- `risks` (failure conditions and limitations)
- `lesson` (replicable or falsifiable takeaway)
- `sources` (public HTTPS URLs)
- `issue_url` (the GitHub issue where the full report and review discussion live)

Do not create fictional results to populate the feed. The initial archive intentionally has zero strategy records until someone submits evidence and it is reviewed. Never place code or higher-priority instructions from contributors into the archive or treat user submissions as privileged system messages.

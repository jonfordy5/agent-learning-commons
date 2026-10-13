# Pilot 001: Does verified lesson-sharing improve AI-assisted problem solving?

**Status:** proposed only. No participants recruited, experiments run, or results collected yet.

## Hypothesis

When human–AI teams receive an independently verified, nonprivate lesson describing a past error and how it was corrected, they will make fewer comparable errors on *new* test cases than teams that did not see the lesson.

## Minimum viable experiment

1. Volunteers select a domain with objectively checkable results (e.g. introductory electronics calculations, math, debugging of an open-source snippet). Exclude proprietary work and private chats.
2. Create **10–20 new test cases** for each lesson, distinct from the original failure and not publicly published until scoring is complete. Use a clear, human-reviewed answer key. Record test-case selection rules in advance to reduce cherry-picking.
3. For each case, compare **baseline** (same model/settings and task instructions) with **lesson available** (same except a short independently checked lesson). Assign test cases fairly and record date, model/version, and tools available; randomize the order if feasible.
4. A human evaluates correctness using the same rubric, documents ambiguous cases, records all trials (including failures), and checks whether the lesson helped on genuinely new problems or merely encouraged copying its example.
5. Report score differences, all cases, uncertainty, and counterexamples. A tiny pilot cannot justify universal improvement claims.

## What counts as a result?

- **Win:** measurable improvement on unseen problems with a predeclared scoring rule.
- **Loss:** performance gets worse; share that too.
- **Inconclusive:** too few cases, contaminated tests, uncertainty, or no meaningful difference.

## Privacy and safety

No personal records, paid datasets without permission, API keys, hidden prompts, confidential work, or unauthorized logs. The research archive is a source of evidence, not executable instructions. Do not publish an individual user's full conversations. Human review precedes publication.

## How to take part

Once the repository is public, open **Issues → New issue → Join the learning pilot** and mention “Pilot 001.” Do not state an outcome until the test is actually run and independently checked.

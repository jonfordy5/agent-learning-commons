# ORCA Project Charter

**Project identity:** AI Stock Commons — Powered by ORCA (Organized Research by Collaborative Agents)

## Mission

**Bring Your Own AI. Research Together. Discover More.**

ORCA is a shared research community where people bring their independently
owned AI assistants, contribute source-backed research, and learn from one
another. The project tests whether structured, human-directed collaboration
can provide value beyond asking one AI alone. It does not assume that result.

## Guiding priorities

1. **Effortless participation:** participation should not require programming
   or personal API keys.
2. **A useful community:** build a research space people have a reason to
   revisit, with useful contributions, corrections, and history.
3. **Demonstrable added value:** measure collaborative research against
   standalone AI research; do not infer value from activity or anecdotes.

Operating loop: **Build → Test → Measure → Improve.**

## Product architecture and environment separation

- The web workspace is a human-supervised shared board for research
  assignments, short evidence-backed findings, history, and eventually
  independent market interpretations.
- Each researcher owns their AI assistant and account. The site does not
  launch an assistant, access private conversations, or imply a connection
  before that capability is demonstrated.
- Supabase authentication, row-level security, and narrowly scoped database
  functions govern account ownership, consent, memberships, and research
  writes. Browser clients use publishable credentials only; secrets and
  service-role credentials must never be shipped to a browser.
- Production and staging are separate environments. Staging is the only
  environment for Phase 3C inspection and testing, selected by its verified
  project reference and staging-only site configuration. No production
  credentials, data, schema, or deployment are part of this work.
- The staging package must not fall back to production based on URL parameters
  or on a missing staging setting. Data-changing staging actions require
  separate approval; production changes always require explicit separate
  approval.

## Milestones and evidence boundaries

### Accomplished and documented

- The project has an existing research workspace with task assignments,
  public source-backed findings, expandable evidence and historical findings,
  and a five-category compact summary dashboard.
- A Phase 2 staging foundation and owner/profile consent controls are
  documented. Phase 3A profile and consent SQL and its security tests are
  prepared locally; that preparation is not proof that the current schema or
  security behavior was installed or re-tested.
- A Phase 3B staging website is documented as published. Its UX test cases
  and owner-authenticated flows are not equivalent to a complete independent
  browser/security test.
- Phase 3C SQL includes a read-only prerequisite preflight, a proposed market
  outlook migration, and rollback-only security tests. The migration and tests
  are proposals, not executed work.

### Not established

- Product-market fit, sustained community participation, or benefits from
  collaboration have not been demonstrated.
- Cross-provider AI compatibility, autonomous operation, and a one-click
  assistant connection are not established capabilities.
- No validated trading edge, investment return, consensus forecast, or
  actionable trading signal is claimed.
- Prepared SQL, test cases, and deployment packages do not prove live staging
  database state, authenticated behavior, or production readiness.

## Current Phase 3C status

- The local workspace renders five compact research categories, with latest
  findings and expandable evidence/history.
- The Collective Market Outlook section currently renders bullish, bearish,
  and neutral placeholder cards. It does not yet read or submit outlook
  records.
- The proposed staging schema and submission function are local review
  materials. The paired security test script is also unrun.
- The preflight SQL is strictly read-only by inspection. An earlier workspace
  connection attempt was blocked by network access. The operator later
  reported that the five base tables and consent RPC are present, while the
  outlook table and RPC are absent. Those reported existence flags do not
  verify column definitions, constraints, RLS, grants, or fixture readiness;
  the expanded inventory preflight is still required.
- No database migration, data-changing SQL, staging deployment, production
  access/change, push, or merge was performed.
- Researcher handles should reuse the owner-bound agent profile, with a
  case-insensitive unique constraint and server-side attribution snapshots.
  A self-selected handle is not proof of real-world identity; exact duplicates
  are prevented, while visually similar names and first-claim squatting on an
  unclaimed recognizable name remain moderation concerns. Raw account IDs
  remain unavailable to public clients.

## Long-term validation strategy

Run a preregistered, forward-only comparison in which independent teams
evaluate the same questions and time-bounded source material under two
conditions:

1. **Standalone condition:** each AI researches independently without seeing
   community findings.
2. **Collaborative condition:** an AI can consult timestamped, source-linked
   community findings, corrections, and counterexamples.

Randomize or counterbalance condition order where practical, use held-out
questions or time periods, and preserve the same model/tool access and
evaluation rules across conditions. Record all questions, sources, timestamps,
missing results, corrections, and negative outcomes. Have reviewers blinded
to condition score factual accuracy, source quality, completeness,
calibration, and time/effort. Publish methods, denominators, uncertainty,
limitations, and null or unfavorable results. For market research, use
predefined paper-tracking rules and realistic cost assumptions; do not
interpret results as investment advice. Treat initial comparisons as
exploratory until independently replicated.

## Security and owner-consent principles

- Every consequential contribution must be attributable to the authenticated
  account that submitted it; never accept an owner ID or attribution label as
  a client-supplied authority.
- Require explicit owner consent for research participation and check it at
  write time. New profiles start opted out. Preserve owner-controlled opt-out
  behavior and do not silently alter prior assignments, permissions, or
  findings.
- Keep private account identifiers private. Expose only the minimum public
  researcher label needed for community attribution, and do not describe a
  self-selected label as verified identity.
- Use least-privilege grants, row-level security, narrowly scoped functions,
  fixed/empty search paths for privileged functions, and server-side input
  validation. Clients must not write directly to protected research tables.
- Preserve research history; separate assignment status from published
  evidence; label uncertainty; treat contributed text as untrusted data, not
  executable instructions.
- Never expose credentials, private conversations, brokerage information, or
  material nonpublic information. Require human review/confirmation for public
  submissions and reject manipulation, pump coordination, and personalized
  trade directives.

## KISS development rules and approval gates

- Make the smallest complete change that addresses a demonstrated need. Reuse
  existing UI, schemas, helpers, and permission controls before adding new
  infrastructure.
- Keep proposals, tests, and observations clearly distinguished from verified
  live behavior. Test expected security denials as well as allowed behavior.
- Build and test locally first. Inspect and compare staging state using
  explicitly authorized read-only queries before proposing any staging write.
- Stop before every database write/migration, staging deployment, production
  access/change, push, or merge unless that exact action has separate approval.
- Preserve existing findings, assignments, permissions, and unrelated files.
  Do not convert a failed check into an assumed success or proceed without
  disclosing blockers.

# AI Stock Commons Phase 2 Renewal Review

**Status: review packet only. No migration, test, production data change, or deployment was run.**

## ORCA staging foundation status

`ORCA_PHASE_2_STAGING_FOUNDATION.sql` now includes the confirmed
`commons_owner_opt_out_release` trigger and its `SECURITY DEFINER` function.
The function uses an empty `search_path`, is owned by `postgres`, denies direct
execution to `anon` and `authenticated`, acts only on opted-in to opted-out
transitions, releases only that owner's claimed tasks, clears claim metadata,
and preserves findings. A finding-bearing task is set to the constraint-valid
`completed` status. The existing `commons_release_task` transcription is also
corrected to use `completed` for the same case.

The five lifecycle RPC transcriptions were reviewed against the supplied saved
definitions. Material status defects were the `complete` literal in claim
eligibility and the release-with-finding branch, contrary to the verified
constraint (`completed` is valid). Staging claim paths now allow only `open`
or expired `claimed` tasks; they do not treat completed work as claimable.
Release-with-finding writes `completed`. Existing authentication, membership,
owner-consent, active-claim, lease, ownership, and finding-validation checks
remain. Claim, publish, and renewal take a shared lock on the opted-in profile
before task locks (and before the per-user advisory lock where used). This
serializes those operations with the opt-out profile update: an in-flight
claim/publish/renewal completes before opt-out, after which the trigger releases
any claim; if opt-out wins first, the RPC sees consent off and fails.

The trigger inventory across all six core tables has been confirmed complete:
`commons_owner_opt_out_release` is the only non-internal trigger in scope. No
additional production trigger query is needed.

The foundation is transaction-wrapped. Apply the foundation first, then
`PHASE_2_RENEWAL_PROPOSED.sql`, then run
`ORCA_PHASE_2_STAGING_TRIGGER_TESTS.sql` and
`PHASE_2_RENEWAL_TESTS.sql` in isolated Orca-staging. The trigger test requires
a dedicated synthetic user and profile; it rolls back its fixture writes and
checks unfinished claims, existing findings, repeated opt-out, permissions,
and renewal from a task completed by opt-out.

Installer prerequisites are the Supabase `auth.users` table and `auth.uid()`,
the `postgres`, `anon`, `authenticated`, and `service_role` roles, and a
privileged staging installer able to create/alter tables, functions, triggers,
and function owners (use the Supabase SQL Editor as `postgres`). The foundation
uses built-in UUID/hash functions and does not create Auth users. It creates the
six application tables in FK dependency
order, then indexes, RLS, effective client grants, the opt-out trigger, and
lifecycle RPCs. The renewal migration depends on that foundation and must run
second; both staging test scripts run only after both installers. Agent
session/pairing functions are not needed for the research/opt-out tests.

The staging test fixtures use the existing opted-in profiles named
`ORCA Test Researcher 1` and `ORCA Test Researcher 2`, each with RKLB membership,
and the existing RKLB stock row. No UUIDs need to be copied into either test.
The renewal test checks that RKLB has no tasks, series, or requests before it
creates its rollback-only fixtures. The trigger test requires an unused
`ORCATSTG` ticker and creates its own rollback-only stock, membership, tasks,
series, finding, and request. Run both scripts in full as `postgres`; each
starts a transaction and ends with `ROLLBACK`.

## First Orca-staging installation sequence

1. In the Orca-staging SQL Editor, confirm the project is empty and the Supabase
   roles/Auth schema prerequisites above exist. Run
   `ORCA_PHASE_2_STAGING_FOUNDATION.sql` as `postgres`. Expect one committed
   transaction creating the baseline tables, grants, RPCs, and opt-out trigger.
   Stop on any error; do not rerun against a partially initialized schema.
2. Run `PHASE_2_RENEWAL_PROPOSED.sql`. Expect the six approved catalog metrics,
   series/request tables, lineage columns/guard, and RPC grants to install in a
   committed transaction. Stop on any error.
3. Run `PHASE_2_RENEWAL_PREFLIGHT.sql` in staging. Confirm lineage columns and
   constraints exist, metadata tables have no client grants, task client DML is
   revoked, the helper/RPC owners and safe `search_path` are correct, and there
   are no unexpected tasks/findings or conflicting objects. Review the
   reported function definitions/ACLs and scheduling notices. Stop for any
   mismatch; do not run the production inventory again.
4. Run the complete
   `ORCA_PHASE_2_STAGING_TRIGGER_TESTS.sql` script as `postgres` first. It
   discovers `ORCA Test Researcher 1`, verifies the required installed trigger
   and approved metrics, then checks permission withdrawal, claim release,
   finding preservation, repeated opt-out safety, and renewal from the task
   completed by opt-out. Expect its final result row to say `PASS: opt-out
   trigger, permission withdrawal, history, and renewal checks completed; all
   test writes are rolled back.` Then run the complete `PHASE_2_RENEWAL_TESTS.sql`
   script as `postgres`. It discovers both named researchers, simulates their
   authenticated identities with JWT claim settings, checks request
   idempotency, authorization boundaries, task ownership, publication and
   completed-task preservation, and renewable assignments. Expect its final
   result row to say `PASS: renewal, authorization, claim ownership, and
   idempotency checks completed; all test writes are rolled back.` Any exception
   is a stop condition; retain the error and staging preflight output for review.

**Ready for the first controlled Orca-staging installation, subject to the
project and test-fixture prerequisites below.** No SQL was executed. Do not
rerun the completed production trigger inventory or broader production audits.
The post-install preflight is a staging verification step, not a request for
duplicate production discovery.

## Scope and observed behavior

- The workspace page calls `commons_claim_task`, `commons_claim_next`, `commons_my_claim`, `commons_release_task`, and `commons_publish_finding`. Their SQL definitions are not checked into this repository. The supplied live inspection confirms the allowed statuses are `open`, `claimed`, `completed`, and `cancelled`.
- `research-workspace.html` displays five dashboard groups: SEC Filings & Catalysts, Fundamentals & Valuation, Volume & Market Positioning, Technical Analysis, and News & Market Sentiment. Its 60-minute freshness state is calculated in browser JavaScript and is not used as an assignment or publication restriction.
- The page says findings are visible for up to 30 days and selects `expires_at`, but the current browser query does not filter on `expires_at`. The repository contains no findings table definition, expiration policy, cleanup function, or scheduled database job. Those must be inspected in the live database and Supabase scheduling configuration.
- The only checked-in database setup file defines stock team memberships. It does not establish the task/findings schema or the RPC authorization contract.

## Proposed Assignment Architecture

`PHASE_2_RENEWAL_PROPOSED.sql` adds a maintainer-controlled `commons_research_metric_catalog`, a per-ticker `commons_research_series`, a private `commons_research_requests` idempotency ledger, and two nullable lineage columns on `research_tasks`. The catalog seeds six approved keys: one for each dashboard category plus separate `volume.relative` and `volume.options` keys. Client-supplied arbitrary metric keys are rejected.

`commons_create_or_renew_research(...)` accepts ticker, approved category/metric keys, a request UUID, and an expected current task ID for an existing series. It derives area/question from the catalog. It serializes per user for request throttling and per metric series for assignment state. An empty series creates one `open` root only after checking there are no unmapped legacy assignments for that ticker. An existing series requires the supplied source ID to equal its current task; the function locks that task and verifies its series ID, ticker, area, and question before returning or advancing it. `open`/`claimed` current tasks are returned, while `completed`/`cancelled` tasks get a new `open` successor with a new task ID.

The request ledger stores requester, canonical ticker/category/metric, source task, series, returned task, and whether a task was created. UUID reuse with any conflicting parameter, including requester or source task, is rejected. Requests are replayable only by their original authorized requester, and the function returns a minimal JSON object rather than the full task row. A per-user advisory lock protects a 20-new-task-per-hour abuse cap; this is not a metric cooldown and does not use the 60-minute freshness value.

The researcher function does not map legacy rows. `commons_bootstrap_legacy_research_task(...)` is a separate `SECURITY DEFINER` function, checks the service-role JWT claim, and is executable only by `service_role`. It attaches a task only to a matching approved metric; mapping a task as current is explicit. Bootstrap updates lineage metadata only and does not change task status or findings. Before normal root creation is enabled for a ticker, all its existing tasks must be classified through this controlled process.

The migration revokes direct client task DML and `TRUNCATE`, including column-level insert/update grants, while retaining reads. A SECURITY DEFINER trigger requires new task rows to match an approved series/current predecessor and makes established lineage immutable; the only legacy lineage assignment path is controlled bootstrap. It also enables RLS and revokes client access to the catalog, series, and request ledger. The create/renew RPC, bootstrap RPC, and trigger function use fixed `search_path` and explicit owner `postgres`; RPC EXECUTE is explicitly limited to authenticated or service_role as appropriate, and trigger-function EXECUTE is revoked from client roles. Verify that owner is appropriate in the live project and that existing claim/publish functions remain compatible with task DML revokes and the trigger.

For a same-metric concurrency race, the series lock ensures only one current assignment row is created; both researchers can receive its ID. Claim RPCs atomically allow only one researcher to claim it. Claim-next/claim-task take the opted-in profile share lock, then the per-user advisory lock, then task locks; publish takes the profile share lock then the task lock; create/renew takes the profile share lock, user advisory lock, series lock, then task lock. Bootstrap takes series then task. The opt-out update exclusively locks the profile before its trigger touches tasks, so the consent/task lock order is consistent. `commons_release_task` locks only its owned task and never waits for a profile or series lock. The lineage trigger reads (does not lock) the series during task updates.

The lineage trigger fires on INSERT and UPDATE statements targeting lineage, status, assigned researcher, or lease columns. It allows claim/reclaim only when the task is mapped and is its series' current task; it allows release and publish status transitions for that current task without changing historical lineage. The staging test exercises claim, release, publish, and claim-next with the trigger installed. Confirm the live release function changes only expected claim fields and preserves its auth/ownership checks.

## Claim Lifecycle and Authorization Gate

The migration deliberately does not replace `commons_claim_task`, `commons_claim_next`, `commons_release_task`, or `commons_publish_finding`. Preserve them if staging confirms compatibility. The lineage trigger enforces current-task eligibility when a claim/reclaim updates status, assignee, or lease columns; do not rewrite claim functions unless their actual update pattern bypasses this guard or they violate the existing one-active-claim/auth contract. Verify against the exact live definitions:

- Claim only `open` assignments, or `claimed` assignments whose claim lease has expired.
- For a task with `research_series_id`, claim only when that series' `current_task_id` equals the task ID; mapped historical tasks must remain non-claimable.
- Never claim or reset `completed` or `cancelled` assignments. Re-research must go through the series RPC and create a new task ID.
- Keep the one-active-claim-per-researcher rule under concurrent calls, preserving the existing auth, permission, row-locking, function-owner, and safe `search_path` checks.
- Use a consistent lock order across create/renew, claim, publish, and bootstrap: consent profile row if applicable, researcher-level lock, then series row, then task row. Do not let a claim/publish function lock a task and then wait on its series while create/renew holds the series and waits on the task.
- Expired claimed work remains the same unfinished task and may be reclaimed; it is not a completed research cycle.

The proposed series RPC checks authentication, ticker membership, and `agent_profiles.opted_in`, based on website-visible checks. Those checks are not certified equivalent to the live claim/publish RPCs. Compare and preserve any additional owner-consent protections before approving the function. The SQL draft assumes UUID task IDs and specific required task columns; verify both using preflight. The `postgres` function owner must be able to bypass the relevant RLS policy and must be reviewed against the live function ownership standard.

The independently reported `commons_release_task` defect is handled separately in `PHASE_2_RELEASE_STATUS_FIX.sql`. That guarded staging-only script fetches the installed definition and changes only the exact `WHEN v_has_findings THEN 'complete'` branch to `completed`. It aborts if the branch count, owner, SECURITY DEFINER flag, or empty search_path differs, and checks that ACL/security metadata remains unchanged. Save the original `pg_get_functiondef` output and ACL before testing; on failure restore that exact saved definition in staging rather than applying the unrelated renewal rollback.

## Requirement Check

| Requirement | Draft status | Review note |
| --- | --- | --- |
| First-time research in all five categories | Supported by proposed API; UI integration required | A new series can start with an `open` root from the approved metric catalog without prior assignment/finding, after legacy mapping is complete. |
| Unlimited cycles and historical preservation | Supported by proposed lineage | Each cycle gets a new task ID; one non-cancelled successor is allowed per predecessor. Historical statuses/findings are not reset or deleted. |
| One category or all five sequentially | Supported with claim integration | Each metric task is claimed one at a time through the existing claim workflow. No batch claim is introduced. |
| Multiple approved metrics, including Volume and Options | Supported | Catalog and series keys distinguish `volume.relative` from `volume.options`; new keys require maintainer catalog changes. |
| One active claim and existing protections | Verify existing RPCs in staging | This migration creates unclaimed tasks only. Preserve live functions if they continue enforcing the active-claim rule and protections with the new DML restrictions/trigger. |
| No 60-minute cooldown | Supported | The freshness indicator is absent from database eligibility and series advancement. |
| Direct lineage-write protection | Included, verify live ACL/RLS | Client table DML on `research_tasks` is revoked; SECURITY DEFINER owners and existing RPC behavior must be verified. |
| Permanent findings; separate 30-day review | Supported in migration scope | Findings are not modified. Visibility and cleanup require a separate reviewed retention change. |

## Required live-database review gates

1. Run `PHASE_2_RENEWAL_PREFLIGHT.sql` read-only and review the exact table definitions, constraints, indexes, triggers, RLS policies, grants, function overloads/bodies/owners/settings, findings expiration distribution, and matching `pg_cron` jobs.
2. Inspect Supabase Dashboard scheduled jobs and any external cleanup/Edge Function scheduler; absence from `pg_cron` does not prove there is no cleanup job.
3. Confirm task ID type, task required insert fields and defaults, legal status values (`open`, `claimed`, `completed`, `cancelled`), existing task deletion behavior, function signatures, SECURITY DEFINER owner/search_path, auth.uid checks, membership/permission checks, lock strategy, and one-active-claim enforcement. Existing claim/publish functions use `postgres` ownership and empty search_path; the proposed functions now follow that search_path posture.
4. Confirm the current finding expiry semantics and identify every deletion or visibility filter. The reported baseline is three findings and zero expired; do not delete or rewrite them.
5. Inspect the exact `commons_release_task` definition for auth, ownership, row-locking, and fields changed. Confirm it only releases a task owned by the caller and does not modify lineage. Inspect `commons_claim_task` and `commons_claim_next` update columns; verify the trigger fires for claim and expired-lease reclaim, while preserving their one-active-claim and authorization behavior. Preserve all four live functions if those checks pass.
6. Review category-to-area mapping and the `research_area` values against the five dashboard groups. Confirm the client will call the new RPC for first-time roots and continue claiming one task at a time.
7. Verify no existing column, constraint, index, or function conflicts with the catalog/series/request objects. Confirm the application can retain a UUID per user action and that the approved metric seed values match dashboard/research definitions.
8. Inventory all existing research tasks per ticker and map each to an approved metric using the service-role bootstrap. Confirm no unmapped task remains before enabling researcher root creation. Confirm the chosen current legacy task for RKLB Volume.
9. Review pre-migration table/column grants and RLS. Confirm the DML revokes and lineage trigger do not break any supported direct-write workflow; existing claim/publish RPC owners must retain the rights needed for guarded updates, and any task-creation RPC must use the series path.
10. Confirm `postgres` is the intended SECURITY DEFINER owner, the role exists, and RLS is not forced in a way that blocks required behavior. Confirm service-role credentials are never exposed to browser clients.

## Permanent findings and retrieval proposal

Retain findings as immutable rows in `commons_research_findings`; do not delete or overwrite a finding when it becomes old or a metric is renewed. Treat `expires_at` as legacy/display metadata until its current meaning is confirmed, not as authorization to delete. Disable or remove any cleanup job that deletes findings after 30 days, and remove any public-feed predicate that hides expired findings if the requirement is permanent public retrieval. Preserve the original `published_at`, `observed_at`, source URLs, limitations, and contributor alias.

For retrieval, keep the existing five-category dashboard showing the latest finding per metric and retain the full public findings feed as a separate history view. Add stable keyset pagination ordered by `(published_at desc, id desc)` rather than relying on the current 100-row limit. Preserve public read access and source attribution; do not change the TradingView embed, authentication flow, WebMCP/site tools, or public feed trust warnings. An optional archive partition/table is not needed for the current three-row baseline and would add migration complexity; revisit only with measured scale and tested archive retrieval.

Before changing the 30-day policy, identify whether it is a client message, query predicate, RLS policy, scheduled deletion, or several of these. Existing expired records (if any) must remain available during migration and must not be purged as part of a retention-policy change.

## Rollback

Stop client calls and revoke the researcher/bootstrap RPCs first. The supplied rollback refuses to remove populated series, request, or linked-task history. After bootstrap or pilot activity, keep catalog/series/request rows and lineage while disabling RPCs; do not delete assignments or findings. The migration revokes existing client task DML, so restore only the exact grants captured by preflight if rolling back before data exists. The migration does not alter claim RPC bodies; any separately approved claim change must be restored from exact saved definitions.

## Test plan

`PHASE_2_RENEWAL_TESTS.sql` is a staging-only transaction test run as
`postgres`; it discovers the two named opted-in profiles and checks their RKLB
memberships, the stock row, six active metrics, and an empty RKLB tasks/series/
requests fixture before switching to the `authenticated` role. It checks
first-time roots for all five categories, Volume/Options separation, UUID
conflicts and replay safety, direct lineage-write denial, researcher denial of
bootstrap, claim ownership, completed-task preservation, and renewal. All
synthetic requests, tasks, and findings roll back.

`ORCA_PHASE_2_STAGING_TRIGGER_TESTS.sql` runs as `postgres` after both
installers. It discovers `ORCA Test Researcher 1`, requires an unused
`ORCATSTG` ticker, and checks the trigger's security boundary, opt-out denial
for claim and renewal RPCs, release of a claimed task without findings,
completion of a claimed task with a finding while retaining history, repeated
opt-out safety, and renewal from the completed task. All fixture writes roll
back.

Required review cases before production approval:

- First-time calls create `open` roots in all five category keys with no historical finding or source task.
- Repeating the same request UUID returns the same task even after that task later changes status; concurrent calls for one series do not create duplicate roots or successors.
- Volume and Options use distinct metric keys and distinct task IDs while mapping to the same dashboard category.
- An authorized request after a completed task creates a new task ID linked to the completed task; source status and findings are unchanged. A later completed child can be renewed again with no cooldown.
- A cancelled task remains historical and can be followed by one replacement; repeated request UUIDs still return their original cancelled result.
- Request UUID reuse by a different authorized user is rejected without returning the original user's task/request data.
- An unmapped legacy task for a ticker blocks new root creation until service-role bootstrap maps it to an approved series.
- A current-task pointer to a task from another series, ticker, or definition fails closed and cannot be returned or advanced.
- The per-user task-creation limit is enforced concurrently, counts only newly created tasks, allows the five-category workflow, and does not impose a per-metric or freshness cooldown.
- A user without a session, ticker membership, or required opt-in/owner permission cannot create an assignment.
- Existing claim functions select only open tasks or expired claimed tasks, never completed/cancelled; concurrent calls preserve one active claim per researcher.
- Two authenticated researchers concurrently call create-or-renew for the same metric: one series and one current task exist; both may receive that task ID, but concurrent claim attempts produce exactly one claimant and one rejected/unavailable result.
- `commons_claim_task` changes a staged open task to claimed with a live 30-minute lease while lineage trigger is installed; `commons_publish_finding` inserts one finding and changes that task to completed in one transaction; replaying the original request still returns the same completed task.
- `commons_release_task` releases only the caller's active task, leaves lineage intact, and reopens only the current task; unauthorized release attempts fail without changing task or finding data.
- Release a claimed task with no findings and expect `open`; release a claimed task with a finding and expect `completed` (not invalid `complete`). Both tests assert finding count and `research_series_id` / `renewed_from_task_id` remain unchanged.
- `commons_claim_next` claims a separate open task with the lineage trigger installed; a second active claim by the same researcher is rejected. Run two-user claim races in separate staging sessions.
- Publishing still marks the claimed task `completed`; re-research creates a different task ID.
- Claiming one category or all five proceeds sequentially without changing the dashboard’s five groups. The 60-minute freshness UI does not block any action.
- Existing and newly published findings remain queryable after `expires_at`; no cleanup job deletes them; paginated history returns all rows in stable order while the dashboard continues to show its five categories.
- Verify anonymous/authenticated public feed permissions, source attribution, and unchanged TradingView/WebMCP behavior.

## Frontend Integration Required

No website code is changed by the migration proposal. To connect it to `research-workspace.html`:

- Add an initial-research action for each approved metric with no series. It supplies the approved `category_key`, `metric_key`, and a fresh UUID `p_request_id`; area/question come from the server catalog. Do not send client-authored metric definitions.
- For an existing series, send its current task ID as `p_source_task_id` and a fresh request UUID. Open/claimed tasks resolve to the same task; completed/cancelled tasks produce a new task ID. Do not offer completed/cancelled rows to the claim RPC.
- Map legacy tasks before user operation through the service-role bootstrap process, never from the researcher UI. Then use the returned task ID for later cycles.
- When the RPC returns an existing `open` or `claimed` task, use the existing claim flow; do not treat the RPC response as a claim. Handle the existing claim RPC’s conflict response when another researcher wins.
- Keep the approved metric key distinct for each metric (for example `volume.relative` and `volume.options`) while mapping both to the dashboard’s Volume category. The RPC returns minimal JSON (`id`, `ticker`, `research_area`, `research_question`, `status`); render those fields using existing task/finding paths.
- Refresh assignments and findings after creating a task. Keep the five dashboard buckets, TradingView chart, public findings feed, and freshness indicator unchanged; freshness must not disable or gate these actions.

## Artifacts

- `PHASE_2_RENEWAL_PREFLIGHT.sql`: read-only catalog/schema/data/job inspection.
- `PHASE_2_RENEWAL_PROPOSED.sql`: review-only migration draft; assumptions and claim-status release gate apply.
- `PHASE_2_RELEASE_STATUS_FIX.sql`: guarded, separately reviewable staging-only fix for the release status literal.
- `PHASE_2_RENEWAL_ROLLBACK.sql`: guarded rollback that refuses to discard live lineage.
- `PHASE_2_RENEWAL_TESTS.sql`: staging transaction test for renewal idempotency.
# ORCA Phase 2 authenticated two-researcher integration test

**Review-only harness. It has not been run and makes no database or Auth
requests unless a reviewer explicitly launches it.**

## Files

- `ORCA_PHASE_2_AUTHENTICATED_INTEGRATION_TEST.mjs` uses Node's built-in
  `fetch` and `readline`; it adds no package dependency.
- `ORCA_PHASE_2_AUTHENTICATED_INTEGRATION_PREFLIGHT.sql` is read-only and
  requires zero existing RKLB tasks, findings, metric series, and requests.
- `ORCA_PHASE_2_AUTHENTICATED_INTEGRATION_CLEANUP.sql` is a separate,
  destructive transaction. It deletes only the three request rows, one precisely
  labeled synthetic finding, two linked test tasks, and their metric series
  after validating every expected ID and relationship.

## Safety and authentication

The harness accepts only an HTTPS Supabase project URL and a publishable/anon
key from the Orca-staging project settings. It asks the operator to type the
project reference followed by `staging`, then prompts for both Auth emails and
passwords. Password entry is hidden; passwords, access tokens, and refresh
tokens are not printed or written to disk. Authenticated calls use the access
tokens returned by Supabase's password sign-in endpoint. No JWT claims are
simulated, no service-role key is accepted or used, and no browser/site files
are changed.

The harness refuses to proceed unless the authenticated accounts map to the
existing opted-in `ORCA Test Researcher 1` and `ORCA Test Researcher 2`
profiles, each has RKLB membership, and the public RKLB tasks/findings feeds
are empty. Since the metric-series and request-ledger tables have no client
read grants, run the read-only preflight SQL immediately beforehand as
`postgres`. Verify the four RKLB research-data counts are zero and the stock,
active metric, named opted-in profiles, and profile memberships report
`1, 1, 2, and 2` respectively. A mismatch is a stop condition.

## Test sequence and expected checks

1. Researcher A and B sign in through Supabase Auth and are confirmed as
   distinct users matching the two existing staging profiles.
2. A creates the approved RKLB SEC-filings assignment with a random request
   UUID. While it remains open, A concurrently retries that UUID as B submits a
   separate request for the same metric. Both must return the same open task
   ID; the harness checks idempotency and concurrent cross-user request
   consistency.
3. A claims the task; the harness verifies the owner and active lease.
4. B's claim, release, and publish attempts against A's active assignment must
   each receive an HTTP error. B's attempt to replay A's request UUID must also
   be rejected. The original A claim is checked again for unchanged state.
5. A publishes one synthetic finding bearing a unique run UUID in its summary,
   with explicit synthetic-test limitations and an example-only source URL.
   The harness checks the completed task and reads the exact finding through
   the anonymous public feed.
6. Two concurrent calls by B use the same renewal request UUID and completed
   source task. Both must return the same new open task ID.
7. B claims the successor. The harness checks its live lease, B ownership,
   predecessor link, and series; it then confirms the completed original task
   and its exact finding are still present, and that the RKLB feed contains
   exactly these two test tasks.

The harness prints a cleanup manifest containing test IDs only. A full
successful run's expected final line is:

```text
PASS: two authenticated users completed the staging integration flow.
```

Any error is a stop condition. The harness prints a partial manifest if an RPC
may have committed; do not retry blindly or run cleanup on a partial/failed run.
Preserve the output for review.

## Staging procedure

1. In the Supabase dashboard, verify the project is **Orca-staging**, not
   production. Confirm both named accounts are available and have opted-in
   profiles plus RKLB membership.
2. Run `ORCA_PHASE_2_AUTHENTICATED_INTEGRATION_PREFLIGHT.sql` in the staging
   SQL Editor. Proceed only if tasks, findings, series, and requests all report
   `0`; the stock and active metric each report `1`; and the named opted-in
   profiles and their RKLB memberships each report `2`.
3. In an interactive terminal with Node.js 18 or newer, set only the staging
   URL and staging publishable key:

   ```sh
   export ORCA_STAGING_URL='https://<staging-project-ref>.supabase.co'
   export ORCA_STAGING_PUBLISHABLE_KEY='<staging-publishable-key>'
   node ORCA_PHASE_2_AUTHENTICATED_INTEGRATION_TEST.mjs
   ```

   Type the displayed `<staging-project-ref> staging` confirmation. Enter the
   two account emails and passwords at the prompts. Never put account
   passwords, service-role credentials, or access tokens in command arguments,
   environment variables, files, or chat.
4. Review the whole output and cleanup manifest. Verify the flow's PASS lines
   and all identifiers belong to this run before preparing cleanup.
5. Only after a full successful run, replace the five UUID placeholders in
   `ORCA_PHASE_2_AUTHENTICATED_INTEGRATION_CLEANUP.sql` with the manifest's run
   ID, initial request ID, observer request ID, renewal request ID, and finding
   ID. Inspect the selected Orca-staging project one more time, then run the
   complete cleanup script as `postgres`. It validates the two researcher
   identities, three request-ledger entries, exact metric, exactly two linked
   tasks, B's active claim, and one matching synthetic finding before deleting
   anything; all deletes are limited to those validated test records and
   committed as one transaction.
6. Re-run the read-only preflight and confirm all four counts are `0`.

Cleanup deliberately does not run automatically. If validation fails, the
cleanup transaction raises and rolls back. Do not weaken its guards or broaden
the deletes to make cleanup pass.

## Review boundaries

This is a staging-only authenticated integration harness, not an install
migration or a production test. It calls only the existing create/renew, claim,
release, and publish RPCs and the allowed public/own-profile read APIs. It does
not create Auth accounts, change memberships or permissions, bypass RLS, run
SQL, change website behavior, or deploy anything.

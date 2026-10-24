# ORCA Phase 3A staging workspace preview

This is a staging-only browser preview. It does not change the production site.
The existing published staging site does not yet include Aly's onboarding
routes. The preview route, `research-workspace-staging.html`,
opens the existing `research-workspace.html` implementation. The dedicated
GitHub Pages repository path `/orca-staging/` and the existing
`environment=orca-staging` preview parameter both select the staging project.
The route and shared workspace use the public Supabase publishable key for
project `vbziibatnejoswsdggga`; a read-only Auth settings request returned
HTTP 200 and the matching `sb-project-ref` response header. The dedicated
staging path also ensures direct visits to account and team pages stay on
staging rather than falling back to production.

## Open a local preview

From the repository root, run a static server, for example:

```sh
python3 -m http.server 8000
```

Open `http://localhost:8000/research-workspace-staging.html?ticker=RKLB`.
The page must display **ORCA STAGING — TEST ENVIRONMENT** before signing in.
Sign in using an existing Orca-staging Auth account. The staging account and
browser session are separate from the production project's session.
Use a private Codespaces-forwarded port for your own preview. A ChatGPT Work
browser may not be able to reach a local or private Codespaces URL.

## Phase 3B deployment (published)

Separate public staging repository:
`https://github.com/jonfordy5/orca-staging`.
Published Pages root: `https://jonfordy5.github.io/orca-staging/`.
RKLB workspace:
`https://jonfordy5.github.io/orca-staging/research-workspace-staging.html?ticker=RKLB`.
Deployed commit: `c1abec29afb7c2e2a030fef6ea1ac7c4589c8460`.
Pages is published from `main` at `/` with HTTPS enforced. The Pages build
completed successfully. The package's staging-only config selects the staging
project regardless of query parameters.

The deployment package is assembled locally in `orca-staging-deployment/`.
Run `node prepare-orca-staging.mjs` to regenerate the package's shared pages.
The `research-workspace.html` page is a staging-only maintained source override:
the builder verifies its Phase 3C marker and RPC wiring and refuses to replace
it with the shared production workspace. Keep the staging repository checked
out at `orca-staging-deployment/`, with that page committed there, before
preparing a deployment. Its
exact allowlist is `index.html` (the staging route alias),
`research-workspace-staging.html`, `research-workspace.html`, `account.html`,
`agent-profile.html`, `join-research.html`, `participation.html`,
`orca-staging-config.js`, and `commons-site-tools.js`.
The package supplies its own staging-only config: it always selects the
`vbziibatnejoswsdggga` project, irrespective of URL parameters, and has no
production config import or fallback. The builder rewrites the auth callback to staging and removes the
production-only worker enrollment route from the package.
It excludes the production homepage/config, SQL, local test artifacts,
credentials, and unrelated source files. The currently published repository
contains the original seven website files; the locally prepared onboarding
package contains the nine files in the updated allowlist.

Page styles are inline; runtime external dependencies are Supabase JS v2 from
esm.sh and the TradingView chart widget. ChatGPT help and the ChatGPT launch
link are outbound links, not runtime dependencies. Research evidence links
also intentionally open their cited source URLs. The Supabase JS v2 and
TradingView widget URLs both returned HTTP 200 during deployment verification.

The Join Research page exposes the existing profile and permission controls in
staging and omits the production-only worker enrollment route. The staged
profile and participation pages use the generated configuration, which is
locked to project `vbziibatnejoswsdggga`.

The locally prepared `ORCA_PHASE_3A_ALY_PROFILE_RLS.sql` removes direct client
table INSERT/UPDATE grants, restores only owner/name profile operations, and
adds a restrictive owner-scoped INSERT policy requiring `opted_in = false`.
It adds two authenticated SECURITY DEFINER RPCs: one creates the caller's
profile with consent false, and one changes consent on only the caller's
existing profile using `auth.uid()`. Both have an empty search path, qualified
object references, and EXECUTE granted only to `authenticated`. The consent
RPC uses the existing `commons_owner_opt_out_release` trigger; the migration
does not alter that trigger, assignment tables, or finding tables.

The website's profile and permission controls call those RPCs directly using
the staging-only generated config. `ORCA_PHASE_3A_ALY_PROFILE_SECURITY_TESTS.sql`
contains rollback-only tests for two fresh, independent staging test identities,
including cross-owner attempts, unauthenticated calls, direct table-write
denials, and checks that the existing opt-out trigger remains installed. The
migration and tests are prepared locally only; neither was executed. Run the
single SELECT in `ORCA_PHASE_3A_ALY_PROFILE_PREFLIGHT.sql` first, after
confirming the staging project ref in the dashboard. Do not use a service-role
key in the browser or weaken RLS.

This onboarding package, RLS/RPC migration, and security tests are prepared
locally and are not yet deployed.
No profile was created, permission enabled, SQL run, membership changed, or
finding modified as part of preparing it.

The account confirmation callback points exactly to the approved staging root
URL. The root page forwards the Supabase callback fragment to the workspace,
where the existing Supabase client can process it. The owner reports this
staging Authentication redirect URL was saved:
`https://jonfordy5.github.io/orca-staging/`.

The public Auth settings endpoint was read-only checked and returned HTTP 200
with the expected staging project reference. It does not return the configured
Site URL or redirect allowlist, so the saved Auth setting could not be
independently verified. Email confirmation with a real staging test account
remains untested. Use only test accounts and non-sensitive test data. The
browser key is publishable, not secret; never include a password, service-role
key, or private credential in the staging site.

Live checks confirmed all seven Pages URLs returned HTTP 200 and that a
production-like `environment=production` parameter still served the staging
banner and staging config. A read-only REST request to the staging project
returned one open RKLB assignment, “SEC Filings & Catalysts.” No public RKLB
findings were returned. The live browser dashboard itself and authenticated
RLS behavior were not browser-tested because no browser automation or staging
test account was available.

The preview uses the existing authenticated claim, release, publish, and public
finding-read paths. It adds a staging-only metric request/renew control using
`commons_create_or_renew_research`, with a fresh UUID per request and the exact
completed/cancelled predecessor task ID for renewals. It does not start an AI,
research a topic, publish a finding, or create an assignment until a researcher
explicitly initiates those actions.

## Boundaries and setup notes

- Browser code uses only the public staging publishable key; never add a
  service-role/secret key, ChatGPT credential, or OpenAI API key.
- Normal production workspace navigation does not select staging or show the
  staging-only assignment request controls.
- Staging sign-in requires an Auth user in the staging project. If email
  confirmation is required for a new staging user, the staging Auth redirect
  allowlist must permit the preview's return URL.
- ChatGPT Work must be able to access the preview URL and use the owner's
  authenticated browser session. It may require the owner to complete login or
  confirm the publish action. The website does not launch or claim to connect a
  personal assistant.
- No SQL, assignment claim, or finding publication was performed. Production
  repository, Pages, Supabase project, and schema were not changed.

# ORCA Phase 3A staging workspace preview

This is a staging-only browser preview. It is not deployed and does not change
the production site. The preview route, `research-workspace-staging.html`,
opens the existing `research-workspace.html` implementation with the explicit
`environment=orca-staging` setting. Only that setting selects the staging
project. The route and shared workspace use the public Supabase publishable
key for project `vbziibatnejoswsdggga`; a read-only Auth settings request
returned HTTP 200 and the matching `sb-project-ref` response header.
Staging pages load only the pinned staging client configuration; the existing
production public configuration is dynamically loaded only outside staging mode.

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
browser may not be able to reach a local or private Codespaces URL; do not
change the port to public or deploy the preview without a separate review and
approval.

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
- No SQL, assignment creation, publication, deployment, or production change
  is part of preparing this preview.

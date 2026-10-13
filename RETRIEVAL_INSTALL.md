# Install the read-only lesson retrieval tools (mobile-friendly)

This pack **does not** overwrite `index.html`, the existing three forms, the research pilot, or the empty lesson archive. It adds discoverability and an assistant-friendly retrieval interface.

## Upload

1. Open https://github.com/jonfordy5/agent-learning-commons/upload/main
2. Choose the FIVE files in this kit (`retrieve.html`, `CONNECT_AN_AGENT.md`, `llms.txt`, `OPENAPI_ACTION.yaml`, `RETRIEVAL_INSTALL.md`). Keep them at repository root alongside `index.html` and `lessons.json`.
3. Commit with message: `Add collective lesson retrieval tools`.
4. Once GitHub Pages updates, open https://jonfordy5.github.io/agent-learning-commons/retrieve.html
5. It should display `0 matches · 0 published records` (until a lesson is approved) and a separate **Latest community proposals** section. GitHub Issues may be empty too. The reviewed archive should *not* show a network error.
6. Tap **Copy agent instructions** and paste into a web-enabled assistant. It should be able to fetch the same feed if its tools allow it.

## Optional homepage button (small edit; no overwrite)

Edit the *current* `index.html` in GitHub. Directly AFTER the existing "Start Your Own Experiment" button and before the `<div class="card">` status section, insert:

```html
<a class="btn secondary" href="retrieve.html">🔎 Search Shared Lessons</a>
```

Commit with message `Link public lesson retrieval` and refresh the public home page after deployment. Do not upload an older `index.html` from a ZIP: that would overwrite your recent experiment button.

## Test an agent read

Prompt a web-enabled assistant:

> Open https://raw.githubusercontent.com/jonfordy5/agent-learning-commons/main/lessons.json and tell me the `count` and the number of entries in `lessons`. If the feed is empty, say so and don't invent a discovery.

Initial expected result: `count: 0`, `lessons: []`.

## Next step to make the library *useful*

After actual submissions have been reviewed, maintainers must add approved entries to `lessons.json`. Then the search page and any participating agents fetching the feed can retrieve them. GitHub Issues are **submissions**, not automatically verified findings. A future service could index issues and generate curated records, but human review should remain in the loop.

## Integration scope

New unverified GitHub Issues are visible in a separate section; do not treat them as confirmed discoveries. The YAML schema is an optional compatibility aid for GPT products that still allow custom HTTP actions or other OpenAPI-compatible clients. A public data feed does not make every GPT session automatically learn from it. External apps and agents must choose to connect. GitHub Pages supports static JSON hosting and client-side search, not a dynamic semantic search API.

# Pilot 001 — Round A blinded test cases

These are fictional miniature website repositories made for this experiment. **Do not attempt to access them online.** Their file inventories are complete. Paths are case-sensitive; links are evaluated as written; no automatic redirects or alias files exist. A working relative URL is resolved relative to its containing document or stylesheet. Unless a case says otherwise, its published GitHub Pages site lives at `https://example.github.io/collab-lab/`.

Copy **only one full case at a time** into each new chat. Do not give an agent other cases, the scoring key, or another agent's answer.

---

## C01 — Issue form buttons

**Files present:**
- `index.html`
- `repo-links.js`
- `.github/ISSUE_TEMPLATE/join.yml`
- `.github/ISSUE_TEMPLATE/experiment.yml`

**`repo-links.js` relevant lines:**
```js
const destinations = {
  join: 'https://github.com/demo/collab-lab/issues/new?template=join.yml',
  lesson: 'https://github.com/demo/collab-lab/issues/new?template=report.yml'
};
```
**`index.html` relevant links:**
```html
<a href="https://github.com/demo/collab-lab/issues/new?template=join.yml">Join</a>
<a href="https://github.com/demo/collab-lab/issues/new?template=report.yml">Share a discovery</a>
```
**Task:** Audit all project-controlled reference destinations appearing in the snippets. Minimal exact changes only.

---

## C02 — Simple navigation

**Files present:**
- `index.html`
- `invite.html`
- `docs/faq.html`

**`index.html`:**
```html
<nav>
  <a href="invite.html">Invitation</a>
  <a href="docs/faq.html">FAQ</a>
</nav>
```
**Task:** Audit all project-controlled reference destinations. Minimal exact changes only.

---

## C03 — Case-sensitive folder names

**Files present:**
- `index.html`
- `docs/setup.html`

**`index.html`:**
```html
<a href="Docs/setup.html">Read setup</a>
```
**Task:** Audit all project-controlled reference destinations. Minimal exact changes only.

---

## C04 — Nested document relative path

**Files present:**
- `index.html`
- `pages/help.html`

**`pages/help.html`:**
```html
<a href="index.html">Home</a>
```
**Task:** Audit all project-controlled reference destinations. Minimal exact changes only.

---

## C05 — Stylesheet asset path

**Files present:**
- `index.html`
- `css/site.css`
- `assets/logo.svg`

**`index.html`:**
```html
<link rel="stylesheet" href="css/site.css">
```
**`css/site.css`:**
```css
.logo { background-image: url("assets/logo.svg"); }
```
**Task:** Audit all project-controlled reference destinations. Minimal exact changes only.

---

## C06 — HTML/JavaScript lookup mismatch

**Files present:**
- `index.html`
- `repo-links.js`
- `.github/ISSUE_TEMPLATE/discovery.yml`

**`index.html`:**
```html
<a data-github="discovery">Share research</a>
<script src="repo-links.js"></script>
```
**`repo-links.js`:**
```js
const destinations = {
  lesson: 'https://github.com/demo/collab-lab/issues/new?template=discovery.yml'
};
document.querySelectorAll('[data-github]').forEach((el) => {
  const href = destinations[el.dataset.github];
  if (href) el.href = href;
});
```
**Task:** Audit all project-controlled reference destinations and dynamic references. Minimal exact changes only.

---

## C07 — Valid project-relative links

**Published site:** `https://example.github.io/collab-lab/`

**Files present:**
- `index.html`
- `about.html`
- `assets/logo.svg`

**`index.html`:**
```html
<a href="./about.html">About</a>
<img src="./assets/logo.svg" alt="Logo">
```
**Task:** Audit all project-controlled reference destinations. Minimal exact changes only.

---

## C08 — Host-root versus project-root

**Published site:** `https://example.github.io/collab-lab/`

**Files present:**
- `index.html`
- `about.html`

**`index.html`:**
```html
<a href="/about.html">About</a>
```
**Task:** Audit all project-controlled reference destinations. Minimal exact changes only.

---

**End of tasks.** Participants should not score their own answers from another agent's output. Submit every attempted response, including wrong and uncertain ones.

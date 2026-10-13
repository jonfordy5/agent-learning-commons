# Five-step publication and recruiting checklist

**Current status: everything in this folder is local. No GitHub repository, site, outside invitation or participant has been created or contacted by producing this kit.**

## 1 — Create a public repository

- Sign in to https://github.com/ (or create a free account).
- Open https://github.com/new.
- Repository name: `agent-learning-commons`.
- Description: `Shared, human-reviewed lessons from AI-assisted research — including failures.`
- Visibility: **Public**; initialize without a README if you want to upload this whole folder without file conflicts.
- Press **Create repository**.

## 2 — Upload the actual public files

- Extract `agent-learning-commons-launch-ready.zip` on a computer.
- In your new GitHub repository, choose **Add file → Upload files**. Drag the **contents** of the extracted folder (not the ZIP and not the outer containing folder) into the upload area.
- Confirm `index.html`, `repo-links.js`, `lessons.json`, `PILOT_001.md` and **`.github/ISSUE_TEMPLATE/join.yml` and `lesson.yml`** appear in the right paths. Hidden `.github` files may require enabling “show hidden files” on your computer.
- Commit the files to the `main` branch. Do not upload your private prototype or its draft records.
- If folders are missing, use GitHub's **Create new file** and include folder names in the path or use GitHub Desktop.

## 3 — Publish the project website

- In the repository, go to **Settings → Pages**.
- Under **Build and deployment**, choose **Deploy from a branch → `main` → `/ (root)` → Save**.
- The normal address becomes `https://YOUR-GITHUB-USERNAME.github.io/agent-learning-commons/`.
- Test the site, its **Join the pilot** and **Propose a lesson** buttons, its copy-invitation page, and `lessons.json`.
- Make sure **Issues** is enabled under **Settings → General → Features**; GitHub Issue forms require this.

## 4 — Invite interested human–AI teams, with permission

- Send/share the **actual live** project page URL; use `OUTREACH_POSTS.md` for ready-to-paste copy.
- Invite interested individuals directly; where appropriate, post in developer communities, GitHub projects, and research discussion groups **only if their posting rules allow it**. Do not spam or imply other GPT sessions can be contacted directly.
- Ask each person to present `INVITE_AGENTS.md` or `agent-invite.txt` to their assistant *only if they want to* and have them evaluate critically.
- Start with a small cohort (e.g. 5–10 consenting human–AI teams) and Pilot 001 rather than making broad collective-intelligence claims from a handful of responses.

## 5 — Collect, verify and publish what is learned

- New GitHub Issues contain Join / Lesson forms. They are **public immediately** and therefore must contain only material contributors approve for publication.
- Manually inspect submissions for sensitive material and spam before incorporating them into the `lessons.json` archive.
- Label unverified/replicated/refuted findings; document baselines, dates, negative outcomes, source evidence, and limitations; keep retractions.
- Publish only human-reviewed findings to the data feed. There is **no automatic ingestion**, model-to-model private network, or self-updating model.
- First success metric: **at least one independently checkable lesson and one independent replication/counterexample**, not merely the number of enthusiastic replies.

## Practical limitations

This package cannot access your GitHub account, create the remote repository, enable Pages, or post invitations from this ChatGPT session. Those account operations require an authenticated person or a separately authorized publishing integration. Do not enter GitHub passwords or API tokens into chat.

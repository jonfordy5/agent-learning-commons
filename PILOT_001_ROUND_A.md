# Pilot 001 — Round A: Can one team's debugging lesson help another AI team?

**Agent Learning Commons | Protocol v1.0 | Status: OPEN FOR VOLUNTEERS — NO RESULTS YET**

> "A discovery shared can become a lesson for thousands. A discovery forgotten may have to be learned thousands of times."

## Origin: an actual lesson we learned

Our website's **Propose a lesson** button initially referenced `lesson.yml`, while the GitHub issue form was named `discovery.yml`. We corrected the mismatch and then checked the real user-facing form. This is an observed project error, **not** evidence that other AI systems will benefit from reading about it.

**Question:** On previously unseen miniature website projects, will AI assistants that receive a reviewed debugging lesson identify broken links more accurately than otherwise comparable assistants that do not receive the lesson?

## One-sentence design

Human volunteers run the same eight link-audit cases in **independent, fresh chats** under two conditions: (A) the case alone, or (B) the identical case plus a short verified lesson. We compare objectively scored answers. No money, proprietary data, or agent-to-agent access is required.

## Who can participate

Anyone using a ChatGPT, Claude, Gemini, or other AI assistant. You must supervise submissions; do not share private chats, system prompts, credentials, or confidential code. A GitHub account is useful for posting results, but not required to try the tasks locally.

## Materials

- `PILOT_001_CASES.md`: eight artificial debugging problems. These **are not production website issues**.
- `PILOT_001_LESSON.md`: the exact optional lesson to give a treatment assistant.
- `PILOT_001_LOG.csv`: blank results log.
- `PILOT_001_PRECOMMITMENT.txt`: hash of the organizer-held answer key, to discourage changing the answers after collecting results.

The complete answer key is withheld until Round A closes, then should be published with the scoring and all results. **The public package deliberately does not include it.**

## Step-by-step for each volunteer

1. Choose **at least four** case IDs before opening AI chats (all eight preferred). Decide before testing which cases you will use; don't select on the basis of outcomes. For easy coordination, choose C01–C04 for one volunteer, C05–C08 for the next.
2. For EACH chosen case, start **two entirely new chats** with the **same named model/version, tools and settings** when possible. Do not allow one chat to see the other's answers. Disable web access and code execution if the product allows; every relevant fact is in the case.
3. Use the **CONTROL prompt** below with only the case text in one chat. Use the **LESSON prompt** with the exact published lesson and the identical case text in the other. Apart from the lesson, instructions must be identical. Keep the case order and condition order varied, e.g. use a coin toss for lesson-first vs control-first per case. Never coach or correct answers during the trial.
4. Copy the AI's first complete response (or a link/screenshots with private data removed), record date, named model/version, case ID, condition, whether any tools were used, and answer. Submit **every** attempted trial, including failures and uncertain answers.
5. The organizer scores responses against the same withheld answer key (1 = fully correct; 0 = otherwise), flags ambiguous answers before peeking at the condition if feasible, and publishes the key and anonymized results after the round closes. Report both wins and losses; do not equate a nice explanation with a correct patch.

### Identical core task instruction, used in both arms

> Audit the miniature static website case below. Assume the file inventory is complete, paths are case-sensitive, and there are no redirects or implicit aliases. Use only the information given. Identify **every broken project-controlled reference**, or write `NONE`. For each broken reference, name the referencing file and give the **minimal exact correction**. Do not invent missing files or change references that already work. Format your answer as: `CASE | BROKEN REFERENCES | EXACT FIXES | REASON`. Do not ask follow-up questions.

**Control arm:** paste the core task instruction and the full relevant case from `PILOT_001_CASES.md` into a fresh chat.

**Lesson arm:** paste the core task instruction, then the complete contents under **SHARED LESSON — START/END** in `PILOT_001_LESSON.md`, then the identical case text into a different fresh chat.

The **same human** should not translate, improve, or clarify an agent's answer. Each run counts only the first complete response.

## Scoring and predeclared outcomes

- Per case and condition: **1** if all broken references and exact minimal corrections are correct **and no functioning reference is falsely marked broken**; otherwise **0**.
- Main measure: `lesson accuracy (%) - control accuracy (%)` across paired case runs. Also publish paired counts: improved, worsened, both right, both wrong.
- Record run exclusions with reasons **before scoring**. If the assistant used external tools or context not permitted, flag rather than silently delete the trial.
- **Pilot threshold:** Aim for at least **10 volunteers** and **at least 40 paired case runs**. Earlier results are useful for checking whether the protocol works, **not** proof of generalizable improvement.
- If both arms score 100%, we have a ceiling effect, not proof shared lessons are useless. If one arm wins on this narrow task, it does not show that sharing lessons improves all AI reasoning or permanently trains the model.

## How to contribute

1. Sign up through **Join the learning pilot** in our GitHub Issues and mention `Pilot 001 — Round A`.
2. Run paired tests privately using the public cases and record results using the CSV.
3. Open **Share a discovery or lesson** on the project Issues page. In your submission, include all case IDs, conditions, model/version, raw answers (privacy reviewed), and your log. Do **not** score yourself using a leaked answer key.
4. We will publish an aggregate readout, full answer key, failure modes, and replication invitation when the round concludes.

**Project:** https://github.com/jonfordy5/agent-learning-commons  
**Registration:** https://github.com/jonfordy5/agent-learning-commons/issues/new/choose  
**Website:** https://jonfordy5.github.io/agent-learning-commons/

## Limits and integrity

Participating assistants do **not** directly contact each other and do **not** update their model weights from this experiment. Shared evidence is an external, human-reviewed artifact. Case authors may know the answers; participating humans must not coach either arm. Repeated prompts, mismatched models, knowledge leakage, and selective reporting can bias results, so disclose deviations. We welcome negative and inconclusive results.

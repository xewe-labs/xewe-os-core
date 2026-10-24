# RULES.md — root rules for agents

Every rule below is absolute. It applies in every project that carries this folder and is
never edited inside a project. Rules are cited by ID (`R-01` …). Project preferences (`P-xx`)
live in `./.agents/PREFERENCES.md`; user preferences (`U-xx`) live in
`~/.agents/users/<me>/PREFERENCES.md`. If two instructions conflict, R-02 decides.

## 1. Entry and precedence

- **R-01 Read order.** On opening the project, read completely and in this order:
  `AGENTS.md`, `RULES.md`, `PREFERENCES.md` (if present), `~/.agents/users/<me>/PREFERENCES.md`
  (if present), then the frontmatter of every project skill `./.agents/skills/*/SKILL.md` and
  every global skill `~/.agents/skills/*/SKILL.md`. Do no project work before all of these
  have been read.
- **R-02 Precedence.** An explicit human instruction given in the current session outranks
  `RULES.md`, which outranks `PREFERENCES.md`, which outranks `users/<me>/PREFERENCES.md`,
  which outranks `AGENTS.md`, which outranks any individual skill. A preference never
  overrides a rule.
- **R-03 The global layer is read-only.** `README.md`, `AGENTS.md` and `RULES.md` in a project
  are overwritten from the central repository on every session start; the global skills,
  `users/*/PREFERENCES.md` and `harnesses/` live only in `~/.agents/`. Never edit any of them
  in a project or in `~/.agents/`; propose the change for the central repository.

## 2. Conduct

- **R-04 No secrets.** Never read secret files: `.env` and `.env.*` (except `.env.example`,
  `.sample`, `.template`, `.dist`), `*.key`, `*.pem`, `*.p12`, `*.pfx`, and SSH private keys
  (`id_rsa`, `id_ed25519`, …); the harness guardrail blocks them too. Nothing an agent writes
  into the project (handoffs, skills, preferences, code) contains secrets, tokens,
  credentials, or private notes. Handoffs are committed and may be public.
- **R-05 Propose, do not legislate.** An agent never adds or changes a rule or a preference.
  A missing or unclear one is proposed to the human, and recorded in the handoff's "Design
  decisions" if a handoff is written.
- **R-06 Report honestly.** State what was actually run and what was observed. Label anything
  not verified as unverified. Never report a skipped or failed step as done; failures come
  with their output.
- **R-07 Talk like a colleague at the next desk.** Answer first, in plain sentences, and stop
  when the answer is complete. Match the length to the question. A yes-or-no question gets
  the answer and the one reason that matters. A finished task gets what changed, where it
  lives, and what the human has to do next. Mention a step you took only when it changes what
  the human believes or does, and report a failure with its output. Use a list or a table
  only for items the reader will compare or act on one at a time. The human reads these
  replies between other work, so a sentence that adds nothing uses up attention the next real
  warning will need.
- **R-08 Stay focused.** Keep to what the human asked. When a task is done, restate to
  yourself the main goal of this conversation before replying or starting anything else, and
  check that the reply and any next step serve it. A side issue you noticed gets one line in
  the reply, not a detour; no unrequested refactors, fixes, files or features.
- **R-09 Never without being asked.** Do not delete anything you did not create in this
  session, and do not publish to any network service.
- **R-10 No git or GitHub writes.** Do not run `git commit`, push any branch or tag, create or
  delete remote branches or tags, or create, edit, merge, close or comment on pull requests,
  issues, releases, gists or workflow runs, by `git`, `gh`, `gh api` (any method but GET), or
  a GitHub MCP tool. Print the commands for the human instead. Reading (fetch, clone, status,
  `gh pr view`) is fine. Only an explicit instruction in the current session lifts this
  (R-02), and even then no commit, pull request or issue carries a `Co-Authored-By` trailer,
  a "Generated with" line, or any other AI attribution.

## 3. Documentation

- **R-11 Documentation only through `xewe_doc`.** Every documentation change in a project goes
  through the `xewe_doc` skill: load it before the first edit and follow it. That covers any
  `README.md`, `doc/`, code comments, and everything under `./.agents/skills/` (including the
  `doc` skill that holds agent knowledge). When you learn something a later agent would need
  and the code does not show (a gotcha, an exact command, a decision), record it the same
  way. Global files (R-03) and handoffs (R-14) are not documentation in this sense.

## 4. Skills

- **R-12 Discover skills from their frontmatter.** A skill is a folder `skills/<name>/` that
  holds a `SKILL.md`, under `./.agents/` (project) or `~/.agents/` (global). Skills are found
  by reading the `name` and `description` frontmatter of every such `SKILL.md`. Nothing else
  indexes them. A folder whose `SKILL.md` is missing or fails R-13 is not a skill and must
  not be used.
- **R-13 Skill shape.** `SKILL.md` has YAML frontmatter with exactly two keys, `name` and
  `description`, and `name` equals the folder name. Supporting files sit beside `SKILL.md` or
  under `references/`, `scripts/`, `assets/`, or `evals/`.

## 5. Handoffs

- **R-14 Access only through `xewe_handoff`.** Nothing under `users/<me>/handoffs/` is read,
  created, edited, moved, or deleted except by executing the `init`, `read`, or `write`
  procedure of the `xewe_handoff` skill. The skill stops and reports any inconsistency; it
  never repairs.

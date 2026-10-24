# AGENTS.md

This is **xewe 2.3**, the agentic workspace. Human documentation and the source of every
global file: https://github.com/maxdokukin/dot_agents

Two roots. `./.agents/` is this project's folder; `~/.agents/` is the global install on this
machine (may be absent, e.g. in a cloud session). Paths below say which one they mean.

| Layer | Contents | Ownership |
|---|---|---|
| global | `./.agents/README.md`, `./.agents/AGENTS.md`, `./.agents/RULES.md`; and, only in `~/.agents/`: the global skills (`xewe_handoff`, `xewe_doc`, `sample_skill`), `users/<me>/PREFERENCES.md`, `harnesses/` | The three files here are overwritten from the central repo on every session start. Read-only (R-03). |
| project | `./.agents/PREFERENCES.md` (P-xx), `./.agents/skills/*` | Owned by the project, committed with it. |
| user | `./.agents/users/<me>/handoffs/` | Written only by `xewe_handoff`. Committed with the project. |

`<me>` is the GitHub login: `gh api user -q .login 2>/dev/null || git config github.user || echo "$USER"`.

## Read in this order (R-01)

1. `./.agents/RULES.md` — absolute, identical everywhere. Cite by ID.
2. `./.agents/PREFERENCES.md` — project preferences, if the file exists. Cite by ID.
3. `~/.agents/users/<me>/PREFERENCES.md` — the current user's preferences, if the file exists.
   Cite by ID.
4. The frontmatter of every `./.agents/skills/*/SKILL.md` (project skills) and every
   `~/.agents/skills/*/SKILL.md` (global skills; the harness may already list them as native
   skills) — that is the whole skill index (R-12).

Project knowledge written for agents lives in the project skill `doc`, whose `SKILL.md` is the
index, and in topic skills for procedures that keep coming back. Every documentation change,
including recording something you learned, goes through `xewe_doc` (R-11).

## Handoffs are voluntary

`./.agents/users/<me>/handoffs/` is a record of past sessions, committed with the project. Use
`xewe_handoff read` to resume from it and `xewe_handoff write` to leave a trail; run
`xewe_handoff init` once per project and user before the first write. Nothing under
`handoffs/` is touched except through that skill (R-14). Skipping handoffs is allowed;
corrupting them is not. Write nothing there you would not publish.

## Never do these without being asked

- Edit a global file. Propose the change for the central repo instead; a local edit is gone
  at the next session start.
- Name a project skill after a global skill.
- Touch `users/*/handoffs/` by hand (R-14).

Conduct (no secrets, honest and brief reporting, staying focused, no deleting or publishing,
no git or GitHub writes) is in `RULES.md`, R-04 to R-10.

## Precedence (R-02)

Human instruction in this session > `RULES.md` > `PREFERENCES.md` > `users/<me>/PREFERENCES.md`
> this file > a skill. Record every human-instructed deviation in the handoff, quoting the
instruction, if a handoff is written.

## Harnesses

`~/.agents/harnesses/<harness>/` holds material specific to one host tool, named after the
tool's own dotfolder. Claude Code: `harnesses/.claude/` (`setup.sh` links the global skills
into `~/.claude/skills` and installs the session hook, `sync.sh` is that hook). Harnesses are
not copied into projects. No harness-specific rules exist yet.

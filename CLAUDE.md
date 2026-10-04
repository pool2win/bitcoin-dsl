Look at docs/design/HANDOFF.md and docs/design/scenarios.md to pick up context where we are

## Documentation must stay current

The Racket DSL is documented in `racket-dsl/docs/` (an MkDocs Material site, config in `racket-dsl/mkdocs.yml`). A change to the language, the MCP server, replay or a scenario is not done until these docs describe it, in the same commit.

- **Reference pages are generated.** After changing a form's usage or doc (`racket-dsl/private/describe.rkt`), a consensus rule, an opcode or a proposal, run from `racket-dsl/`: `racket docs/gen-reference.rkt`. `tests/docs.rkt` fails when they are stale.
- **Scenario pages include the tested code** from `racket-dsl/tests/` via snippets; keep the prose around them accurate when a scenario's behaviour changes.
- **Prose pages need a hand:** concepts, guides, `reference/results.md`, scenario write-ups, and the status table on `index.md`. The checklist of what to update for each kind of change is in `racket-dsl/docs/guides/docs.md`.
- **New forms need a `describe` entry**, so agents using the MCP server can find them.
- **Check the build** before committing doc changes: `cd racket-dsl && .venv/bin/mkdocs build` (strict; warnings fail). Set up the venv with `python3 -m venv .venv && .venv/bin/pip install -r docs/requirements.txt`.

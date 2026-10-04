Look at docs/design/HANDOFF.md and docs/design/scenarios.md to pick up context where we are. The old Ruby DSL is in `obsolete-ruby-dsl/`; do not change it.

Follow `AGENT.md`. In particular, write all documentation in ASD-STE100 Simplified Technical English.

## Keep the documentation current

The documentation of the Racket DSL is in `docs/`. It is an MkDocs Material site, with the configuration in `mkdocs.yml`. GitHub Actions publishes it to GitHub Pages from `main` (`.github/workflows/docs.yml`). A change to the language, the MCP server, replay or a scenario is not complete until these docs describe it. Change the docs in the same commit.

- **The reference pages are generated.** After you change the usage or doc of a form (`private/describe.rkt`), a consensus rule, an opcode or a proposal, run `racket docs/gen-reference.rkt` from the root of the repository. If you do not, `tests/docs.rkt` fails.
- **The scenario pages include the tested code** from `tests/` through snippets. When the behavior of a scenario changes, make sure that the text around the code stays correct.
- **You must change the other pages manually:** the concepts, the guides, `reference/results.md`, the scenario pages and the status table on `index.md`. `docs/guides/docs.md` gives the pages to change for each type of change.
- **Each new form must have a `describe` entry.** Then agents that use the MCP server can find it.
- **Build the site before you commit changes to the docs:** run `.venv/bin/mkdocs build` from the root of the repository. The build is strict, and a warning stops it. To make the virtual environment, run `python3 -m venv .venv && .venv/bin/pip install -r docs/requirements.txt`.

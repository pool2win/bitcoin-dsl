# Keeping these docs current

These docs are part of the code: a change to the language is not done until the docs describe it. `CLAUDE.md` at the repository root says the same for agents working on the code.

## What updates itself

- **Reference pages** ([Forms](../reference/forms.md), [Consensus rules](../reference/rules.md), [Opcodes](../reference/opcodes.md)) are generated from the `describe` registry that agents read over MCP. After changing a form's usage or doc, a rule or an opcode, regenerate them from `racket-dsl/`:

    ```sh
    racket docs/gen-reference.rkt
    ```

    `tests/docs.rkt` fails when they are stale, so `raco test racket-dsl/tests` catches a forgotten regeneration.

- **Scenario code** on the scenario pages is included from the test files with snippets (`--8<-- "tests/scenario-1.rkt"`), so the docs show exactly the code the suite runs. A missing file fails the build.

## What needs a hand

Prose pages: the concepts, guides, the [results reference](../reference/results.md) and the scenario write-ups. When a change affects behaviour described there, update the page in the same commit. A checklist:

| Change | Update |
|---|---|
| New or changed form | `private/describe.rkt` entry, regenerate reference, the relevant concept page |
| New rule, opcode or proposal | its doc string, regenerate reference, [Consensus as a value](../concepts/consensus.md) |
| Result or trace shape | [Results and traces](../reference/results.md) |
| MCP tool behaviour | [Using it over MCP](mcp.md), [How agents use it](agents.md) |
| Replay behaviour | [Conformance replay](../concepts/conformance.md) |
| A scenario becomes runnable | its scenario page (drop "planned"), [Home](../index.md) status table |

## Building the site

```sh
cd racket-dsl
python3 -m venv .venv && .venv/bin/pip install -r docs/requirements.txt
.venv/bin/mkdocs serve      # live preview at http://127.0.0.1:8000
.venv/bin/mkdocs build      # static site in racket-dsl/site/ (strict: warnings fail)
```

The site is plain static HTML, ready to publish with GitHub Pages (for example with `mkdocs gh-deploy` from a workflow) on a custom domain via a `docs/CNAME` file.

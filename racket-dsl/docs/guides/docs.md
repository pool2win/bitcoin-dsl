# Keep the documentation current

The documentation is a part of the code. A change to the language is not complete until the documentation describes it. `CLAUDE.md` and `AGENT.md` at the root of the repository give the same instruction to agents.

## The standard for documentation

Write all documentation in ASD-STE100 Simplified Technical English. `AGENT.md` gives the rules that we use. In summary:

- Write descriptive sentences with 25 words or fewer, and procedural sentences with 20 words or fewer.
- Use the active voice. Write procedures as numbered steps in the imperative, with one instruction in each step.
- Do not use words that end in "-ing", phrasal verbs or contractions.
- Use approved words. The table in `AGENT.md` gives the approved words for frequent unapproved words.
- Keep DSL names, rule names, file names and commands as technical names.

`tests/docs.rkt` checks the pages for sentence length, unapproved words, phrasal verbs and contractions. It cannot check all the rules. Read your text against `AGENT.md` before you commit it.

## Pages that change automatically

- **The reference pages** ([Forms](../reference/forms.md), [Consensus rules](../reference/rules.md) and [Opcodes](../reference/opcodes.md)) come from the `describe` registry that agents read over MCP. Thus the doc strings in that registry must also follow the standard. After you change the usage or doc of a form, a rule or an opcode, run this command from `racket-dsl/`:

    ```sh
    racket docs/gen-reference.rkt
    ```

    If you do not run it, `tests/docs.rkt` fails.

- **The scenario code** on the scenario pages comes from the test files through snippets, for example `--8<-- "tests/scenario-1.rkt"`. Thus the pages show the code that the tests run. If a file is not there, the build fails.

## Pages that you must change

You must change these pages manually: the concepts, the guides, the [results reference](../reference/results.md) and the scenario pages. If a change has an effect on the behavior that a page describes, change the page in the same commit.

| Change | Pages to change |
|---|---|
| A new or changed form | The entry in `private/describe.rkt`, the generated reference and the related concept page |
| A new rule, opcode or proposal | Its doc string, the generated reference and [Consensus as a value](../concepts/consensus.md) |
| A change to the shape of a result or a trace | [Results and traces](../reference/results.md) |
| A change to the MCP tools | [Use the MCP server](mcp.md) and [How agents use the DSL](agents.md) |
| A change to replay | [Conformance replay](../concepts/conformance.md) |
| A scenario that now runs | Its scenario page (remove "planned") and the status table on the [home page](../index.md) |

## Build the site

1. Go to `racket-dsl/`.
2. Make a Python virtual environment:

    ```sh
    python3 -m venv .venv
    ```

3. Install MkDocs Material:

    ```sh
    .venv/bin/pip install -r docs/requirements.txt
    ```

4. To see the site while you write, run `.venv/bin/mkdocs serve` and open `http://127.0.0.1:8000`.
5. To make the static site in `racket-dsl/site/`, run `.venv/bin/mkdocs build`. The build is strict, and a warning stops it.

The site is static HTML. You can publish it with GitHub Pages, for example with `mkdocs gh-deploy` from a workflow. A `docs/CNAME` file sets a custom domain.

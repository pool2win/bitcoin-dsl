# Instructions for agents

## Write all documentation in ASD-STE100

Write all documentation in ASD-STE100 Simplified Technical English (STE). This applies to:

- the pages in `docs/`, except the design notes in `docs/design/`;
- the doc strings that the docs and the MCP `describe` tool show (`private/describe.rkt`, rule docs in `private/consensus.rkt`, opcode and failure docs);
- `README.md`.

The design documents in `docs/design/` are working notes. They do not have to follow this standard.

### The rules that we use

**Words**

- Use approved words with their approved meanings. Use one word for one meaning.
- Use technical names as they are: DSL forms, rule names, opcodes, file names and commands (for example `define-tx`, `sequence-lock`, `raco test`).
- Use technical verbs of the field: run, mine, spend, sign, replay, build, compile, return.
- Do not use words that end in "-ing", except in technical names.
- Do not use phrasal verbs ("set up", "look up", "find out", "go back"). Use a single verb.
- Do not use contractions ("don't", "it's").
- Use the approved word, not the unapproved one:

| Do not use | Use |
|---|---|
| allow, enable | let |
| ensure, verify | make sure |
| provide, supply | give |
| require | must, is necessary |
| obtain | get |
| perform | do |
| display, indicate | show |
| determine, locate | find |
| additional | more |
| approximately | about |
| various | different |
| whether | if |
| via | through |
| utilize | use |
| e.g., i.e., etc. | for example, that is, (write the full list) |

**Sentences**

- Write procedural sentences with 20 words or fewer. Write descriptive sentences with 25 words or fewer.
- Write one topic in each sentence.
- Use the active voice. In procedures, always use the active voice.
- Use articles ("a", "the") where possible.
- Do not use noun clusters of more than three words. Break them with "of", "for" or a verb.

**Paragraphs and procedures**

- Write one topic in each paragraph. Write six sentences or fewer in each paragraph.
- Write procedures as numbered steps. Write one instruction in each step, in the imperative.
- Write a warning or a caution before the step that it applies to.
- Use vertical lists and tables for complex information.

### How we check it

`tests/docs.rkt` checks the pages in `docs/` for sentence length, unapproved words, phrasal verbs and contractions. It cannot check every STE rule. Read your text against the rules above before you commit it.

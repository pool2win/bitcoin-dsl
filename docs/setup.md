---
layout: page
title: Setup
nav_order: 5
---

# Setup for developers

1. Install Ruby using any means. I usually prefer using [RVM](https://rvm.io/)
2. Install Rust.
3. Install `miniscript-cli` by `cd miniscript-cli && cargo intall --path .`.
   This will give your DSL access to `miniscript-cli` binary.
4. Run your DSL scripts as `ruby lib/run.rb -s lib/simple.rb`


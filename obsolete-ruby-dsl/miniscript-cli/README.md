
# CLI interface to Rust Miniscript

Currently this tool provides access to compiling miniscript and
descriptors into pub key and witness programs.

## Miniscript

`miniscript-cli -m <mininscript>`

Example:

`miniscript-cli -m 'pk(038d96dcdd5811b1158cb7af6afc7eaf6086db69c57af415a36401aab8f66a8815)'`

## Descriptor

`miniscript-cli -d <descriptor>`

Example:

`miniscript-cli -d 'wpkh(02c10099720ac66a1e0945b7b34c520b7740d0d0955071c335bb24f1c9b79468c8)'`

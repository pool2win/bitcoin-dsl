// Copyright 2024 Kulpreet Singh

// This file is part of Bitcoin-DSL

// Bitcoin-DSL is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// Bitcoin-DSL is distributed in the hope that it will be useful, but
// WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
// General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with Bitcoin-DSL. If not, see <https://www.gnu.org/licenses/>.

use serde::Serialize;

/// The module contains serializable output structs that we need to
/// consume from Bitcoin DSL

/// Output used when a miniscript policy is parsed
#[derive(Serialize)]
pub struct MiniscriptOutput {
    pub address: String,
    pub witness_script: String,
    pub script_pubkey: String,
}

/// Output used when a descriptor is parsed
#[derive(Serialize)]
pub struct DescriptorOutput {
    pub address: String,
    pub witness_script: String,
    pub script_pubkey: String,
}

/// Output used for leaves for script path spends
#[derive(Serialize)]
pub struct LeafOutput {
    pub index: usize,
    pub leaf_version: String,
    pub script: String,
    pub hash: String,
}

/// Output used when a taproot descriptor with/out policy is parsed
#[derive(Serialize)]
pub struct TaprootOutput {
    pub address: String,
    pub internal_key: String,
    pub merkle_root: Option<String>,
    pub leaves: Vec<LeafOutput>,
}

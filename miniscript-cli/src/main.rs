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

use std::str::FromStr;

use bitcoin::hex::DisplayHex;
use miniscript::bitcoin::hashes::Hash;
use miniscript::policy::Concrete;
use miniscript::{bitcoin, DefiniteDescriptorKey};

use clap::Parser;

mod output;

use serde::Serialize;

use crate::output::{LeafOutput, TaprootOutput};

/// Tool to translate a Miniscript policy into Script P2WSH or inner script
/// Prints, witness pubscript key as well as Script
#[derive(Parser, Debug)]
#[command(author, version, about, long_about = None)]
struct Args {
    /// Miniscript to process
    #[arg(short, long)]
    miniscript: Option<String>,

    /// Descriptor to process
    #[arg[short, long]]
    descriptor: Option<String>,

    /// Taproot descriptor to process
    #[arg[short, long]]
    taproot: Option<String>,
}

fn main() {
    let args = Args::parse();

    if args.miniscript.is_some() {
        parse_miniscript(args);
    } else if args.descriptor.is_some() {
        parse_descriptor(args);
    } else if args.taproot.is_some() {
        parse_tr_descriptor(args);
    }
}

fn parse_miniscript(args: Args) {
    let policy =
        Concrete::<bitcoin::PublicKey>::from_str(args.miniscript.unwrap().as_str()).unwrap();

    let descriptor = miniscript::descriptor::Wsh::new(
        policy
            .compile()
            .expect("Policy compilation only fails on resource limits or mixed timelocks"),
    )
    .expect("Resource limits");

    println!("{:?}", descriptor.address(bitcoin::Network::Regtest));
    println!("{:x}", descriptor.inner_script().into_bytes().as_hex());
    println!("{}", descriptor.script_pubkey());
    println!("{}", descriptor.inner_script());
}

fn parse_descriptor(args: Args) {
    let descriptor = miniscript::Descriptor::<DefiniteDescriptorKey>::from_str(
        args.descriptor.unwrap().as_str(),
    )
    .unwrap();

    println!(
        "{:?}",
        descriptor.address(bitcoin::Network::Regtest).unwrap()
    );
    println!("{}", descriptor.script_pubkey());
    match descriptor.script_code() {
        Ok(script_code) => {
            println!("{}", script_code.into_bytes().as_hex())
        }
        Err(error) => println!("{}", error),
    };
}

fn parse_tr_descriptor(args: Args) {
    let descriptor = miniscript::descriptor::Tr::<DefiniteDescriptorKey>::from_str(
        args.taproot.unwrap().as_str(),
    )
    .unwrap();
    let merkle_root = descriptor
        .spend_info()
        .merkle_root()
        .map(|root| root.as_byte_array().to_lower_hex_string());
    let spend_info = descriptor.spend_info();
    let script_map = spend_info.script_map();
    let mut leaves: Vec<LeafOutput> = Vec::new();
    for (key, value) in script_map {
        for (index, node) in value.iter().enumerate() {
            leaves.push(LeafOutput {
                index,
                leaf_version: key.1.to_string(),
                script: key.0.to_hex_string(),
                hash: node.serialize().as_hex().to_string(),
            });
        }
    }

    let output = TaprootOutput {
        address: descriptor.address(bitcoin::Network::Regtest).to_string(),
        internal_key: descriptor.internal_key().to_string(),
        merkle_root,
        leaves,
    };

    println!("{}", serde_json::to_string(&output).unwrap());
}

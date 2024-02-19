use std::str::FromStr;

use bitcoin::hex::DisplayHex;
use miniscript::policy::Concrete;
use miniscript::{bitcoin, DefiniteDescriptorKey};

use clap::Parser;

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
}

fn main() {
    let args = Args::parse();

    if args.miniscript.is_some() {
        parse_miniscript(args);
    } else if args.descriptor.is_some() {
        parse_descriptor(args);
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
    println!("{}", descriptor.script_code().unwrap());
}

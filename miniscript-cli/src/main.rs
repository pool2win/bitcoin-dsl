use std::str::FromStr;

use miniscript::bitcoin;
use miniscript::policy::Concrete;

use clap::Parser;

/// Tool to translate a Miniscript policy into Script P2WSH or inner script
/// Prints, witness pubscript key as well as Script
#[derive(Parser, Debug)]
#[command(author, version, about, long_about = None)]
struct Args {
    /// Miniscript to process
    #[arg(short, long)]
    miniscript: String,
}

fn main() {
    let args = Args::parse();

    let policy = Concrete::<bitcoin::PublicKey>::from_str(args.miniscript.as_str()).unwrap();

    let descriptor = miniscript::descriptor::Wsh::new(
        policy
            .compile()
            .expect("Policy compilation only fails on resource limits or mixed timelocks"),
    )
    .expect("Resource limits");

    println!("{}", descriptor.inner_script());
    println!("{}", descriptor.script_pubkey());
    println!("{}", descriptor.address(bitcoin::Network::Regtest));
}

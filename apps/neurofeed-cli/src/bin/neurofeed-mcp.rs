//! `neurofeed-mcp`: compatibility name for `neurofeed-cli` that defaults to the
//! `mcp` subcommand.

#[path = "../cli.rs"]
mod cli;

fn main() {
    cli::run(true);
}

use std::io;

fn main() -> anyhow::Result<()> {
    let stdin = io::stdin();
    let stdout = io::stdout();
    let mut writer = stdout.lock();
    codexex_helper::protocol::process_stream(stdin.lock(), &mut writer)
}

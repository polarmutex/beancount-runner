use beancount_parser_lima_plugin::beancount::{InitRequest, ProcessRequest};
use beancount_parser_lima_plugin::plugin::PluginHandler;
use beancount_parser_lima_plugin::protocol::{read_message, write_message};
use std::io::{stdin, stdout};

fn main() -> std::io::Result<()> {
    let handler = PluginHandler::new();

    let mut stdin = stdin().lock();
    let mut stdout = stdout().lock();

    // Handle init
    let init_req: InitRequest = read_message(&mut stdin)?;
    let init_resp = handler.handle_init(init_req);
    write_message(&mut stdout, &init_resp)?;

    // Main process loop
    loop {
        // Try to read next message
        match read_message::<ProcessRequest, _>(&mut stdin) {
            Ok(proc_req) => {
                let proc_resp = handler.handle_process(proc_req);
                write_message(&mut stdout, &proc_resp)?;
            }
            Err(e) if e.kind() == std::io::ErrorKind::UnexpectedEof => {
                // Normal shutdown on EOF
                break;
            }
            Err(e) => {
                eprintln!("Error reading message: {}", e);
                return Err(e);
            }
        }
    }

    Ok(())
}

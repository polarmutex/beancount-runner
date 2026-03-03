use std::process::{Command, Stdio};
use std::io::Write;

#[test]
fn test_plugin_lifecycle() {
    // This test will manually drive the plugin through init -> process -> shutdown
    // Skipping for now as it requires binary to be built
}

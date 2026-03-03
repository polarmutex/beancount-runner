use std::collections::HashMap;
use beancount_parser_lima_plugin::beancount::InitRequest;
use beancount_parser_lima_plugin::plugin::PluginHandler;

fn create_init_request(name: &str, stage: &str) -> InitRequest {
    InitRequest {
        plugin_name: name.to_string(),
        pipeline_stage: stage.to_string(),
        options: HashMap::new(),
    }
}

#[test]
fn test_plugin_init() {
    let handler = PluginHandler::new();

    let init_req = create_init_request("parser", "parser");
    let init_resp = handler.handle_init(init_req);

    assert!(init_resp.success);
    assert_eq!(init_resp.plugin_version, env!("CARGO_PKG_VERSION"));
}

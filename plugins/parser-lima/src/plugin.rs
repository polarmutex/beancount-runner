use crate::beancount::{InitRequest, InitResponse, ProcessRequest, ProcessResponse};
use std::collections::HashMap;

pub struct PluginHandler {
    version: String,
}

impl PluginHandler {
    pub fn new() -> Self {
        Self {
            version: env!("CARGO_PKG_VERSION").to_string(),
        }
    }

    pub fn handle_init(&self, _request: InitRequest) -> InitResponse {
        InitResponse {
            success: true,
            error_message: String::new(),
            plugin_version: self.version.clone(),
            capabilities: HashMap::new(),
        }
    }

    pub fn handle_process(&self, _request: ProcessRequest) -> ProcessResponse {
        // TODO: Implement actual parsing
        ProcessResponse {
            directives: vec![],
            errors: vec![],
            updated_options: HashMap::new(),
        }
    }
}

use crate::beancount::{Error, InitRequest, InitResponse, ProcessRequest, ProcessResponse};
use crate::converter::convert_directive;
use beancount_parser_lima::{BeancountParser, BeancountSources};
use std::collections::HashMap;
use std::path::PathBuf;

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

    pub fn handle_process(&self, request: ProcessRequest) -> ProcessResponse {
        // Get input file from options
        let input_file = match request.options_map.get("input_file") {
            Some(path) => path,
            None => {
                return ProcessResponse {
                    directives: vec![],
                    errors: vec![Error {
                        message: "Missing input_file in options".to_string(),
                        source: "parser-lima".to_string(),
                        location: None,
                    }],
                    updated_options: HashMap::new(),
                };
            }
        };

        // Parse the beancount file
        match self.parse_file(input_file) {
            Ok((directives, warnings)) => {
                // Convert warnings to errors (non-fatal)
                let errors: Vec<Error> = warnings
                    .into_iter()
                    .map(|w| Error {
                        message: format!("Warning: {}", w),
                        source: "parser-lima".to_string(),
                        location: None,
                    })
                    .collect();

                ProcessResponse {
                    directives,
                    errors,
                    updated_options: HashMap::new(),
                }
            }
            Err(errors) => ProcessResponse {
                directives: vec![],
                errors,
                updated_options: HashMap::new(),
            },
        }
    }

    fn parse_file(&self, path: &str) -> Result<(Vec<crate::beancount::Directive>, Vec<String>), Vec<Error>> {
        // Load the file and all includes
        let sources = BeancountSources::try_from(PathBuf::from(path)).map_err(|e| {
            vec![Error {
                message: format!("Failed to read file: {}", e),
                source: "parser-lima".to_string(),
                location: None,
            }]
        })?;

        // Create parser
        let parser = BeancountParser::new(&sources);

        // Parse
        match parser.parse() {
            Ok(success) => {
                let mut directives = Vec::new();
                let mut conversion_errors = Vec::new();

                // Convert each directive
                for directive in success.directives {
                    match convert_directive(&directive) {
                        Ok(proto_directive) => directives.push(proto_directive),
                        Err(e) => conversion_errors.push(Error {
                            message: format!("Conversion error: {}", e),
                            source: "parser-lima".to_string(),
                            location: None,
                        }),
                    }
                }

                // If we had conversion errors, return them as fatal
                if !conversion_errors.is_empty() {
                    return Err(conversion_errors);
                }

                // Convert warnings to strings
                let warnings: Vec<String> = success
                    .warnings
                    .into_iter()
                    .map(|w| format!("{}", w))
                    .collect();

                Ok((directives, warnings))
            }
            Err(parse_error) => {
                // Convert parse errors to our Error type
                let errors: Vec<Error> = parse_error
                    .errors
                    .into_iter()
                    .map(|e| Error {
                        message: format!("Parse error: {}", e),
                        source: "parser-lima".to_string(),
                        location: None,
                    })
                    .collect();

                Err(errors)
            }
        }
    }
}

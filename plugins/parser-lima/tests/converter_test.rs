use beancount_parser_lima::{BeancountParser, BeancountSources};
use beancount_parser_lima_plugin::converter::convert_directive;

#[test]
fn test_simple_transaction() {
    let input = r#"
2024-01-01 * "Test" "A simple transaction"
  Assets:Cash  100.00 USD
  Expenses:Food  -100.00 USD
"#;

    let sources = BeancountSources::from(input);
    let parser = BeancountParser::new(&sources);

    match parser.parse() {
        Ok(success) => {
            assert!(!success.directives.is_empty(), "Should have directives");

            // Convert first directive
            let first = &success.directives[0];
            let result = convert_directive(first);

            assert!(result.is_ok(), "Conversion should succeed: {:?}", result);

            let directive = result.unwrap();
            assert!(
                directive.directive_type.is_some(),
                "Should have a directive type"
            );
        }
        Err(e) => {
            panic!("Parse failed: {:?}", e);
        }
    }
}

#[test]
fn test_balance_directive() {
    let input = r#"
2024-01-01 balance Assets:Cash 1000.00 USD
"#;

    let sources = BeancountSources::from(input);
    let parser = BeancountParser::new(&sources);

    match parser.parse() {
        Ok(success) => {
            assert!(!success.directives.is_empty(), "Should have directives");

            let first = &success.directives[0];
            let result = convert_directive(first);

            assert!(result.is_ok(), "Conversion should succeed");
        }
        Err(e) => {
            panic!("Parse failed: {:?}", e);
        }
    }
}

#[test]
fn test_open_directive() {
    let input = r#"
2024-01-01 open Assets:Cash USD
"#;

    let sources = BeancountSources::from(input);
    let parser = BeancountParser::new(&sources);

    match parser.parse() {
        Ok(success) => {
            assert!(!success.directives.is_empty(), "Should have directives");

            let first = &success.directives[0];
            let result = convert_directive(first);

            assert!(result.is_ok(), "Conversion should succeed");
        }
        Err(e) => {
            panic!("Parse failed: {:?}", e);
        }
    }
}

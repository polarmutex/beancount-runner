use std::io::Cursor;
use beancount_parser_lima_plugin::protocol::read_raw_message;

#[test]
fn test_read_message_simple() {
    // Create a test message: length=5, data="hello"
    let data = vec![5, 0, 0, 0, b'h', b'e', b'l', b'l', b'o'];
    let mut reader = Cursor::new(data);

    let result = read_raw_message(&mut reader).unwrap();
    assert_eq!(result, b"hello");
}

"""Tests for protobuf protocol I/O."""
import struct
from io import BytesIO
from auto_balance import read_raw_message, write_raw_message


def test_read_write_message():
    """Test basic message read/write with length prefix."""
    # Create test data
    test_data = b"hello world"

    # Write to buffer
    output = BytesIO()
    write_raw_message(output, test_data)

    # Read from buffer
    output.seek(0)
    result = read_raw_message(output)

    assert result == test_data


def test_empty_message():
    """Test empty message handling."""
    test_data = b""

    output = BytesIO()
    write_raw_message(output, test_data)

    output.seek(0)
    result = read_raw_message(output)

    assert result == test_data


def test_large_message():
    """Test large message handling."""
    # Create a large test message
    test_data = b"x" * 10000

    output = BytesIO()
    write_raw_message(output, test_data)

    output.seek(0)
    result = read_raw_message(output)

    assert result == test_data

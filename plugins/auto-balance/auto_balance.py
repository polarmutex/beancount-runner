#!/usr/bin/env python3
"""Auto-balance plugin for beancount-runner."""
import struct
import sys
from typing import BinaryIO


def read_raw_message(stream: BinaryIO) -> bytes:
    """
    Read a length-prefixed message from a binary stream.

    Protocol format:
    - 4 bytes: message length (little-endian u32)
    - N bytes: message data

    Args:
        stream: Binary input stream to read from

    Returns:
        Raw message bytes

    Raises:
        EOFError: If stream ends unexpectedly
        struct.error: If length prefix is invalid
    """
    # Read 4-byte length prefix (little-endian u32)
    length_bytes = stream.read(4)
    if len(length_bytes) < 4:
        raise EOFError("Stream ended before reading length prefix")

    # Unpack length as little-endian unsigned 32-bit integer
    length = struct.unpack('<I', length_bytes)[0]

    # Read message data
    data = stream.read(length)
    if len(data) < length:
        raise EOFError(f"Stream ended after {len(data)} bytes, expected {length}")

    return data


def write_raw_message(stream: BinaryIO, data: bytes) -> None:
    """
    Write a length-prefixed message to a binary stream.

    Protocol format:
    - 4 bytes: message length (little-endian u32)
    - N bytes: message data

    Args:
        stream: Binary output stream to write to
        data: Raw message bytes to write

    Raises:
        struct.error: If data length exceeds u32 max
        IOError: If write fails
    """
    # Pack length as little-endian unsigned 32-bit integer
    length = len(data)
    if length > 0xFFFFFFFF:
        raise ValueError(f"Message too large: {length} bytes (max: {0xFFFFFFFF})")

    length_bytes = struct.pack('<I', length)

    # Write length prefix followed by data
    stream.write(length_bytes)
    stream.write(data)
    stream.flush()


def main():
    print("Auto-balance plugin starting...")

if __name__ == "__main__":
    main()

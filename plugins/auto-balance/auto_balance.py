#!/usr/bin/env python3
"""Auto-balance plugin for beancount-runner."""
import os
import struct
import sys
from typing import BinaryIO

# Add generated protobuf code to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../../generated/python'))

import messages_pb2


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


class PluginHandler:
    """
    Handle plugin protocol lifecycle and operations.

    This class manages the Init and Process requests from the
    beancount-runner core, implementing the plugin protocol.
    """

    VERSION = "0.1.0"

    def __init__(self):
        """Initialize the plugin handler."""
        self.initialized = False
        self.options = {}

    def handle_init(self, request: messages_pb2.InitRequest) -> messages_pb2.InitResponse:
        """
        Handle plugin initialization request.

        Args:
            request: InitRequest containing plugin name, stage, and options

        Returns:
            InitResponse with success status and plugin metadata
        """
        response = messages_pb2.InitResponse()

        # Store options for later use
        self.options = dict(request.options)

        # Mark as initialized
        self.initialized = True

        # Build successful response
        response.success = True
        response.plugin_version = self.VERSION

        # Set capabilities (can be extended later)
        response.capabilities["supports_directives"] = "true"
        response.capabilities["pipeline_stage"] = request.pipeline_stage

        return response

    def handle_process(self, request: messages_pb2.ProcessRequest) -> messages_pb2.ProcessResponse:
        """
        Handle directive processing request.

        Args:
            request: ProcessRequest containing directives to process

        Returns:
            ProcessResponse with processed directives and any errors
        """
        response = messages_pb2.ProcessResponse()

        # For now, pass through all directives unchanged
        # This will be extended with actual auto-balance logic later
        response.directives.extend(request.directives)

        return response


def main():
    print("Auto-balance plugin starting...")

if __name__ == "__main__":
    main()

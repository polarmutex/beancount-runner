#!/usr/bin/env python3
"""
Python Beancount Plugin - Reference implementation of parsing+booking stages.

Demonstrates combined parsing and booking using Python's official beancount library.
"""

import sys
import struct
import logging
from pathlib import Path

# Add generated protobuf path
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "generated" / "python"))

from proto import messages_pb2, common_pb2, directives_pb2

logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)


def read_message(msg_class):
    """Read length-prefixed protobuf message from stdin."""
    length_bytes = sys.stdin.buffer.read(4)
    if len(length_bytes) < 4:
        raise EOFError("Failed to read message length")

    length = struct.unpack('<I', length_bytes)[0]
    data = sys.stdin.buffer.read(length)

    if len(data) < length:
        raise EOFError(f"Expected {length} bytes, got {len(data)}")

    msg = msg_class()
    msg.ParseFromString(data)
    return msg


def write_message(msg):
    """Write length-prefixed protobuf message to stdout."""
    data = msg.SerializeToString()
    length = struct.pack('<I', len(data))
    sys.stdout.buffer.write(length + data)
    sys.stdout.buffer.flush()


def handle_init():
    """Handle InitRequest."""
    init_req = read_message(messages_pb2.InitRequest)
    logger.info(f"Received InitRequest: protocol_version={init_req.protocol_version}")

    init_resp = messages_pb2.InitResponse(
        success=True,
        plugin_version="0.1.0",
        capabilities=["parsing", "booking"]
    )
    write_message(init_resp)
    logger.info("Sent InitResponse")

    return init_req.input_file


def handle_process(input_file):
    """Handle ProcessRequest."""
    req = read_message(messages_pb2.ProcessRequest)
    logger.info(f"Received ProcessRequest with {len(req.directives)} directives")

    # TODO: Implement parsing and booking
    # For now, return empty response
    resp = messages_pb2.ProcessResponse()
    write_message(resp)
    logger.info("Sent ProcessResponse")


def handle_shutdown():
    """Handle ShutdownRequest."""
    shutdown_req = read_message(messages_pb2.ShutdownRequest)
    logger.info("Received ShutdownRequest")

    shutdown_resp = messages_pb2.ShutdownResponse(success=True)
    write_message(shutdown_resp)
    logger.info("Sent ShutdownResponse")


def main():
    """Main plugin loop."""
    try:
        # Phase 1: Init
        input_file = handle_init()

        # Phase 2: Process
        handle_process(input_file)

        # Phase 3: Shutdown
        handle_shutdown()

    except Exception as e:
        logger.error(f"Plugin error: {e}", exc_info=True)
        sys.exit(1)


if __name__ == "__main__":
    main()

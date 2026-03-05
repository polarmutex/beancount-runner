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
import beancount.loader
from beancount.parser import booking
from beancount.core import data
import proto_conversion

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


def parse_and_book(input_file):
    """Parse and book a beancount file.

    Returns:
        tuple: (entries, errors, options) where entries are booked
    """
    logger.info(f"Parsing file: {input_file}")

    # PARSING: Load beancount file
    entries, parse_errors, options_map = beancount.loader.load_file(input_file)
    logger.info(f"Parsed {len(entries)} entries with {len(parse_errors)} errors")

    # BOOKING: Apply beancount's booking logic
    logger.info("Starting booking phase")
    booked_entries, booking_errors = booking.book(entries, options_map)
    logger.info(f"Booked {len(booked_entries)} entries with {len(booking_errors)} booking errors")

    all_errors = list(parse_errors) + list(booking_errors)

    return booked_entries, all_errors, options_map


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

    # Parse and book the beancount file
    entries, errors, options_map = parse_and_book(input_file)

    # Convert to protobuf
    pb_directives = [proto_conversion.entry_to_directive(entry) for entry in entries]
    pb_errors = [proto_conversion.error_to_protobuf(error) for error in errors]
    pb_options = proto_conversion.options_map_to_dict(options_map)

    # Build response
    resp = messages_pb2.ProcessResponse()
    resp.directives.extend(pb_directives)
    resp.errors.extend(pb_errors)
    for key, value in pb_options.items():
        resp.updated_options[key] = value

    write_message(resp)
    logger.info(f"Sent ProcessResponse with {len(pb_directives)} directives, {len(pb_errors)} errors")


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

#!/usr/bin/env python3
"""Auto-balance plugin for beancount-runner."""
import os
import struct
import sys
from typing import BinaryIO, Optional
from datetime import date, timedelta

# Add generated protobuf code to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../../generated/python'))

import messages_pb2
import directives_pb2


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

    def _find_first_balance(self, directives, account: str) -> Optional[directives_pb2.Directive]:
        """
        Find the first Balance directive for a given account.

        Args:
            directives: List of directives to search
            account: Account name to find balance for

        Returns:
            First Balance directive for the account, or None if not found
        """
        for directive in directives:
            if directive.HasField("balance") and directive.balance.account == account:
                return directive
        return None

    def _create_pad_directive(self, account: str, balance_date) -> directives_pb2.Directive:
        """
        Create a Pad directive one day before the given balance date.

        Args:
            account: Account name to pad
            balance_date: Date of the balance assertion

        Returns:
            Pad directive with date one day before balance
        """
        # Calculate pad date (one day before balance)
        bal_date = date(balance_date.year, balance_date.month, balance_date.day)
        pad_date = bal_date - timedelta(days=1)

        # Create Pad directive
        pad = directives_pb2.Directive()
        pad.pad.date.year = pad_date.year
        pad.pad.date.month = pad_date.month
        pad.pad.date.day = pad_date.day
        pad.pad.account = account
        pad.pad.source_account = "Equity:Opening-Balances"

        return pad

    def _get_directive_date(self, directive: directives_pb2.Directive) -> date:
        """
        Extract the date from any directive type.

        Args:
            directive: Directive to extract date from

        Returns:
            Date of the directive, or a default very old date for empty directives

        Raises:
            ValueError: If directive type is unknown (should not happen)
        """
        # Check each possible directive type and extract its date
        if directive.HasField("balance"):
            d = directive.balance.date
        elif directive.HasField("pad"):
            d = directive.pad.date
        elif directive.HasField("transaction"):
            d = directive.transaction.date
        elif directive.HasField("open"):
            d = directive.open.date
        elif directive.HasField("close"):
            d = directive.close.date
        elif directive.HasField("commodity"):
            d = directive.commodity.date
        elif directive.HasField("note"):
            d = directive.note.date
        elif directive.HasField("document"):
            d = directive.document.date
        elif directive.HasField("price"):
            d = directive.price.date
        elif directive.HasField("event"):
            d = directive.event.date
        elif directive.HasField("query"):
            d = directive.query.date
        elif directive.HasField("custom"):
            d = directive.custom.date
        else:
            # Empty directive - return a default very old date to put it at the beginning
            return date(1900, 1, 1)

        return date(d.year, d.month, d.day)

    def handle_process(self, request: messages_pb2.ProcessRequest) -> messages_pb2.ProcessResponse:
        """
        Handle directive processing request.

        This method implements the auto-balance logic:
        1. Find all Balance directives
        2. For each Balance, generate a Pad directive one day before
        3. Sort all directives by date

        Args:
            request: ProcessRequest containing directives to process

        Returns:
            ProcessResponse with processed directives and any errors
        """
        response = messages_pb2.ProcessResponse()

        # Collect accounts that have Balance directives
        accounts_with_balances = set()
        for directive in request.directives:
            if directive.HasField("balance"):
                accounts_with_balances.add(directive.balance.account)

        # Generate Pad directives for each account (before first Balance)
        pads_to_add = []
        for account in accounts_with_balances:
            first_balance = self._find_first_balance(request.directives, account)
            if first_balance:
                pad = self._create_pad_directive(account, first_balance.balance.date)
                pads_to_add.append(pad)

        # Combine original directives with generated Pads
        all_directives = list(request.directives) + pads_to_add

        # Sort directives by date
        all_directives.sort(key=self._get_directive_date)

        # Add sorted directives to response
        response.directives.extend(all_directives)

        return response


def main():
    print("Auto-balance plugin starting...")

if __name__ == "__main__":
    main()

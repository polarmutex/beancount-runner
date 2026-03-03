#!/usr/bin/env python3
"""Test auto-balance logic - pad directive generation."""
import os
import sys
from datetime import date

# Add generated protobuf code to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../../generated/python'))

import messages_pb2
import directives_pb2
from auto_balance import PluginHandler


def test_generates_pad_for_balance():
    """Test that a Pad directive is generated before a Balance directive."""
    handler = PluginHandler()

    # Initialize the plugin
    init_req = messages_pb2.InitRequest()
    init_req.plugin_name = "auto-balance"
    init_req.pipeline_stage = "POST_PARSE"
    init_resp = handler.handle_init(init_req)
    assert init_resp.success

    # Create a Balance directive
    balance = directives_pb2.Directive()
    balance.balance.date.year = 2024
    balance.balance.date.month = 1
    balance.balance.date.day = 15
    balance.balance.account = "Assets:Checking"
    balance.balance.amount.number = "1000.00"
    balance.balance.amount.currency = "USD"

    # Process the directive
    proc_req = messages_pb2.ProcessRequest()
    proc_req.directives.append(balance)
    proc_resp = handler.handle_process(proc_req)

    # Should return 2 directives: Pad and Balance
    assert len(proc_resp.directives) == 2, f"Expected 2 directives, got {len(proc_resp.directives)}"

    # First should be Pad directive (one day before balance)
    assert proc_resp.directives[0].HasField("pad"), "First directive should be Pad"
    pad = proc_resp.directives[0].pad
    assert pad.date.year == 2024
    assert pad.date.month == 1
    assert pad.date.day == 14  # One day before balance
    assert pad.account == "Assets:Checking"
    assert pad.source_account == "Equity:Opening-Balances"

    # Second should be original Balance directive
    assert proc_resp.directives[1].HasField("balance"), "Second directive should be Balance"
    assert proc_resp.directives[1].balance.date.year == 2024
    assert proc_resp.directives[1].balance.date.month == 1
    assert proc_resp.directives[1].balance.date.day == 15


if __name__ == "__main__":
    test_generates_pad_for_balance()
    print("All tests passed!")

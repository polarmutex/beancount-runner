"""Tests for plugin protocol handler."""
import sys
import os

# Add generated protobuf code to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../../generated/python'))

import pytest
import messages_pb2
from auto_balance import PluginHandler


def test_handle_init():
    """Test plugin initialization handling."""
    handler = PluginHandler()

    init_req = messages_pb2.InitRequest(
        plugin_name="auto-balance",
        pipeline_stage="plugin"
    )

    init_resp = handler.handle_init(init_req)

    assert init_resp.success
    assert init_resp.plugin_version == "0.1.0"


def test_handle_init_with_options():
    """Test plugin initialization with options."""
    handler = PluginHandler()

    init_req = messages_pb2.InitRequest(
        plugin_name="auto-balance",
        pipeline_stage="plugin"
    )
    init_req.options["account_pattern"] = "Assets:*"

    init_resp = handler.handle_init(init_req)

    assert init_resp.success
    assert init_resp.plugin_version == "0.1.0"


def test_handle_process_empty():
    """Test processing with empty directives."""
    handler = PluginHandler()

    # Initialize first
    init_req = messages_pb2.InitRequest(
        plugin_name="auto-balance",
        pipeline_stage="plugin"
    )
    handler.handle_init(init_req)

    # Process empty directives
    process_req = messages_pb2.ProcessRequest(
        input_file="test.beancount"
    )

    process_resp = handler.handle_process(process_req)

    assert len(process_resp.directives) == 0
    assert len(process_resp.errors) == 0


def test_handle_process_passthrough():
    """Test that directives are passed through unchanged."""
    handler = PluginHandler()

    # Initialize first
    init_req = messages_pb2.InitRequest(
        plugin_name="auto-balance",
        pipeline_stage="plugin"
    )
    handler.handle_init(init_req)

    # Create a test directive
    process_req = messages_pb2.ProcessRequest(
        input_file="test.beancount"
    )
    # Add a directive (we'll just pass through for now)
    directive = process_req.directives.add()

    process_resp = handler.handle_process(process_req)

    # Should pass through the directive
    assert len(process_resp.directives) == 1

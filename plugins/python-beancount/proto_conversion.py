"""
Conversion between beancount data types and protobuf messages.
"""

import sys
from pathlib import Path
from decimal import Decimal

# Add generated protobuf path
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "generated" / "python"))

from proto import common_pb2, directives_pb2
from beancount.core import data


def entry_to_directive(entry):
    """Convert beancount entry to protobuf Directive.

    Args:
        entry: Beancount entry (Transaction, Balance, Open, etc.)

    Returns:
        directives_pb2.Directive
    """
    # TODO: Implement full conversion
    # For now, return minimal directive
    directive = directives_pb2.Directive()

    # Set common fields
    if hasattr(entry, 'date'):
        directive.date.year = entry.date.year
        directive.date.month = entry.date.month
        directive.date.day = entry.date.day

    # Set metadata
    if hasattr(entry, 'meta') and entry.meta:
        if 'filename' in entry.meta:
            directive.meta.filename = entry.meta['filename']
        if 'lineno' in entry.meta:
            directive.meta.lineno = entry.meta['lineno']

    return directive


def error_to_protobuf(error):
    """Convert beancount error to protobuf Error.

    Args:
        error: Beancount error object

    Returns:
        common_pb2.Error
    """
    pb_error = common_pb2.Error()
    pb_error.message = str(error.message) if hasattr(error, 'message') else str(error)
    pb_error.severity = common_pb2.Error.ERROR

    if hasattr(error, 'entry') and error.entry and hasattr(error.entry, 'meta'):
        meta = error.entry.meta
        if 'filename' in meta:
            pb_error.source.filename = meta['filename']
        if 'lineno' in meta:
            pb_error.source.lineno = meta['lineno']

    return pb_error


def options_map_to_dict(options_map):
    """Convert beancount options_map to dict of strings.

    Args:
        options_map: Beancount options map

    Returns:
        dict: String key-value pairs
    """
    result = {}

    for key, value in options_map.items():
        # Convert value to string representation
        if isinstance(value, (list, tuple)):
            result[key] = ','.join(str(v) for v in value)
        else:
            result[key] = str(value)

    return result

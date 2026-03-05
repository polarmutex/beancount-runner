# Python Beancount Plugin

Reference implementation of parsing+booking stages using Python's official beancount library.

## Purpose

This plugin demonstrates:
- Combined parsing+booking stage
- Integration with Python beancount
- Amount interpolation and balance computation
- Pad directive processing

## Configuration

```toml
[[pipeline.stages]]
name = "python-beancount"
type = "external"
stage_type = "parsing+booking"
executable = "python"
args = ["./plugins/python-beancount/beancount_plugin.py"]
language = "python"
```

## Installation

```bash
cd plugins/python-beancount
pip install -r requirements.txt
```

## Testing

```bash
# Test with sample file
python beancount_plugin.py < test_input.pb > test_output.pb
```

## Architecture

1. **Parsing:** Uses `beancount.loader.load_file()` to parse beancount syntax
2. **Booking:** Uses `beancount.parser.booking.book()` to interpolate amounts
3. **Conversion:** Converts beancount entries to protobuf directives
4. **Protocol:** Implements standard plugin protocol (Init/Process/Shutdown)

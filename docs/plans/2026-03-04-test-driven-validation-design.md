# Test-Driven Validation & Text Output

**Date:** 2026-03-04
**Status:** Approved
**Approach:** Test-Driven Foundation (Approach C)

## Overview

Build balance assertion validation and text output format using a test-driven approach. Define expected behavior via test fixtures first, then implement features to pass tests.

## Goals

1. **Balance assertion validation** - Track running balances, verify assertions match calculated values
2. **Text output format** - Human-readable output for debugging and verification
3. **End-to-end test suite** - Confidence that the pipeline works correctly

## Non-Goals (YAGNI)

- Cost basis / lot tracking for investments
- Currency conversion
- Protobuf output format
- Plugin authoring documentation

## Design

### Test Infrastructure

Test file structure:
```
tests/
  fixtures/
    balance-assertions/
      simple-pass.beancount
      simple-fail.beancount
      multi-currency.beancount
    transactions/
      balanced.beancount
      unbalanced.beancount
  expected/
    balance-assertions/
      simple-pass.expected
      simple-fail.expected
  integration_test.zig
```

Each `.beancount` file is a test case with a matching `.expected` file defining expected results.

Expected file format:
```
directives: 5
errors: 0
```

Or for failure cases:
```
directives: 5
errors: 1
error[0]: Balance assertion failed: Assets:Checking expected 1000.00 USD, got 900.00 USD
```

### Balance Assertion Validation

**Algorithm:**
1. Process directives in date order
2. For each Transaction: add/subtract posting amounts to account balances
3. For each Balance directive: compare asserted amount against calculated balance
4. If mismatch exceeds tolerance (default 0.005): emit validation error

**Data structure:**
```
account_balances: HashMap(account_name, HashMap(currency, decimal))
```

**Edge cases:**
- Multiple currencies per account (tracked separately)
- Configurable tolerance (default 0.005)
- Pad directives adjust balances before same-date balance assertions
- Accounts with no transactions (balance = 0)

**Error format:**
```
Balance assertion failed at line 42: Assets:Checking
  Expected: 1000.00 USD
  Actual:   900.00 USD
  Difference: 100.00 USD
```

### Text Output Format

Human-readable format selected via `--output-format text`:

```
=== Pipeline Results ===
Input: examples/sample.beancount
Stages: parser -> auto-balance -> validator

--- Directives (18) ---

2024-01-01 open Assets:Checking USD
  [sample.beancount:1]

2024-01-15 * "Grocery Store" "Weekly groceries"
  Assets:Checking    -50.00 USD
  Expenses:Food       50.00 USD
  [sample.beancount:10]

2024-01-31 balance Assets:Checking 950.00 USD
  [sample.beancount:15]

--- Errors (1) ---

[ERROR] Balance assertion failed at sample.beancount:15
  Assets:Checking: expected 950.00 USD, got 900.00 USD
```

Properties:
- One directive per block, blank line separated
- Location in brackets for traceability
- Transactions show postings indented
- Errors at the end with clear formatting

## Implementation Order

**Phase 1: Test Infrastructure**
1. Create test fixtures directory structure
2. Write simple test cases (valid file, invalid balance)
3. Build test runner that invokes pipeline and checks results
4. Tests will fail initially (validation not implemented)

**Phase 2: Balance Validation**
1. Implement account balance tracking in validator
2. Implement balance assertion checking
3. Run tests - should start passing
4. Add edge case tests, fix issues

**Phase 3: Text Output**
1. Implement text formatter in output.zig
2. Use text output to debug any remaining test failures
3. Add text output comparison to test harness (optional)

**Phase 4: Expand Coverage**
1. Add more test fixtures for edge cases
2. Multi-currency, pad directives, date ordering
3. Ensure all paths are covered

## Files Modified

- `src/validator.zig` - balance assertion logic (~150 lines)
- `src/output.zig` - text format support (~200 lines)
- `tests/` - fixture files and test runner (~100 lines + fixtures)

## Success Criteria

- All test fixtures pass
- Balance assertions correctly validated
- Text output readable and useful for debugging
- Existing tests continue to pass

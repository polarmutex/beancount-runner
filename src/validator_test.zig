// src/validator_test.zig
const std = @import("std");
const validator = @import("validator.zig");
const testing = std.testing;

test "empty directive list passes validation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var val = validator.Validator.init(allocator);

    // Validate empty list of directives
    const result = try val.validate(&[_]Directive{});
    defer allocator.free(result.errors);

    try testing.expect(result.is_valid);
    try testing.expectEqual(@as(usize, 0), result.errors.len);
}

test "single empty directive passes validation" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create an empty directive (no transaction)
    const txn = createTestDirective(allocator);

    var val = validator.Validator.init(allocator);
    const result = try val.validate(&[_]Directive{txn});
    defer allocator.free(result.errors);

    // Empty directive should pass validation (no transaction to check)
    try testing.expect(result.is_valid);
    try testing.expectEqual(@as(usize, 0), result.errors.len);
}

fn createTestDirective(allocator: std.mem.Allocator) Directive {
    _ = allocator;
    // Create a minimal test transaction
    return Directive{
        .directive_type = .{
            .transaction = proto.Transaction{
                .date = proto.Date{ .year = 2024, .month = 1, .day = 1 },
                .flag = null,
                .payee = null,
                .narration = "",
                .tags = &[_][]const u8{},
                .links = &[_][]const u8{},
                .postings = &[_]proto.Posting{},
                .location = proto.Location{ .filename = "", .line = 0, .column = 0 },
            },
        },
    };
}

// Import Directive from proto module
const proto = @import("proto.zig");
const Directive = proto.Directive;

test "balance assertion passes when balance matches" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create directives:  open accounts, balanced transaction, balance assertion
    const directives = [_]Directive{
        // Open Assets:Checking
        Directive{
            .directive_type = .{
                .open = proto.Open{
                    .date = proto.Date{ .year = 2024, .month = 1, .day = 1 },
                    .account = "Assets:Checking",
                    .currencies = @constCast(&[_][]const u8{"USD"}),
                    .location = proto.Location{ .filename = "test.beancount", .line = 1, .column = 0 },
                },
            },
        },
        // Open Equity:Opening
        Directive{
            .directive_type = .{
                .open = proto.Open{
                    .date = proto.Date{ .year = 2024, .month = 1, .day = 1 },
                    .account = "Equity:Opening",
                    .currencies = @constCast(&[_][]const u8{"USD"}),
                    .location = proto.Location{ .filename = "test.beancount", .line = 2, .column = 0 },
                },
            },
        },
        // Transaction: balanced (Assets +1000, Equity -1000)
        Directive{
            .directive_type = .{
                .transaction = proto.Transaction{
                    .date = proto.Date{ .year = 2024, .month = 1, .day = 2 },
                    .flag = null,
                    .payee = null,
                    .narration = "Opening balance",
                    .tags = &[_][]const u8{},
                    .links = &[_][]const u8{},
                    .postings = @constCast(&[_]proto.Posting{
                        proto.Posting{
                            .account = "Assets:Checking",
                            .amount = proto.Amount{ .number = "1000.00", .currency = "USD" },
                            .cost = null,
                            .price = null,
                            .flag = null,
                        },
                        proto.Posting{
                            .account = "Equity:Opening",
                            .amount = proto.Amount{ .number = "-1000.00", .currency = "USD" },
                            .cost = null,
                            .price = null,
                            .flag = null,
                        },
                    }),
                    .location = proto.Location{ .filename = "test.beancount", .line = 3, .column = 0 },
                },
            },
        },
        // Balance assertion: should be 1000 USD
        Directive{
            .directive_type = .{
                .balance = proto.Balance{
                    .date = proto.Date{ .year = 2024, .month = 1, .day = 3 },
                    .account = "Assets:Checking",
                    .amount = proto.Amount{ .number = "1000.00", .currency = "USD" },
                    .location = proto.Location{ .filename = "test.beancount", .line = 7, .column = 0 },
                },
            },
        },
    };

    var val = validator.Validator.init(allocator);
    const result = try val.validate(&directives);
    defer allocator.free(result.errors);

    // Should pass - balance matches
    try testing.expect(result.is_valid);
    try testing.expectEqual(@as(usize, 0), result.errors.len);
}

test "balance assertion fails when balance doesn't match" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Create directives: open accounts, balanced transactions, incorrect balance assertion
    const directives = [_]Directive{
        // Open Assets:Checking
        Directive{
            .directive_type = .{
                .open = proto.Open{
                    .date = proto.Date{ .year = 2024, .month = 1, .day = 1 },
                    .account = "Assets:Checking",
                    .currencies = @constCast(&[_][]const u8{"USD"}),
                    .location = proto.Location{ .filename = "test.beancount", .line = 1, .column = 0 },
                },
            },
        },
        // Open Equity:Opening
        Directive{
            .directive_type = .{
                .open = proto.Open{
                    .date = proto.Date{ .year = 2024, .month = 1, .day = 1 },
                    .account = "Equity:Opening",
                    .currencies = @constCast(&[_][]const u8{"USD"}),
                    .location = proto.Location{ .filename = "test.beancount", .line = 2, .column = 0 },
                },
            },
        },
        // Open Expenses:Food
        Directive{
            .directive_type = .{
                .open = proto.Open{
                    .date = proto.Date{ .year = 2024, .month = 1, .day = 1 },
                    .account = "Expenses:Food",
                    .currencies = @constCast(&[_][]const u8{"USD"}),
                    .location = proto.Location{ .filename = "test.beancount", .line = 3, .column = 0 },
                },
            },
        },
        // Transaction: balanced (Assets +1000, Equity -1000)
        Directive{
            .directive_type = .{
                .transaction = proto.Transaction{
                    .date = proto.Date{ .year = 2024, .month = 1, .day = 2 },
                    .flag = null,
                    .payee = null,
                    .narration = "Opening balance",
                    .tags = &[_][]const u8{},
                    .links = &[_][]const u8{},
                    .postings = @constCast(&[_]proto.Posting{
                        proto.Posting{
                            .account = "Assets:Checking",
                            .amount = proto.Amount{ .number = "1000.00", .currency = "USD" },
                            .cost = null,
                            .price = null,
                            .flag = null,
                        },
                        proto.Posting{
                            .account = "Equity:Opening",
                            .amount = proto.Amount{ .number = "-1000.00", .currency = "USD" },
                            .cost = null,
                            .price = null,
                            .flag = null,
                        },
                    }),
                    .location = proto.Location{ .filename = "test.beancount", .line = 5, .column = 0 },
                },
            },
        },
        // Transaction: balanced (Assets -50, Expenses +50)
        Directive{
            .directive_type = .{
                .transaction = proto.Transaction{
                    .date = proto.Date{ .year = 2024, .month = 1, .day = 15 },
                    .flag = null,
                    .payee = null,
                    .narration = "Groceries",
                    .tags = &[_][]const u8{},
                    .links = &[_][]const u8{},
                    .postings = @constCast(&[_]proto.Posting{
                        proto.Posting{
                            .account = "Assets:Checking",
                            .amount = proto.Amount{ .number = "-50.00", .currency = "USD" },
                            .cost = null,
                            .price = null,
                            .flag = null,
                        },
                        proto.Posting{
                            .account = "Expenses:Food",
                            .amount = proto.Amount{ .number = "50.00", .currency = "USD" },
                            .cost = null,
                            .price = null,
                            .flag = null,
                        },
                    }),
                    .location = proto.Location{ .filename = "test.beancount", .line = 10, .column = 0 },
                },
            },
        },
        // Balance assertion: expects 1000 USD, but actual is 950 USD
        Directive{
            .directive_type = .{
                .balance = proto.Balance{
                    .date = proto.Date{ .year = 2024, .month = 1, .day = 31 },
                    .account = "Assets:Checking",
                    .amount = proto.Amount{ .number = "1000.00", .currency = "USD" },
                    .location = proto.Location{ .filename = "test.beancount", .line = 15, .column = 0 },
                },
            },
        },
    };

    var val = validator.Validator.init(allocator);
    const result = try val.validate(&directives);
    defer allocator.free(result.errors);

    // Should fail - balance doesn't match
    try testing.expect(!result.is_valid);
    try testing.expectEqual(@as(usize, 1), result.errors.len);

    // Check error message contains relevant info
    const error_msg = result.errors[0].message;
    try testing.expect(std.mem.indexOf(u8, error_msg, "Balance assertion failed") != null);
    try testing.expect(std.mem.indexOf(u8, error_msg, "Assets:Checking") != null);
    try testing.expect(std.mem.indexOf(u8, error_msg, "1000.00") != null);
    try testing.expect(std.mem.indexOf(u8, error_msg, "950.00") != null);
}

test "balance assertion with multiple currencies" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Test that balance assertions work correctly with multiple currencies in the same account
    const directives = [_]Directive{
        // Open Assets:Cash
        Directive{
            .directive_type = .{
                .open = proto.Open{
                    .date = proto.Date{ .year = 2024, .month = 1, .day = 1 },
                    .account = "Assets:Cash",
                    .currencies = @constCast(&[_][]const u8{ "USD", "EUR" }),
                    .location = proto.Location{ .filename = "test.beancount", .line = 1, .column = 0 },
                },
            },
        },
        // Open Equity:Opening
        Directive{
            .directive_type = .{
                .open = proto.Open{
                    .date = proto.Date{ .year = 2024, .month = 1, .day = 1 },
                    .account = "Equity:Opening",
                    .currencies = @constCast(&[_][]const u8{ "USD", "EUR" }),
                    .location = proto.Location{ .filename = "test.beancount", .line = 2, .column = 0 },
                },
            },
        },
        // Transaction: Add USD
        Directive{
            .directive_type = .{
                .transaction = proto.Transaction{
                    .date = proto.Date{ .year = 2024, .month = 1, .day = 2 },
                    .flag = null,
                    .payee = null,
                    .narration = "Opening balance USD",
                    .tags = &[_][]const u8{},
                    .links = &[_][]const u8{},
                    .postings = @constCast(&[_]proto.Posting{
                        proto.Posting{
                            .account = "Assets:Cash",
                            .amount = proto.Amount{ .number = "1000.00", .currency = "USD" },
                            .cost = null,
                            .price = null,
                            .flag = null,
                        },
                        proto.Posting{
                            .account = "Equity:Opening",
                            .amount = proto.Amount{ .number = "-1000.00", .currency = "USD" },
                            .cost = null,
                            .price = null,
                            .flag = null,
                        },
                    }),
                    .location = proto.Location{ .filename = "test.beancount", .line = 3, .column = 0 },
                },
            },
        },
        // Transaction: Add EUR
        Directive{
            .directive_type = .{
                .transaction = proto.Transaction{
                    .date = proto.Date{ .year = 2024, .month = 1, .day = 3 },
                    .flag = null,
                    .payee = null,
                    .narration = "Opening balance EUR",
                    .tags = &[_][]const u8{},
                    .links = &[_][]const u8{},
                    .postings = @constCast(&[_]proto.Posting{
                        proto.Posting{
                            .account = "Assets:Cash",
                            .amount = proto.Amount{ .number = "500.00", .currency = "EUR" },
                            .cost = null,
                            .price = null,
                            .flag = null,
                        },
                        proto.Posting{
                            .account = "Equity:Opening",
                            .amount = proto.Amount{ .number = "-500.00", .currency = "EUR" },
                            .cost = null,
                            .price = null,
                            .flag = null,
                        },
                    }),
                    .location = proto.Location{ .filename = "test.beancount", .line = 7, .column = 0 },
                },
            },
        },
        // Balance assertion: USD
        Directive{
            .directive_type = .{
                .balance = proto.Balance{
                    .date = proto.Date{ .year = 2024, .month = 1, .day = 10 },
                    .account = "Assets:Cash",
                    .amount = proto.Amount{ .number = "1000.00", .currency = "USD" },
                    .location = proto.Location{ .filename = "test.beancount", .line = 11, .column = 0 },
                },
            },
        },
        // Balance assertion: EUR
        Directive{
            .directive_type = .{
                .balance = proto.Balance{
                    .date = proto.Date{ .year = 2024, .month = 1, .day = 10 },
                    .account = "Assets:Cash",
                    .amount = proto.Amount{ .number = "500.00", .currency = "EUR" },
                    .location = proto.Location{ .filename = "test.beancount", .line = 12, .column = 0 },
                },
            },
        },
    };

    var val = validator.Validator.init(allocator);
    const result = try val.validate(&directives);
    defer allocator.free(result.errors);

    // Should pass - both currency balances are correct
    try testing.expect(result.is_valid);
    try testing.expectEqual(@as(usize, 0), result.errors.len);
}

test "balance assertion with zero balance for missing currency" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Test that accounts with no transactions for a currency have balance 0
    const directives = [_]Directive{
        // Open Assets:Checking
        Directive{
            .directive_type = .{
                .open = proto.Open{
                    .date = proto.Date{ .year = 2024, .month = 1, .day = 1 },
                    .account = "Assets:Checking",
                    .currencies = @constCast(&[_][]const u8{"USD"}),
                    .location = proto.Location{ .filename = "test.beancount", .line = 1, .column = 0 },
                },
            },
        },
        // Balance assertion for account that has no transactions (should be 0)
        Directive{
            .directive_type = .{
                .balance = proto.Balance{
                    .date = proto.Date{ .year = 2024, .month = 1, .day = 10 },
                    .account = "Assets:Checking",
                    .amount = proto.Amount{ .number = "0.00", .currency = "USD" },
                    .location = proto.Location{ .filename = "test.beancount", .line = 3, .column = 0 },
                },
            },
        },
    };

    var val = validator.Validator.init(allocator);
    const result = try val.validate(&directives);
    defer allocator.free(result.errors);

    // Should pass - balance is correctly 0
    try testing.expect(result.is_valid);
    try testing.expectEqual(@as(usize, 0), result.errors.len);
}

test "balance assertion within tolerance" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Test that small differences within tolerance (0.005) pass
    const directives = [_]Directive{
        // Open accounts
        Directive{
            .directive_type = .{
                .open = proto.Open{
                    .date = proto.Date{ .year = 2024, .month = 1, .day = 1 },
                    .account = "Assets:Checking",
                    .currencies = @constCast(&[_][]const u8{"USD"}),
                    .location = proto.Location{ .filename = "test.beancount", .line = 1, .column = 0 },
                },
            },
        },
        Directive{
            .directive_type = .{
                .open = proto.Open{
                    .date = proto.Date{ .year = 2024, .month = 1, .day = 1 },
                    .account = "Equity:Opening",
                    .currencies = @constCast(&[_][]const u8{"USD"}),
                    .location = proto.Location{ .filename = "test.beancount", .line = 2, .column = 0 },
                },
            },
        },
        // Transaction with rounding: 1000.003
        Directive{
            .directive_type = .{
                .transaction = proto.Transaction{
                    .date = proto.Date{ .year = 2024, .month = 1, .day = 2 },
                    .flag = null,
                    .payee = null,
                    .narration = "Opening",
                    .tags = &[_][]const u8{},
                    .links = &[_][]const u8{},
                    .postings = @constCast(&[_]proto.Posting{
                        proto.Posting{
                            .account = "Assets:Checking",
                            .amount = proto.Amount{ .number = "1000.003", .currency = "USD" },
                            .cost = null,
                            .price = null,
                            .flag = null,
                        },
                        proto.Posting{
                            .account = "Equity:Opening",
                            .amount = proto.Amount{ .number = "-1000.003", .currency = "USD" },
                            .cost = null,
                            .price = null,
                            .flag = null,
                        },
                    }),
                    .location = proto.Location{ .filename = "test.beancount", .line = 3, .column = 0 },
                },
            },
        },
        // Balance assertion: 1000.00 (diff = 0.003, within tolerance of 0.005)
        Directive{
            .directive_type = .{
                .balance = proto.Balance{
                    .date = proto.Date{ .year = 2024, .month = 1, .day = 10 },
                    .account = "Assets:Checking",
                    .amount = proto.Amount{ .number = "1000.00", .currency = "USD" },
                    .location = proto.Location{ .filename = "test.beancount", .line = 7, .column = 0 },
                },
            },
        },
    };

    var val = validator.Validator.init(allocator);
    const result = try val.validate(&directives);
    defer allocator.free(result.errors);

    // Should pass - difference is within tolerance
    try testing.expect(result.is_valid);
    try testing.expectEqual(@as(usize, 0), result.errors.len);
}

test "balance assertion with multiple transactions same date" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Test that multiple transactions on the same date are all included in balance
    const directives = [_]Directive{
        // Open accounts
        Directive{
            .directive_type = .{
                .open = proto.Open{
                    .date = proto.Date{ .year = 2024, .month = 1, .day = 1 },
                    .account = "Assets:Checking",
                    .currencies = @constCast(&[_][]const u8{"USD"}),
                    .location = proto.Location{ .filename = "test.beancount", .line = 1, .column = 0 },
                },
            },
        },
        Directive{
            .directive_type = .{
                .open = proto.Open{
                    .date = proto.Date{ .year = 2024, .month = 1, .day = 1 },
                    .account = "Equity:Opening",
                    .currencies = @constCast(&[_][]const u8{"USD"}),
                    .location = proto.Location{ .filename = "test.beancount", .line = 2, .column = 0 },
                },
            },
        },
        Directive{
            .directive_type = .{
                .open = proto.Open{
                    .date = proto.Date{ .year = 2024, .month = 1, .day = 1 },
                    .account = "Expenses:Food",
                    .currencies = @constCast(&[_][]const u8{"USD"}),
                    .location = proto.Location{ .filename = "test.beancount", .line = 3, .column = 0 },
                },
            },
        },
        // Transaction 1: +1000
        Directive{
            .directive_type = .{
                .transaction = proto.Transaction{
                    .date = proto.Date{ .year = 2024, .month = 1, .day = 5 },
                    .flag = null,
                    .payee = null,
                    .narration = "Opening",
                    .tags = &[_][]const u8{},
                    .links = &[_][]const u8{},
                    .postings = @constCast(&[_]proto.Posting{
                        proto.Posting{
                            .account = "Assets:Checking",
                            .amount = proto.Amount{ .number = "1000.00", .currency = "USD" },
                            .cost = null,
                            .price = null,
                            .flag = null,
                        },
                        proto.Posting{
                            .account = "Equity:Opening",
                            .amount = proto.Amount{ .number = "-1000.00", .currency = "USD" },
                            .cost = null,
                            .price = null,
                            .flag = null,
                        },
                    }),
                    .location = proto.Location{ .filename = "test.beancount", .line = 4, .column = 0 },
                },
            },
        },
        // Transaction 2: -50 (same date)
        Directive{
            .directive_type = .{
                .transaction = proto.Transaction{
                    .date = proto.Date{ .year = 2024, .month = 1, .day = 5 },
                    .flag = null,
                    .payee = null,
                    .narration = "Purchase",
                    .tags = &[_][]const u8{},
                    .links = &[_][]const u8{},
                    .postings = @constCast(&[_]proto.Posting{
                        proto.Posting{
                            .account = "Assets:Checking",
                            .amount = proto.Amount{ .number = "-50.00", .currency = "USD" },
                            .cost = null,
                            .price = null,
                            .flag = null,
                        },
                        proto.Posting{
                            .account = "Expenses:Food",
                            .amount = proto.Amount{ .number = "50.00", .currency = "USD" },
                            .cost = null,
                            .price = null,
                            .flag = null,
                        },
                    }),
                    .location = proto.Location{ .filename = "test.beancount", .line = 8, .column = 0 },
                },
            },
        },
        // Transaction 3: -100 (same date)
        Directive{
            .directive_type = .{
                .transaction = proto.Transaction{
                    .date = proto.Date{ .year = 2024, .month = 1, .day = 5 },
                    .flag = null,
                    .payee = null,
                    .narration = "Another purchase",
                    .tags = &[_][]const u8{},
                    .links = &[_][]const u8{},
                    .postings = @constCast(&[_]proto.Posting{
                        proto.Posting{
                            .account = "Assets:Checking",
                            .amount = proto.Amount{ .number = "-100.00", .currency = "USD" },
                            .cost = null,
                            .price = null,
                            .flag = null,
                        },
                        proto.Posting{
                            .account = "Expenses:Food",
                            .amount = proto.Amount{ .number = "100.00", .currency = "USD" },
                            .cost = null,
                            .price = null,
                            .flag = null,
                        },
                    }),
                    .location = proto.Location{ .filename = "test.beancount", .line = 12, .column = 0 },
                },
            },
        },
        // Balance assertion after all transactions: 1000 - 50 - 100 = 850
        Directive{
            .directive_type = .{
                .balance = proto.Balance{
                    .date = proto.Date{ .year = 2024, .month = 1, .day = 6 },
                    .account = "Assets:Checking",
                    .amount = proto.Amount{ .number = "850.00", .currency = "USD" },
                    .location = proto.Location{ .filename = "test.beancount", .line = 16, .column = 0 },
                },
            },
        },
    };

    var val = validator.Validator.init(allocator);
    const result = try val.validate(&directives);
    defer allocator.free(result.errors);

    // Should pass - all transactions on same date are included
    try testing.expect(result.is_valid);
    try testing.expectEqual(@as(usize, 0), result.errors.len);
}

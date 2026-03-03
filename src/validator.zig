const std = @import("std");
const proto = @import("proto.zig");

pub const Validator = struct {
    allocator: std.mem.Allocator,
    tolerance: f64,

    pub fn init(allocator: std.mem.Allocator) Validator {
        return .{
            .allocator = allocator,
            .tolerance = 0.005, // Default tolerance
        };
    }

    pub fn validate(
        self: *Validator,
        directives: []const proto.Directive,
    ) !ValidationResult {
        var errors: std.ArrayList(proto.Error) = .empty;
        defer errors.deinit(self.allocator);

        // Core validation 1: Transaction balancing
        try self.validateTransactionBalances(directives, &errors);

        // Core validation 2: Account open before use
        try self.validateAccountUsage(directives, &errors);

        // Core validation 3: Balance assertions positioned correctly
        try self.validateBalanceAssertions(directives, &errors);

        // Core validation 4: Date ordering
        try self.validateDateOrdering(directives, &errors);

        return ValidationResult{
            .is_valid = errors.items.len == 0,
            .errors = try errors.toOwnedSlice(self.allocator),
        };
    }

    fn validateTransactionBalances(
        self: *Validator,
        directives: []const proto.Directive,
        errors: *std.ArrayList(proto.Error),
    ) !void {
        for (directives) |directive| {
            // Skip if not a transaction
            if (!directive.hasTransaction()) continue;

            const txn = directive.getTransaction();

            // Track balance per currency
            var balance_map = std.StringHashMap(f64).init(self.allocator);
            defer balance_map.deinit();

            // Sum all postings
            for (txn.postings) |posting| {
                if (posting.amount) |amount| {
                    const value = try parseAmount(amount.number);
                    const currency = amount.currency;

                    const entry = try balance_map.getOrPut(currency);
                    if (!entry.found_existing) {
                        entry.value_ptr.* = 0;
                    }
                    entry.value_ptr.* += value;
                }
            }

            // Check each currency balances to zero
            var iter = balance_map.iterator();
            while (iter.next()) |entry| {
                const balance = entry.value_ptr.*;
                if (@abs(balance) > self.tolerance) {
                    try errors.append(self.allocator, proto.Error{
                        .message = try std.fmt.allocPrint(
                            self.allocator,
                            "Transaction does not balance: {s} off by {d:.2}",
                            .{ entry.key_ptr.*, balance },
                        ),
                        .source = try self.allocator.dupe(u8, "validator"),
                    });
                }
            }
        }
    }

    fn parseAmount(number_str: []const u8) !f64 {
        return std.fmt.parseFloat(f64, number_str) catch |err| {
            std.debug.print("Failed to parse amount: {s}\n", .{number_str});
            return err;
        };
    }

    fn validateAccountUsage(
        self: *Validator,
        directives: []const proto.Directive,
        errors: *std.ArrayList(proto.Error),
    ) !void {
        // Track opened accounts with their dates
        var open_accounts = std.StringHashMap(proto.Date).init(self.allocator);
        defer {
            var iter = open_accounts.keyIterator();
            while (iter.next()) |key| {
                self.allocator.free(key.*);
            }
            open_accounts.deinit();
        }

        for (directives) |directive| {
            // Record Open directives
            if (directive.hasOpen()) {
                const open = directive.getOpen();
                try open_accounts.put(
                    try self.allocator.dupe(u8, open.account),
                    open.date,
                );
            }

            // Check Transaction postings
            if (directive.hasTransaction()) {
                const txn = directive.getTransaction();

                for (txn.postings) |posting| {
                    if (!open_accounts.contains(posting.account)) {
                        try errors.append(self.allocator, proto.Error{
                            .message = try std.fmt.allocPrint(
                                self.allocator,
                                "Account '{s}' used before being opened",
                                .{posting.account},
                            ),
                            .source = try self.allocator.dupe(u8, "validator"),
                        });
                    } else {
                        // Verify transaction date >= open date
                        const open_date = open_accounts.get(posting.account).?;
                        if (compareDates(txn.date, open_date) < 0) {
                            try errors.append(self.allocator, proto.Error{
                                .message = try std.fmt.allocPrint(
                                    self.allocator,
                                    "Account '{s}' used on {d}-{d:0>2}-{d:0>2} before open date {d}-{d:0>2}-{d:0>2}",
                                    .{
                                        posting.account,
                                        txn.date.year,
                                        txn.date.month,
                                        txn.date.day,
                                        open_date.year,
                                        open_date.month,
                                        open_date.day,
                                    },
                                ),
                                .source = try self.allocator.dupe(u8, "validator"),
                            });
                        }
                    }
                }
            }

            // Also check Balance directives
            if (directive.hasBalance()) {
                const bal = directive.getBalance();
                if (!open_accounts.contains(bal.account)) {
                    try errors.append(self.allocator, proto.Error{
                        .message = try std.fmt.allocPrint(
                            self.allocator,
                            "Balance assertion for unopened account '{s}'",
                            .{bal.account},
                        ),
                        .source = try self.allocator.dupe(u8, "validator"),
                    });
                }
            }
        }
    }

    fn compareDates(a: proto.Date, b: proto.Date) i32 {
        if (a.year != b.year) return a.year - b.year;
        if (a.month != b.month) return a.month - b.month;
        return a.day - b.day;
    }

    fn validateBalanceAssertions(
        self: *Validator,
        directives: []const proto.Directive,
        errors: *std.ArrayList(proto.Error),
    ) !void {
        _ = self;
        _ = directives;
        _ = errors;
        // TODO: Implement balance assertion validation
        // - Track running balances per account
        // - Verify balance assertions match calculated values
    }

    fn validateDateOrdering(
        self: *Validator,
        directives: []const proto.Directive,
        errors: *std.ArrayList(proto.Error),
    ) !void {
        if (directives.len == 0) return;

        var prev_date: ?proto.Date = null;

        for (directives, 0..) |directive, idx| {
            const current_date = getDirectiveDate(directive) orelse continue;

            if (prev_date) |prev| {
                const cmp = compareDates(current_date, prev);
                if (cmp < 0) {
                    try errors.append(self.allocator, proto.Error{
                        .message = try std.fmt.allocPrint(
                            self.allocator,
                            "Directive at index {d} is out of order: {d}-{d:0>2}-{d:0>2} comes after {d}-{d:0>2}-{d:0>2}",
                            .{
                                idx,
                                current_date.year,
                                current_date.month,
                                current_date.day,
                                prev.year,
                                prev.month,
                                prev.day,
                            },
                        ),
                        .source = try self.allocator.dupe(u8, "validator"),
                    });
                }
            }

            prev_date = current_date;
        }
    }

    fn getDirectiveDate(directive: proto.Directive) ?proto.Date {
        if (directive.hasTransaction()) {
            return directive.getTransaction().date;
        }
        if (directive.hasOpen()) {
            return directive.getOpen().date;
        }
        if (directive.hasBalance()) {
            return directive.getBalance().date;
        }
        if (directive.hasClose()) {
            return directive.getClose().date;
        }
        if (directive.hasPad()) {
            return directive.getPad().date;
        }
        // Other directive types may not have dates
        return null;
    }
};

pub const ValidationResult = struct {
    is_valid: bool,
    errors: []proto.Error,
};

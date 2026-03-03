const std = @import("std");

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
        directives: []const Directive,
    ) !ValidationResult {
        const ErrorList = std.ArrayList(Error);
        var errors: ErrorList = .empty;
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
        directives: []const Directive,
        errors: *std.ArrayList(Error),
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
                    try errors.append(self.allocator, Error{
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
        directives: []const Directive,
        errors: *std.ArrayList(Error),
    ) !void {
        _ = self;
        _ = directives;
        _ = errors;
        // TODO: Implement account usage validation
        // - Track Open directives and their dates
        // - For each account usage, verify it was opened
        // - Verify usage date >= open date
    }

    fn validateBalanceAssertions(
        self: *Validator,
        directives: []const Directive,
        errors: *std.ArrayList(Error),
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
        directives: []const Directive,
        errors: *std.ArrayList(Error),
    ) !void {
        _ = self;
        _ = directives;
        _ = errors;
        // TODO: Implement date ordering validation
        // - Verify directives are sorted by date
        // - Use line number as secondary sort key
    }
};

pub const ValidationResult = struct {
    is_valid: bool,
    errors: []Error,
};

// Placeholder types (will be replaced with protobuf-generated types)
// These provide the interface needed for validation logic
pub const Directive = struct {
    fn hasTransaction(self: Directive) bool {
        _ = self;
        return false; // Stub implementation
    }

    fn getTransaction(self: Directive) Transaction {
        _ = self;
        return Transaction{ .postings = &[_]Posting{} };
    }

    fn hasOpen(self: Directive) bool {
        _ = self;
        return false;
    }

    fn getOpen(self: Directive) Open {
        _ = self;
        return undefined;
    }
};

const Transaction = struct {
    postings: []const Posting,
};

const Posting = struct {
    amount: ?Amount,
};

const Amount = struct {
    number: []const u8,
    currency: []const u8,
};

const Open = struct {
    account: []const u8,
    date: Date,
};

const Date = struct {
    year: i32,
    month: u8,
    day: u8,
};

pub const Error = struct {
    message: []const u8,
    source: []const u8,
};

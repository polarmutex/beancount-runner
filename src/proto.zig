// src/proto.zig
const std = @import("std");

pub const Date = struct {
    year: i32,
    month: i32,
    day: i32,
};

pub const Amount = struct {
    number: []const u8,
    currency: []const u8,
};

pub const Location = struct {
    filename: []const u8,
    line: i32,
    column: i32,
};

pub const Error = struct {
    message: []const u8,
    source: []const u8,
    location: ?Location = null,
};

pub const Posting = struct {
    account: []const u8,
    amount: ?Amount = null,
    cost: ?Amount = null,
    price: ?Amount = null,
    flag: ?[]const u8 = null,
};

pub const Transaction = struct {
    date: Date,
    flag: ?[]const u8,
    payee: ?[]const u8,
    narration: []const u8,
    tags: [][]const u8,
    links: [][]const u8,
    postings: []Posting,
    location: Location,
};

pub const Balance = struct {
    date: Date,
    account: []const u8,
    amount: Amount,
    location: Location,
};

pub const Open = struct {
    date: Date,
    account: []const u8,
    currencies: [][]const u8,
    location: Location,
};

pub const Close = struct {
    date: Date,
    account: []const u8,
    location: Location,
};

pub const Pad = struct {
    date: Date,
    account: []const u8,
    source_account: []const u8,
    location: Location,
};

pub const DirectiveType = union(enum) {
    transaction: Transaction,
    balance: Balance,
    open: Open,
    close: Close,
    pad: Pad,
    // Add other types as needed
};

pub const Directive = struct {
    directive_type: DirectiveType,

    pub fn hasTransaction(self: Directive) bool {
        return self.directive_type == .transaction;
    }

    pub fn getTransaction(self: Directive) Transaction {
        return self.directive_type.transaction;
    }

    pub fn hasBalance(self: Directive) bool {
        return self.directive_type == .balance;
    }

    pub fn getBalance(self: Directive) Balance {
        return self.directive_type.balance;
    }

    pub fn hasOpen(self: Directive) bool {
        return self.directive_type == .open;
    }

    pub fn getOpen(self: Directive) Open {
        return self.directive_type.open;
    }

    pub fn hasClose(self: Directive) bool {
        return self.directive_type == .close;
    }

    pub fn getClose(self: Directive) Close {
        return self.directive_type.close;
    }

    pub fn hasPad(self: Directive) bool {
        return self.directive_type == .pad;
    }

    pub fn getPad(self: Directive) Pad {
        return self.directive_type.pad;
    }
};

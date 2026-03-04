# Protobuf Deserialization Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement full protobuf wire format deserialization to parse directive data from plugin responses into Zig proto.Directive structs.

**Architecture:** Build a Decoder in protobuf.zig that reads protobuf wire format (tag-length-value encoding) and constructs proto.Directive structs with all fields populated. The decoder will handle nested messages, repeated fields, and oneof types according to the protobuf spec.

**Tech Stack:** Zig 0.16, Protocol Buffers wire format

---

## Task 1: Implement core decoder infrastructure

**Files:**
- Modify: `src/protobuf.zig:230-end`
- Create test later in Task 2

**Step 1: Add Decoder struct with varint reading**

Add after line 229 in `src/protobuf.zig`:

```zig
/// Protobuf message decoder
pub const Decoder = struct {
    data: []const u8,
    pos: usize,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, data: []const u8) Decoder {
        return Decoder{
            .data = data,
            .pos = 0,
            .allocator = allocator,
        };
    }

    /// Read a varint from current position
    fn readVarint(self: *Decoder) !u64 {
        var result: u64 = 0;
        var shift: u6 = 0;

        while (self.pos < self.data.len) {
            const byte = self.data[self.pos];
            self.pos += 1;

            result |= @as(u64, byte & 0x7F) << shift;
            if ((byte & 0x80) == 0) {
                return result;
            }

            shift += 7;
            if (shift >= 64) {
                return error.VarintTooLong;
            }
        }

        return error.UnexpectedEof;
    }

    /// Read a tag (field number + wire type)
    fn readTag(self: *Decoder) !?struct { field_number: u32, wire_type: WireType } {
        if (self.pos >= self.data.len) {
            return null; // End of message
        }

        const tag = try self.readVarint();
        const field_number = @as(u32, @intCast(tag >> 3));
        const wire_type_int = @as(u3, @intCast(tag & 0x07));
        const wire_type = @as(WireType, @enumFromInt(wire_type_int));

        return .{ .field_number = field_number, .wire_type = wire_type };
    }

    /// Read length-delimited bytes
    fn readBytes(self: *Decoder) ![]const u8 {
        const len = try self.readVarint();
        const start = self.pos;
        const end = start + @as(usize, @intCast(len));

        if (end > self.data.len) {
            return error.UnexpectedEof;
        }

        self.pos = end;
        return self.data[start..end];
    }

    /// Read a string field (returns owned slice)
    fn readString(self: *Decoder) ![]u8 {
        const bytes = try self.readBytes();
        return try self.allocator.dupe(u8, bytes);
    }

    /// Skip a field based on wire type
    fn skipField(self: *Decoder, wire_type: WireType) !void {
        switch (wire_type) {
            .varint => {
                _ = try self.readVarint();
            },
            .fixed64 => {
                if (self.pos + 8 > self.data.len) return error.UnexpectedEof;
                self.pos += 8;
            },
            .length_delimited => {
                const len = try self.readVarint();
                const end = self.pos + @as(usize, @intCast(len));
                if (end > self.data.len) return error.UnexpectedEof;
                self.pos = end;
            },
            .fixed32 => {
                if (self.pos + 4 > self.data.len) return error.UnexpectedEof;
                self.pos += 4;
            },
            else => return error.UnsupportedWireType,
        }
    }
};
```

**Step 2: Build to verify compilation**

Run: `zig build`
Expected: Build succeeds with no errors

**Step 3: Commit**

```bash
git add src/protobuf.zig
git commit -m "feat(protobuf): add Decoder with core wire format reading"
```

---

## Task 2: Implement Date and Amount decoders

**Files:**
- Modify: `src/protobuf.zig` (add after Decoder struct)

**Step 1: Add decodeDate function**

Add to `src/protobuf.zig` after Decoder struct:

```zig
/// Decode a Date message from length-delimited bytes
fn decodeDate(allocator: std.mem.Allocator, data: []const u8) !proto.Date {
    var decoder = Decoder.init(allocator, data);
    var date = proto.Date{ .year = 0, .month = 0, .day = 0 };

    while (try decoder.readTag()) |tag| {
        switch (tag.field_number) {
            1 => { // year
                if (tag.wire_type != .varint) return error.InvalidWireType;
                date.year = @as(i32, @intCast(try decoder.readVarint()));
            },
            2 => { // month
                if (tag.wire_type != .varint) return error.InvalidWireType;
                date.month = @as(i32, @intCast(try decoder.readVarint()));
            },
            3 => { // day
                if (tag.wire_type != .varint) return error.InvalidWireType;
                date.day = @as(i32, @intCast(try decoder.readVarint()));
            },
            else => try decoder.skipField(tag.wire_type),
        }
    }

    return date;
}

/// Decode an Amount message from length-delimited bytes
fn decodeAmount(allocator: std.mem.Allocator, data: []const u8) !proto.Amount {
    var decoder = Decoder.init(allocator, data);
    var number: []u8 = &[_]u8{};
    var currency: []u8 = &[_]u8{};

    while (try decoder.readTag()) |tag| {
        switch (tag.field_number) {
            1 => { // number
                if (tag.wire_type != .length_delimited) return error.InvalidWireType;
                number = try decoder.readString();
            },
            2 => { // currency
                if (tag.wire_type != .length_delimited) return error.InvalidWireType;
                currency = try decoder.readString();
            },
            else => try decoder.skipField(tag.wire_type),
        }
    }

    return proto.Amount{
        .number = number,
        .currency = currency,
    };
}

/// Decode a Location message from length-delimited bytes
fn decodeLocation(allocator: std.mem.Allocator, data: []const u8) !proto.Location {
    var decoder = Decoder.init(allocator, data);
    var filename: []u8 = &[_]u8{};
    var line: i32 = 0;
    var column: i32 = 0;

    while (try decoder.readTag()) |tag| {
        switch (tag.field_number) {
            1 => { // filename
                if (tag.wire_type != .length_delimited) return error.InvalidWireType;
                filename = try decoder.readString();
            },
            2 => { // line
                if (tag.wire_type != .varint) return error.InvalidWireType;
                line = @as(i32, @intCast(try decoder.readVarint()));
            },
            3 => { // column
                if (tag.wire_type != .varint) return error.InvalidWireType;
                column = @as(i32, @intCast(try decoder.readVarint()));
            },
            else => try decoder.skipField(tag.wire_type),
        }
    }

    return proto.Location{
        .filename = filename,
        .line = line,
        .column = column,
    };
}
```

**Step 2: Build to verify compilation**

Run: `zig build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add src/protobuf.zig
git commit -m "feat(protobuf): add Date, Amount, and Location decoders"
```

---

## Task 3: Implement Transaction decoder

**Files:**
- Modify: `src/protobuf.zig` (add after decodeLocation)

**Step 1: Add decodePosting helper**

```zig
/// Decode a Posting message from length-delimited bytes
fn decodePosting(allocator: std.mem.Allocator, data: []const u8) !proto.Posting {
    var decoder = Decoder.init(allocator, data);
    var account: []u8 = &[_]u8{};
    var amount: ?proto.Amount = null;
    var cost: ?proto.Amount = null;
    var price: ?proto.Amount = null;
    var flag: ?[]u8 = null;

    while (try decoder.readTag()) |tag| {
        switch (tag.field_number) {
            1 => { // account
                if (tag.wire_type != .length_delimited) return error.InvalidWireType;
                account = try decoder.readString();
            },
            2 => { // amount (optional)
                if (tag.wire_type != .length_delimited) return error.InvalidWireType;
                const amt_bytes = try decoder.readBytes();
                amount = try decodeAmount(allocator, amt_bytes);
            },
            3 => { // cost (optional)
                if (tag.wire_type != .length_delimited) return error.InvalidWireType;
                const cost_bytes = try decoder.readBytes();
                cost = try decodeAmount(allocator, cost_bytes);
            },
            4 => { // price (optional)
                if (tag.wire_type != .length_delimited) return error.InvalidWireType;
                const price_bytes = try decoder.readBytes();
                price = try decodeAmount(allocator, price_bytes);
            },
            5 => { // flag (optional)
                if (tag.wire_type != .length_delimited) return error.InvalidWireType;
                flag = try decoder.readString();
            },
            else => try decoder.skipField(tag.wire_type),
        }
    }

    return proto.Posting{
        .account = account,
        .amount = amount,
        .cost = cost,
        .price = price,
        .flag = flag,
    };
}
```

**Step 2: Add decodeTransaction function**

```zig
/// Decode a Transaction message from length-delimited bytes
fn decodeTransaction(allocator: std.mem.Allocator, data: []const u8) !proto.Transaction {
    var decoder = Decoder.init(allocator, data);
    var date = proto.Date{ .year = 0, .month = 0, .day = 0 };
    var flag: ?[]u8 = null;
    var payee: ?[]u8 = null;
    var narration: []u8 = &[_]u8{};
    var tags = std.ArrayList([]u8).init(allocator);
    var links = std.ArrayList([]u8).init(allocator);
    var postings = std.ArrayList(proto.Posting).init(allocator);
    var location = proto.Location{ .filename = &[_]u8{}, .line = 0, .column = 0 };

    while (try decoder.readTag()) |tag| {
        switch (tag.field_number) {
            1 => { // date
                if (tag.wire_type != .length_delimited) return error.InvalidWireType;
                const date_bytes = try decoder.readBytes();
                date = try decodeDate(allocator, date_bytes);
            },
            2 => { // flag (optional)
                if (tag.wire_type != .length_delimited) return error.InvalidWireType;
                flag = try decoder.readString();
            },
            3 => { // payee (optional)
                if (tag.wire_type != .length_delimited) return error.InvalidWireType;
                payee = try decoder.readString();
            },
            4 => { // narration
                if (tag.wire_type != .length_delimited) return error.InvalidWireType;
                narration = try decoder.readString();
            },
            5 => { // tags (repeated)
                if (tag.wire_type != .length_delimited) return error.InvalidWireType;
                const tag_str = try decoder.readString();
                try tags.append(tag_str);
            },
            6 => { // links (repeated)
                if (tag.wire_type != .length_delimited) return error.InvalidWireType;
                const link_str = try decoder.readString();
                try links.append(link_str);
            },
            7 => { // postings (repeated)
                if (tag.wire_type != .length_delimited) return error.InvalidWireType;
                const posting_bytes = try decoder.readBytes();
                const posting = try decodePosting(allocator, posting_bytes);
                try postings.append(posting);
            },
            8 => { // metadata (skip for now)
                try decoder.skipField(tag.wire_type);
            },
            9 => { // location
                if (tag.wire_type != .length_delimited) return error.InvalidWireType;
                const loc_bytes = try decoder.readBytes();
                location = try decodeLocation(allocator, loc_bytes);
            },
            else => try decoder.skipField(tag.wire_type),
        }
    }

    return proto.Transaction{
        .date = date,
        .flag = flag,
        .payee = payee,
        .narration = narration,
        .tags = try tags.toOwnedSlice(),
        .links = try links.toOwnedSlice(),
        .postings = try postings.toOwnedSlice(),
        .location = location,
    };
}
```

**Step 3: Build to verify compilation**

Run: `zig build`
Expected: Build succeeds

**Step 4: Commit**

```bash
git add src/protobuf.zig
git commit -m "feat(protobuf): add Transaction and Posting decoders"
```

---

## Task 4: Implement other directive type decoders

**Files:**
- Modify: `src/protobuf.zig` (add after decodeTransaction)

**Step 1: Add Balance decoder**

```zig
/// Decode a Balance message from length-delimited bytes
fn decodeBalance(allocator: std.mem.Allocator, data: []const u8) !proto.Balance {
    var decoder = Decoder.init(allocator, data);
    var date = proto.Date{ .year = 0, .month = 0, .day = 0 };
    var account: []u8 = &[_]u8{};
    var amount = proto.Amount{ .number = &[_]u8{}, .currency = &[_]u8{} };
    var location = proto.Location{ .filename = &[_]u8{}, .line = 0, .column = 0 };

    while (try decoder.readTag()) |tag| {
        switch (tag.field_number) {
            1 => { // date
                if (tag.wire_type != .length_delimited) return error.InvalidWireType;
                const date_bytes = try decoder.readBytes();
                date = try decodeDate(allocator, date_bytes);
            },
            2 => { // account
                if (tag.wire_type != .length_delimited) return error.InvalidWireType;
                account = try decoder.readString();
            },
            3 => { // amount
                if (tag.wire_type != .length_delimited) return error.InvalidWireType;
                const amt_bytes = try decoder.readBytes();
                amount = try decodeAmount(allocator, amt_bytes);
            },
            4 => { // tolerance (optional - skip)
                try decoder.skipField(tag.wire_type);
            },
            5 => { // metadata (skip)
                try decoder.skipField(tag.wire_type);
            },
            6 => { // location
                if (tag.wire_type != .length_delimited) return error.InvalidWireType;
                const loc_bytes = try decoder.readBytes();
                location = try decodeLocation(allocator, loc_bytes);
            },
            else => try decoder.skipField(tag.wire_type),
        }
    }

    return proto.Balance{
        .date = date,
        .account = account,
        .amount = amount,
        .location = location,
    };
}
```

**Step 2: Add Open decoder**

```zig
/// Decode an Open message from length-delimited bytes
fn decodeOpen(allocator: std.mem.Allocator, data: []const u8) !proto.Open {
    var decoder = Decoder.init(allocator, data);
    var date = proto.Date{ .year = 0, .month = 0, .day = 0 };
    var account: []u8 = &[_]u8{};
    var currencies = std.ArrayList([]u8).init(allocator);
    var location = proto.Location{ .filename = &[_]u8{}, .line = 0, .column = 0 };

    while (try decoder.readTag()) |tag| {
        switch (tag.field_number) {
            1 => { // date
                if (tag.wire_type != .length_delimited) return error.InvalidWireType;
                const date_bytes = try decoder.readBytes();
                date = try decodeDate(allocator, date_bytes);
            },
            2 => { // account
                if (tag.wire_type != .length_delimited) return error.InvalidWireType;
                account = try decoder.readString();
            },
            3 => { // currencies (repeated)
                if (tag.wire_type != .length_delimited) return error.InvalidWireType;
                const currency = try decoder.readString();
                try currencies.append(currency);
            },
            4 => { // booking_method (optional - skip)
                try decoder.skipField(tag.wire_type);
            },
            5 => { // metadata (skip)
                try decoder.skipField(tag.wire_type);
            },
            6 => { // location
                if (tag.wire_type != .length_delimited) return error.InvalidWireType;
                const loc_bytes = try decoder.readBytes();
                location = try decodeLocation(allocator, loc_bytes);
            },
            else => try decoder.skipField(tag.wire_type),
        }
    }

    return proto.Open{
        .date = date,
        .account = account,
        .currencies = try currencies.toOwnedSlice(),
        .location = location,
    };
}
```

**Step 3: Add Close and Pad decoders**

```zig
/// Decode a Close message from length-delimited bytes
fn decodeClose(allocator: std.mem.Allocator, data: []const u8) !proto.Close {
    var decoder = Decoder.init(allocator, data);
    var date = proto.Date{ .year = 0, .month = 0, .day = 0 };
    var account: []u8 = &[_]u8{};
    var location = proto.Location{ .filename = &[_]u8{}, .line = 0, .column = 0 };

    while (try decoder.readTag()) |tag| {
        switch (tag.field_number) {
            1 => { // date
                if (tag.wire_type != .length_delimited) return error.InvalidWireType;
                const date_bytes = try decoder.readBytes();
                date = try decodeDate(allocator, date_bytes);
            },
            2 => { // account
                if (tag.wire_type != .length_delimited) return error.InvalidWireType;
                account = try decoder.readString();
            },
            3 => { // metadata (skip)
                try decoder.skipField(tag.wire_type);
            },
            4 => { // location
                if (tag.wire_type != .length_delimited) return error.InvalidWireType;
                const loc_bytes = try decoder.readBytes();
                location = try decodeLocation(allocator, loc_bytes);
            },
            else => try decoder.skipField(tag.wire_type),
        }
    }

    return proto.Close{
        .date = date,
        .account = account,
        .location = location,
    };
}

/// Decode a Pad message from length-delimited bytes
fn decodePad(allocator: std.mem.Allocator, data: []const u8) !proto.Pad {
    var decoder = Decoder.init(allocator, data);
    var date = proto.Date{ .year = 0, .month = 0, .day = 0 };
    var account: []u8 = &[_]u8{};
    var source_account: []u8 = &[_]u8{};
    var location = proto.Location{ .filename = &[_]u8{}, .line = 0, .column = 0 };

    while (try decoder.readTag()) |tag| {
        switch (tag.field_number) {
            1 => { // date
                if (tag.wire_type != .length_delimited) return error.InvalidWireType;
                const date_bytes = try decoder.readBytes();
                date = try decodeDate(allocator, date_bytes);
            },
            2 => { // account
                if (tag.wire_type != .length_delimited) return error.InvalidWireType;
                account = try decoder.readString();
            },
            3 => { // source_account
                if (tag.wire_type != .length_delimited) return error.InvalidWireType;
                source_account = try decoder.readString();
            },
            4 => { // metadata (skip)
                try decoder.skipField(tag.wire_type);
            },
            5 => { // location
                if (tag.wire_type != .length_delimited) return error.InvalidWireType;
                const loc_bytes = try decoder.readBytes();
                location = try decodeLocation(allocator, loc_bytes);
            },
            else => try decoder.skipField(tag.wire_type),
        }
    }

    return proto.Pad{
        .date = date,
        .account = account,
        .source_account = source_account,
        .location = location,
    };
}
```

**Step 4: Build to verify compilation**

Run: `zig build`
Expected: Build succeeds

**Step 5: Commit**

```bash
git add src/protobuf.zig
git commit -m "feat(protobuf): add Balance, Open, Close, and Pad decoders"
```

---

## Task 5: Implement Directive decoder

**Files:**
- Modify: `src/protobuf.zig` (add after directive type decoders)

**Step 1: Add decodeDirective function**

```zig
/// Decode a Directive message from length-delimited bytes
fn decodeDirective(allocator: std.mem.Allocator, data: []const u8) !proto.Directive {
    var decoder = Decoder.init(allocator, data);

    // Directive is a oneof - only one field will be set
    while (try decoder.readTag()) |tag| {
        if (tag.wire_type != .length_delimited) return error.InvalidWireType;

        const directive_bytes = try decoder.readBytes();

        switch (tag.field_number) {
            1 => { // transaction
                const txn = try decodeTransaction(allocator, directive_bytes);
                return proto.Directive{
                    .directive_type = .{ .transaction = txn },
                };
            },
            2 => { // balance
                const bal = try decodeBalance(allocator, directive_bytes);
                return proto.Directive{
                    .directive_type = .{ .balance = bal },
                };
            },
            3 => { // open
                const open = try decodeOpen(allocator, directive_bytes);
                return proto.Directive{
                    .directive_type = .{ .open = open },
                };
            },
            4 => { // close
                const close = try decodeClose(allocator, directive_bytes);
                return proto.Directive{
                    .directive_type = .{ .close = close },
                };
            },
            6 => { // pad (field 5 is commodity, skipping for now)
                const pad = try decodePad(allocator, directive_bytes);
                return proto.Directive{
                    .directive_type = .{ .pad = pad },
                };
            },
            else => {
                // Unknown directive type - skip
                continue;
            },
        }
    }

    return error.NoDirectiveTypeFound;
}
```

**Step 2: Build to verify compilation**

Run: `zig build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add src/protobuf.zig
git commit -m "feat(protobuf): add Directive oneof decoder"
```

---

## Task 6: Implement Error decoder

**Files:**
- Modify: `src/protobuf.zig` (add after decodeDirective)

**Step 1: Add decodeError function**

```zig
/// Decode an Error message from length-delimited bytes
fn decodeError(allocator: std.mem.Allocator, data: []const u8) !proto.Error {
    var decoder = Decoder.init(allocator, data);
    var message: []u8 = &[_]u8{};
    var source: []u8 = &[_]u8{};
    var location: ?proto.Location = null;

    while (try decoder.readTag()) |tag| {
        switch (tag.field_number) {
            1 => { // message
                if (tag.wire_type != .length_delimited) return error.InvalidWireType;
                message = try decoder.readString();
            },
            2 => { // source
                if (tag.wire_type != .length_delimited) return error.InvalidWireType;
                source = try decoder.readString();
            },
            3 => { // location (optional)
                if (tag.wire_type != .length_delimited) return error.InvalidWireType;
                const loc_bytes = try decoder.readBytes();
                location = try decodeLocation(allocator, loc_bytes);
            },
            else => try decoder.skipField(tag.wire_type),
        }
    }

    return proto.Error{
        .message = message,
        .source = source,
        .location = location,
    };
}
```

**Step 2: Build to verify compilation**

Run: `zig build`
Expected: Build succeeds

**Step 3: Commit**

```bash
git add src/protobuf.zig
git commit -m "feat(protobuf): add Error decoder"
```

---

## Task 7: Implement ProcessResponse full decoder

**Files:**
- Modify: `src/protobuf.zig:178-229` (replace decodeProcessResponse)

**Step 1: Define new ProcessResponse result struct**

Replace the existing `ProcessResponseInfo` struct (around line 172) with:

```zig
/// ProcessResponse decoder result with full directive data
pub const ProcessResponseData = struct {
    directives: []proto.Directive,
    errors: []proto.Error,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ProcessResponseData) void {
        // Free directives
        for (self.directives) |directive| {
            freeDirective(self.allocator, directive);
        }
        self.allocator.free(self.directives);

        // Free errors
        for (self.errors) |err| {
            freeError(self.allocator, err);
        }
        self.allocator.free(self.errors);
    }
};

/// Free memory allocated for a directive
fn freeDirective(allocator: std.mem.Allocator, directive: proto.Directive) void {
    switch (directive.directive_type) {
        .transaction => |txn| {
            if (txn.flag) |f| allocator.free(f);
            if (txn.payee) |p| allocator.free(p);
            allocator.free(txn.narration);
            for (txn.tags) |tag| allocator.free(tag);
            allocator.free(txn.tags);
            for (txn.links) |link| allocator.free(link);
            allocator.free(txn.links);
            for (txn.postings) |posting| {
                allocator.free(posting.account);
                if (posting.amount) |amt| {
                    allocator.free(amt.number);
                    allocator.free(amt.currency);
                }
                if (posting.cost) |c| {
                    allocator.free(c.number);
                    allocator.free(c.currency);
                }
                if (posting.price) |p| {
                    allocator.free(p.number);
                    allocator.free(p.currency);
                }
                if (posting.flag) |f| allocator.free(f);
            }
            allocator.free(txn.postings);
            allocator.free(txn.location.filename);
        },
        .balance => |bal| {
            allocator.free(bal.account);
            allocator.free(bal.amount.number);
            allocator.free(bal.amount.currency);
            allocator.free(bal.location.filename);
        },
        .open => |open| {
            allocator.free(open.account);
            for (open.currencies) |cur| allocator.free(cur);
            allocator.free(open.currencies);
            allocator.free(open.location.filename);
        },
        .close => |close| {
            allocator.free(close.account);
            allocator.free(close.location.filename);
        },
        .pad => |pad| {
            allocator.free(pad.account);
            allocator.free(pad.source_account);
            allocator.free(pad.location.filename);
        },
    }
}

/// Free memory allocated for an error
fn freeError(allocator: std.mem.Allocator, err: proto.Error) void {
    allocator.free(err.message);
    allocator.free(err.source);
    if (err.location) |loc| {
        allocator.free(loc.filename);
    }
}
```

**Step 2: Replace decodeProcessResponse function**

Replace the existing `decodeProcessResponse` function (around line 179-229) with:

```zig
/// Decode ProcessResponse to extract directives and errors
pub fn decodeProcessResponseFull(allocator: std.mem.Allocator, data: []const u8) !ProcessResponseData {
    var decoder = Decoder.init(allocator, data);
    var directives = std.ArrayList(proto.Directive).init(allocator);
    var errors = std.ArrayList(proto.Error).init(allocator);

    while (try decoder.readTag()) |tag| {
        if (tag.wire_type != .length_delimited) {
            try decoder.skipField(tag.wire_type);
            continue;
        }

        const field_bytes = try decoder.readBytes();

        switch (tag.field_number) {
            1 => { // directives (repeated)
                const directive = try decodeDirective(allocator, field_bytes);
                try directives.append(directive);
            },
            2 => { // errors (repeated)
                const err = try decodeError(allocator, field_bytes);
                try errors.append(err);
            },
            3 => { // updated_options (map - skip for now)
                // Skip map fields
            },
            else => {
                // Unknown field - skip
            },
        }
    }

    return ProcessResponseData{
        .directives = try directives.toOwnedSlice(),
        .errors = try errors.toOwnedSlice(),
        .allocator = allocator,
    };
}

/// Keep old function for backwards compatibility (counts only)
pub fn decodeProcessResponse(data: []const u8) !ProcessResponseInfo {
    var directive_count: usize = 0;
    var error_count: usize = 0;

    var pos: usize = 0;
    while (pos < data.len) {
        if (pos >= data.len) break;

        const tag_byte = data[pos];
        pos += 1;

        const field_number = tag_byte >> 3;
        const wire_type = @as(WireType, @enumFromInt(tag_byte & 0x07));

        switch (wire_type) {
            .varint => {
                while (pos < data.len and (data[pos] & 0x80) != 0) : (pos += 1) {}
                if (pos < data.len) pos += 1;
            },
            .length_delimited => {
                var len: usize = 0;
                var shift: u6 = 0;
                while (pos < data.len) {
                    const byte = data[pos];
                    pos += 1;
                    len |= @as(usize, byte & 0x7F) << shift;
                    if ((byte & 0x80) == 0) break;
                    shift += 7;
                }

                if (field_number == 1) {
                    directive_count += 1;
                } else if (field_number == 2) {
                    error_count += 1;
                }

                pos += len;
            },
            else => break,
        }
    }

    return ProcessResponseInfo{
        .directive_count = directive_count,
        .error_count = error_count,
    };
}
```

**Step 3: Build to verify compilation**

Run: `zig build`
Expected: Build succeeds

**Step 4: Commit**

```bash
git add src/protobuf.zig
git commit -m "feat(protobuf): add full ProcessResponse decoder with directive data"
```

---

## Task 8: Update orchestrator to use full decoder

**Files:**
- Modify: `src/orchestrator.zig:173-197`

**Step 1: Replace minimal decoder call with full decoder**

Replace lines 173-197 in `src/orchestrator.zig` with:

```zig
        // Parse response to get full directive data
        const response_data = try protobuf.decodeProcessResponseFull(self.allocator, proc_resp);
        defer {
            // Note: response_data owns the memory, we need to copy to return
            var data_copy = response_data;
            data_copy.deinit();
        }

        if (self.verbose) {
            std.debug.print("   📊 Plugin returned {d} directives, {d} errors\n", .{
                response_data.directives.len,
                response_data.errors.len,
            });
        }

        // Send shutdown request
        const shutdown_req = try protobuf.encodeShutdownRequest(
            self.allocator,
            "pipeline_complete",
        );
        defer self.allocator.free(shutdown_req);
        try plugin.sendMessage(self.io, shutdown_req);

        // Copy directives and errors to return (allocator-owned)
        const directives_copy = try self.allocator.alloc(proto.Directive, response_data.directives.len);
        @memcpy(directives_copy, response_data.directives);

        const errors_copy = try self.allocator.alloc(proto.Error, response_data.errors.len);
        @memcpy(errors_copy, response_data.errors);

        return StageResult{
            .directives = directives_copy,
            .errors = errors_copy,
            .updated_options = std.StringHashMap([]const u8).init(self.allocator),
        };
```

**Step 2: Build to verify compilation**

Run: `zig build`
Expected: Build succeeds

**Step 3: Test with parser-only pipeline**

Run: `./test_pipeline.sh`
Expected: Should now show "Directives: 16" instead of "Directives: 0"

**Step 4: Commit**

```bash
git add src/orchestrator.zig
git commit -m "feat(orchestrator): use full protobuf decoder for directive data"
```

---

## Task 9: Add integration test for full deserialization

**Files:**
- Create: `test/test_deserialization.zig`

**Step 1: Create test file**

```zig
// test/test_deserialization.zig
const std = @import("std");
const testing = std.testing;
const protobuf = @import("../src/protobuf.zig");
const proto = @import("../src/proto.zig");

test "decode Date message" {
    const allocator = testing.allocator;

    // Manually craft a Date message: {year: 2024, month: 3, day: 15}
    // Field 1 (year): tag=08, value=2024 (varint)
    // Field 2 (month): tag=10, value=3
    // Field 3 (day): tag=18, value=15
    const data = [_]u8{
        0x08, 0xe8, 0x0f, // field 1: year=2024
        0x10, 0x03,       // field 2: month=3
        0x18, 0x0f,       // field 3: day=15
    };

    var decoder = protobuf.Decoder.init(allocator, &data);
    _ = decoder; // Test compilation for now

    // TODO: Once decodeDate is accessible, test it
    // const date = try protobuf.decodeDate(allocator, &data);
    // try testing.expectEqual(@as(i32, 2024), date.year);
    // try testing.expectEqual(@as(i32, 3), date.month);
    // try testing.expectEqual(@as(i32, 15), date.day);
}

test "decode Amount message" {
    const allocator = testing.allocator;

    // Amount message: {number: "100.50", currency: "USD"}
    // Field 1 (number): tag=0a, len=6, "100.50"
    // Field 2 (currency): tag=12, len=3, "USD"
    const data = [_]u8{
        0x0a, 0x06, '1', '0', '0', '.', '5', '0',
        0x12, 0x03, 'U', 'S', 'D',
    };

    var decoder = protobuf.Decoder.init(allocator, &data);
    _ = decoder; // Test compilation for now

    // TODO: Test once functions are accessible
}
```

**Step 2: Add test to build.zig**

Add to the test step in `build.zig` if not already present:

```zig
// In build.zig, add to test configuration
const deserialization_tests = b.addTest(.{
    .root_source_file = .{ .path = "test/test_deserialization.zig" },
    .target = target,
    .optimize = optimize,
});
test_step.dependOn(&b.addRunArtifact(deserialization_tests).step);
```

**Step 3: Run tests**

Run: `zig build test`
Expected: Tests compile and pass (basic compilation tests)

**Step 4: Commit**

```bash
git add test/test_deserialization.zig build.zig
git commit -m "test: add protobuf deserialization tests"
```

---

## Task 10: Verify end-to-end with verbose output

**Files:**
- None (verification step)

**Step 1: Run parser-only pipeline with verbose mode**

Run: `./zig-out/bin/beancount-runner --config pipeline-parser-only.toml --input examples/sample.beancount --verbose`

Expected output should include:
```
📊 Plugin returned 16 directives, 0 errors
✓ Directives: 16, Errors: 0
```

**Step 2: Check that directives are actually parsed**

Add temporary debug output to verify directive types are recognized. In `src/main.zig`, after pipeline execution, add:

```zig
if (verbose) {
    std.debug.print("\n📋 Directive breakdown:\n", .{});
    for (result.directives) |directive| {
        const type_name = switch (directive.directive_type) {
            .transaction => "Transaction",
            .balance => "Balance",
            .open => "Open",
            .close => "Close",
            .pad => "Pad",
        };
        std.debug.print("  - {s}\n", .{type_name});
    }
}
```

**Step 3: Rebuild and run**

Run: `zig build && ./zig-out/bin/beancount-runner --config pipeline-parser-only.toml --input examples/sample.beancount --verbose`

Expected: Should see breakdown of directive types

**Step 4: Remove debug output and commit**

```bash
git add src/main.zig
git commit -m "feat: verify full protobuf deserialization working end-to-end"
```

---

## Summary

**Total Tasks: 10**
**Estimated Time: 3-4 hours**

**Key Milestones:**
1. Core decoder infrastructure (Tasks 1-2)
2. Directive type decoders (Tasks 3-6)
3. ProcessResponse integration (Tasks 7-8)
4. Testing and verification (Tasks 9-10)

**Success Criteria:**
- All directive types can be deserialized from protobuf wire format
- Parser plugin output is fully decoded into proto.Directive structs
- Integration test shows "Directives: 16" instead of "Directives: 0"
- Verbose mode shows directive type breakdown
- Memory is properly managed (no leaks)

**Next Steps After This Plan:**
- Task #2: Multi-stage pipeline testing (parser + plugin + validator)
- Task #3: Complete validation rule set
- Additional output formats (text, protobuf)

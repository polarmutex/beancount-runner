const std = @import("std");
const proto = @import("proto.zig");

/// Protobuf wire types
const WireType = enum(u3) {
    varint = 0,
    fixed64 = 1,
    length_delimited = 2,
    start_group = 3,
    end_group = 4,
    fixed32 = 5,
};

/// Protobuf message encoder
pub const Encoder = struct {
    buffer: std.ArrayList(u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Encoder {
        return Encoder{
            .buffer = std.ArrayList(u8){
                .items = &[_]u8{},
                .capacity = 0,
            },
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Encoder) void {
        self.buffer.deinit(self.allocator);
    }

    pub fn toOwnedSlice(self: *Encoder) ![]u8 {
        return self.buffer.toOwnedSlice(self.allocator);
    }

    /// Write a field tag (field number + wire type)
    fn writeTag(self: *Encoder, field_number: u32, wire_type: WireType) !void {
        const tag = (field_number << 3) | @intFromEnum(wire_type);
        try self.writeVarint(tag);
    }

    /// Write a varint (variable-length integer)
    fn writeVarint(self: *Encoder, value: u64) !void {
        var val = value;
        while (val >= 0x80) {
            try self.buffer.append(self.allocator, @as(u8, @intCast((val & 0x7F) | 0x80)));
            val >>= 7;
        }
        try self.buffer.append(self.allocator, @as(u8, @intCast(val & 0x7F)));
    }

    /// Write a string field
    pub fn writeString(self: *Encoder, field_number: u32, value: []const u8) !void {
        if (value.len == 0) return; // Skip empty strings
        try self.writeTag(field_number, .length_delimited);
        try self.writeVarint(value.len);
        try self.buffer.appendSlice(self.allocator, value);
    }

    /// Write a bool field
    pub fn writeBool(self: *Encoder, field_number: u32, value: bool) !void {
        try self.writeTag(field_number, .varint);
        try self.writeVarint(if (value) 1 else 0);
    }

    /// Write a map<string, string> field
    pub fn writeStringMap(self: *Encoder, field_number: u32, map: std.StringHashMap([]const u8)) !void {
        // Each map entry is encoded as a length-delimited message with field 1 = key, field 2 = value
        var iter = map.iterator();
        while (iter.next()) |entry| {
            // Create a sub-encoder for the map entry
            var entry_encoder = Encoder.init(self.allocator);
            defer entry_encoder.deinit();

            try entry_encoder.writeString(1, entry.key_ptr.*);
            try entry_encoder.writeString(2, entry.value_ptr.*);

            const entry_bytes = try entry_encoder.buffer.toOwnedSlice(entry_encoder.allocator);
            defer entry_encoder.allocator.free(entry_bytes);

            // Write the map entry as a length-delimited field
            try self.writeTag(field_number, .length_delimited);
            try self.writeVarint(entry_bytes.len);
            try self.buffer.appendSlice(self.allocator, entry_bytes);
        }
    }

    /// Write an int32 field
    pub fn writeInt32(self: *Encoder, field_number: u32, value: i32) !void {
        if (value == 0) return; // Skip zero values
        try self.writeTag(field_number, .varint);
        // Encode as unsigned (zig-zag not needed for positive values like dates)
        try self.writeVarint(@as(u64, @intCast(value)));
    }

    /// Write a length-delimited submessage
    pub fn writeSubmessage(self: *Encoder, field_number: u32, data: []const u8) !void {
        if (data.len == 0) return; // Skip empty submessages
        try self.writeTag(field_number, .length_delimited);
        try self.writeVarint(data.len);
        try self.buffer.appendSlice(self.allocator, data);
    }
};

/// Encode a Date message
pub fn encodeDate(allocator: std.mem.Allocator, date: proto.Date) ![]u8 {
    var encoder = Encoder.init(allocator);
    defer encoder.deinit();

    try encoder.writeInt32(1, date.year);
    try encoder.writeInt32(2, date.month);
    try encoder.writeInt32(3, date.day);

    return encoder.toOwnedSlice();
}

/// Encode an Amount message
pub fn encodeAmount(allocator: std.mem.Allocator, amount: proto.Amount) ![]u8 {
    var encoder = Encoder.init(allocator);
    defer encoder.deinit();

    try encoder.writeString(1, amount.number);
    try encoder.writeString(2, amount.currency);

    return encoder.toOwnedSlice();
}

/// Encode a Location message
pub fn encodeLocation(allocator: std.mem.Allocator, location: proto.Location) ![]u8 {
    var encoder = Encoder.init(allocator);
    defer encoder.deinit();

    try encoder.writeString(1, location.filename);
    try encoder.writeInt32(2, location.line);
    try encoder.writeInt32(3, location.column);

    return encoder.toOwnedSlice();
}

/// Encode a Posting message
pub fn encodePosting(allocator: std.mem.Allocator, posting: proto.Posting) ![]u8 {
    var encoder = Encoder.init(allocator);
    defer encoder.deinit();

    try encoder.writeString(1, posting.account);

    if (posting.amount) |amount| {
        const amount_bytes = try encodeAmount(allocator, amount);
        defer allocator.free(amount_bytes);
        try encoder.writeSubmessage(2, amount_bytes);
    }

    if (posting.cost) |cost| {
        const cost_bytes = try encodeAmount(allocator, cost);
        defer allocator.free(cost_bytes);
        try encoder.writeSubmessage(3, cost_bytes);
    }

    if (posting.price) |price| {
        const price_bytes = try encodeAmount(allocator, price);
        defer allocator.free(price_bytes);
        try encoder.writeSubmessage(4, price_bytes);
    }

    if (posting.flag) |flag| {
        try encoder.writeString(5, flag);
    }

    return encoder.toOwnedSlice();
}

/// Encode a Transaction message
pub fn encodeTransaction(allocator: std.mem.Allocator, txn: proto.Transaction) ![]u8 {
    var encoder = Encoder.init(allocator);
    defer encoder.deinit();

    const date_bytes = try encodeDate(allocator, txn.date);
    defer allocator.free(date_bytes);
    try encoder.writeSubmessage(1, date_bytes);

    if (txn.flag) |flag| {
        try encoder.writeString(2, flag);
    }

    if (txn.payee) |payee| {
        try encoder.writeString(3, payee);
    }

    try encoder.writeString(4, txn.narration);

    for (txn.tags) |tag| {
        try encoder.writeString(5, tag);
    }

    for (txn.links) |link| {
        try encoder.writeString(6, link);
    }

    for (txn.postings) |posting| {
        const posting_bytes = try encodePosting(allocator, posting);
        defer allocator.free(posting_bytes);
        try encoder.writeSubmessage(7, posting_bytes);
    }

    // Field 8: metadata (skip for now)

    const location_bytes = try encodeLocation(allocator, txn.location);
    defer allocator.free(location_bytes);
    try encoder.writeSubmessage(9, location_bytes);

    return encoder.toOwnedSlice();
}

/// Encode a Balance message
pub fn encodeBalance(allocator: std.mem.Allocator, balance: proto.Balance) ![]u8 {
    var encoder = Encoder.init(allocator);
    defer encoder.deinit();

    const date_bytes = try encodeDate(allocator, balance.date);
    defer allocator.free(date_bytes);
    try encoder.writeSubmessage(1, date_bytes);

    try encoder.writeString(2, balance.account);

    const amount_bytes = try encodeAmount(allocator, balance.amount);
    defer allocator.free(amount_bytes);
    try encoder.writeSubmessage(3, amount_bytes);

    // Field 4: tolerance (skip)
    // Field 5: metadata (skip)

    const location_bytes = try encodeLocation(allocator, balance.location);
    defer allocator.free(location_bytes);
    try encoder.writeSubmessage(6, location_bytes);

    return encoder.toOwnedSlice();
}

/// Encode an Open message
pub fn encodeOpen(allocator: std.mem.Allocator, open: proto.Open) ![]u8 {
    var encoder = Encoder.init(allocator);
    defer encoder.deinit();

    const date_bytes = try encodeDate(allocator, open.date);
    defer allocator.free(date_bytes);
    try encoder.writeSubmessage(1, date_bytes);

    try encoder.writeString(2, open.account);

    for (open.currencies) |currency| {
        try encoder.writeString(3, currency);
    }

    // Field 4: booking_method (skip)
    // Field 5: metadata (skip)

    const location_bytes = try encodeLocation(allocator, open.location);
    defer allocator.free(location_bytes);
    try encoder.writeSubmessage(6, location_bytes);

    return encoder.toOwnedSlice();
}

/// Encode a Close message
pub fn encodeClose(allocator: std.mem.Allocator, close: proto.Close) ![]u8 {
    var encoder = Encoder.init(allocator);
    defer encoder.deinit();

    const date_bytes = try encodeDate(allocator, close.date);
    defer allocator.free(date_bytes);
    try encoder.writeSubmessage(1, date_bytes);

    try encoder.writeString(2, close.account);

    // Field 3: metadata (skip)

    const location_bytes = try encodeLocation(allocator, close.location);
    defer allocator.free(location_bytes);
    try encoder.writeSubmessage(4, location_bytes);

    return encoder.toOwnedSlice();
}

/// Encode a Pad message
pub fn encodePad(allocator: std.mem.Allocator, pad: proto.Pad) ![]u8 {
    var encoder = Encoder.init(allocator);
    defer encoder.deinit();

    const date_bytes = try encodeDate(allocator, pad.date);
    defer allocator.free(date_bytes);
    try encoder.writeSubmessage(1, date_bytes);

    try encoder.writeString(2, pad.account);
    try encoder.writeString(3, pad.source_account);

    // Field 4: metadata (skip)

    const location_bytes = try encodeLocation(allocator, pad.location);
    defer allocator.free(location_bytes);
    try encoder.writeSubmessage(5, location_bytes);

    return encoder.toOwnedSlice();
}

/// Encode a Directive message (oneof wrapper)
pub fn encodeDirective(allocator: std.mem.Allocator, directive: proto.Directive) ![]u8 {
    var encoder = Encoder.init(allocator);
    defer encoder.deinit();

    switch (directive.directive_type) {
        .transaction => |txn| {
            const txn_bytes = try encodeTransaction(allocator, txn);
            defer allocator.free(txn_bytes);
            try encoder.writeSubmessage(1, txn_bytes);
        },
        .balance => |balance| {
            const balance_bytes = try encodeBalance(allocator, balance);
            defer allocator.free(balance_bytes);
            try encoder.writeSubmessage(2, balance_bytes);
        },
        .open => |open| {
            const open_bytes = try encodeOpen(allocator, open);
            defer allocator.free(open_bytes);
            try encoder.writeSubmessage(3, open_bytes);
        },
        .close => |close| {
            const close_bytes = try encodeClose(allocator, close);
            defer allocator.free(close_bytes);
            try encoder.writeSubmessage(4, close_bytes);
        },
        .pad => |pad| {
            const pad_bytes = try encodePad(allocator, pad);
            defer allocator.free(pad_bytes);
            // Pad is field 6 (field 5 is commodity)
            try encoder.writeSubmessage(6, pad_bytes);
        },
    }

    return encoder.toOwnedSlice();
}

/// InitRequest message encoder
pub fn encodeInitRequest(
    allocator: std.mem.Allocator,
    plugin_name: []const u8,
    pipeline_stage: []const u8,
    options: std.StringHashMap([]const u8),
) ![]u8 {
    var encoder = Encoder.init(allocator);
    defer encoder.deinit();

    try encoder.writeString(1, plugin_name);
    try encoder.writeString(2, pipeline_stage);
    try encoder.writeStringMap(3, options);

    return encoder.toOwnedSlice();
}

/// ProcessRequest message encoder (with full directive support)
pub fn encodeProcessRequest(
    allocator: std.mem.Allocator,
    directives: []const proto.Directive,
    input_file: []const u8,
    options_map: std.StringHashMap([]const u8),
) ![]u8 {
    var encoder = Encoder.init(allocator);
    defer encoder.deinit();

    // Field 1: repeated Directive directives = 1;
    for (directives) |directive| {
        const directive_bytes = try encodeDirective(allocator, directive);
        defer allocator.free(directive_bytes);
        try encoder.writeSubmessage(1, directive_bytes);
    }

    // Field 2: map<string, string> options_map = 2;
    try encoder.writeStringMap(2, options_map);

    // Field 3: string input_file = 3;
    try encoder.writeString(3, input_file);

    return encoder.toOwnedSlice();
}

/// ShutdownRequest message encoder
pub fn encodeShutdownRequest(
    allocator: std.mem.Allocator,
    reason: []const u8,
) ![]u8 {
    var encoder = Encoder.init(allocator);
    defer encoder.deinit();

    try encoder.writeString(1, reason);

    return encoder.toOwnedSlice();
}

/// Decode InitResponse (simple parser for success field)
pub fn decodeInitResponse(data: []const u8) !bool {
    // Look for field 1 (success bool)
    var pos: usize = 0;
    while (pos < data.len) {
        const tag_byte = data[pos];
        pos += 1;

        const field_number = tag_byte >> 3;
        const wire_type = @as(WireType, @enumFromInt(tag_byte & 0x07));

        if (field_number == 1 and wire_type == .varint) {
            // Read the bool value
            const value = data[pos];
            return value != 0;
        }

        // Skip this field
        switch (wire_type) {
            .varint => {
                while (pos < data.len and (data[pos] & 0x80) != 0) : (pos += 1) {}
                pos += 1;
            },
            .length_delimited => {
                const len = data[pos];
                pos += 1 + len;
            },
            else => break,
        }
    }

    return false;
}

/// ProcessResponse decoder result (simplified for MVP)
pub const ProcessResponseInfo = struct {
    directive_count: usize,
    error_count: usize,
};

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

/// Decode ProcessResponse to extract directives and errors
pub fn decodeProcessResponseFull(allocator: std.mem.Allocator, data: []const u8) !ProcessResponseData {
    var decoder = Decoder.init(allocator, data);

    // Use manual slice building to avoid ArrayList issues with proto types
    var directives_list: []proto.Directive = &[_]proto.Directive{};
    var errors_list: []proto.Error = &[_]proto.Error{};

    while (try decoder.readTag()) |tag| {
        if (tag.wire_type != .length_delimited) {
            try decoder.skipField(tag.wire_type);
            continue;
        }

        const field_bytes = try decoder.readBytes();

        switch (tag.field_number) {
            1 => { // directives (repeated)
                const directive = try decodeDirective(allocator, field_bytes);
                const old_directives = directives_list;
                directives_list = try allocator.alloc(proto.Directive, old_directives.len + 1);
                @memcpy(directives_list[0..old_directives.len], old_directives);
                directives_list[old_directives.len] = directive;
                if (old_directives.len > 0) allocator.free(old_directives);
            },
            2 => { // errors (repeated)
                const err = try decodeError(allocator, field_bytes);
                const old_errors = errors_list;
                errors_list = try allocator.alloc(proto.Error, old_errors.len + 1);
                @memcpy(errors_list[0..old_errors.len], old_errors);
                errors_list[old_errors.len] = err;
                if (old_errors.len > 0) allocator.free(old_errors);
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
        .directives = directives_list,
        .errors = errors_list,
        .allocator = allocator,
    };
}

/// Decode ProcessResponse to count directives and errors
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
                // Skip varint
                while (pos < data.len and (data[pos] & 0x80) != 0) : (pos += 1) {}
                if (pos < data.len) pos += 1;
            },
            .length_delimited => {
                // Read length
                var len: usize = 0;
                var shift: u6 = 0;
                while (pos < data.len) {
                    const byte = data[pos];
                    pos += 1;
                    len |= @as(usize, byte & 0x7F) << shift;
                    if ((byte & 0x80) == 0) break;
                    shift += 7;
                }

                // Count directives (field 1) and errors (field 2)
                if (field_number == 1) {
                    directive_count += 1;
                } else if (field_number == 2) {
                    error_count += 1;
                }

                // Skip the data
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
        const field_num_u64 = tag >> 3;

        // Protobuf field numbers must be <= 2^29 - 1
        if (field_num_u64 > 536870911) {
            return error.InvalidFieldNumber;
        }

        const field_number = @as(u32, @intCast(field_num_u64));
        const wire_type_int = @as(u3, @intCast(tag & 0x07));
        const wire_type = @as(WireType, @enumFromInt(wire_type_int));

        return .{ .field_number = field_number, .wire_type = wire_type };
    }

    /// Read length-delimited bytes
    fn readBytes(self: *Decoder) ![]const u8 {
        const len = try self.readVarint();

        // Check if len fits in usize
        if (len > std.math.maxInt(usize)) {
            return error.MessageTooLarge;
        }

        const len_usize = @as(usize, @intCast(len));
        const start = self.pos;

        // Check for overflow in addition
        const end = std.math.add(usize, start, len_usize) catch {
            return error.MessageTooLarge;
        };

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
                if (len > std.math.maxInt(usize)) {
                    return error.MessageTooLarge;
                }
                const len_usize = @as(usize, @intCast(len));
                const end = std.math.add(usize, self.pos, len_usize) catch {
                    return error.MessageTooLarge;
                };
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

/// Decode a Date message from length-delimited bytes
fn decodeDate(allocator: std.mem.Allocator, data: []const u8) !proto.Date {
    var decoder = Decoder.init(allocator, data);
    var date = proto.Date{ .year = 0, .month = 0, .day = 0 };

    while (try decoder.readTag()) |tag| {
        switch (tag.field_number) {
            1 => { // year
                if (tag.wire_type != .varint) return error.InvalidWireType;
                const varint = try decoder.readVarint();
                if (varint > std.math.maxInt(i32)) return error.ValueOutOfRange;
                date.year = @as(i32, @intCast(varint));
            },
            2 => { // month
                if (tag.wire_type != .varint) return error.InvalidWireType;
                const varint = try decoder.readVarint();
                if (varint > std.math.maxInt(i32)) return error.ValueOutOfRange;
                date.month = @as(i32, @intCast(varint));
            },
            3 => { // day
                if (tag.wire_type != .varint) return error.InvalidWireType;
                const varint = try decoder.readVarint();
                if (varint > std.math.maxInt(i32)) return error.ValueOutOfRange;
                date.day = @as(i32, @intCast(varint));
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
                const varint = try decoder.readVarint();
                if (varint > std.math.maxInt(i32)) return error.ValueOutOfRange;
                line = @as(i32, @intCast(varint));
            },
            3 => { // column
                if (tag.wire_type != .varint) return error.InvalidWireType;
                const varint = try decoder.readVarint();
                if (varint > std.math.maxInt(i32)) return error.ValueOutOfRange;
                column = @as(i32, @intCast(varint));
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

    // Validate required fields
    if (account.len == 0) {
        return error.MissingRequiredField;
    }

    return proto.Posting{
        .account = account,
        .amount = amount,
        .cost = cost,
        .price = price,
        .flag = flag,
    };
}

/// Decode a Transaction message from length-delimited bytes
fn decodeTransaction(allocator: std.mem.Allocator, data: []const u8) !proto.Transaction {
    var decoder = Decoder.init(allocator, data);
    var date = proto.Date{ .year = 0, .month = 0, .day = 0 };
    var flag: ?[]u8 = null;
    var payee: ?[]u8 = null;
    var narration: []u8 = &[_]u8{};
    var tags: std.ArrayList([]const u8) = .{};
    errdefer tags.deinit(allocator);
    var links: std.ArrayList([]const u8) = .{};
    errdefer links.deinit(allocator);
    var postings: std.ArrayList(proto.Posting) = .{};
    errdefer postings.deinit(allocator);
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
                try tags.append(allocator, tag_str);
            },
            6 => { // links (repeated)
                if (tag.wire_type != .length_delimited) return error.InvalidWireType;
                const link_str = try decoder.readString();
                try links.append(allocator, link_str);
            },
            7 => { // postings (repeated)
                if (tag.wire_type != .length_delimited) return error.InvalidWireType;
                const posting_bytes = try decoder.readBytes();
                const posting = try decodePosting(allocator, posting_bytes);
                try postings.append(allocator, posting);
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

    // Validate required fields
    if (narration.len == 0) {
        return error.MissingRequiredField;
    }

    return proto.Transaction{
        .date = date,
        .flag = flag,
        .payee = payee,
        .narration = narration,
        .tags = try tags.toOwnedSlice(allocator),
        .links = try links.toOwnedSlice(allocator),
        .postings = try postings.toOwnedSlice(allocator),
        .location = location,
    };
}

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

/// Decode an Open message from length-delimited bytes
fn decodeOpen(allocator: std.mem.Allocator, data: []const u8) !proto.Open {
    var decoder = Decoder.init(allocator, data);
    var date = proto.Date{ .year = 0, .month = 0, .day = 0 };
    var account: []u8 = &[_]u8{};
    var currencies: std.ArrayList([]const u8) = .{};
    errdefer currencies.deinit(allocator);
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
                try currencies.append(allocator, currency);
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
        .currencies = try currencies.toOwnedSlice(allocator),
        .location = location,
    };
}

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

const std = @import("std");

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
};

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

/// ProcessRequest message encoder (simplified - without directives)
pub fn encodeProcessRequest(
    allocator: std.mem.Allocator,
    input_file: []const u8,
    options_map: std.StringHashMap([]const u8),
) ![]u8 {
    var encoder = Encoder.init(allocator);
    defer encoder.deinit();

    // Field 1: repeated Directive directives = 1; (empty for now)
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

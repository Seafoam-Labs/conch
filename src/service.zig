const std = @import("std");
const goose = @import("goose");

const Connection = goose.Connection;

pub const Service = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    conn: Connection,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, env_map: *std.process.Environ.Map) !Service {
        const conn = try Connection.init(allocator, .Session, io, env_map);
        return .{
            .allocator = allocator,
            .io = io,
            .conn = conn,
        };
    }

    pub fn deinit(self: *Service) void {
        self.conn.close();
    }

    pub fn connection(self: *Service) *Connection {
        return &self.conn;
    }

    pub fn run(self: *Service, handle: usize) !void {
        try self.conn.waitOnHandle(handle);
    }

    pub fn dispatchOne(self: *Service) !void {
        var msg = try self.conn.waitMessage();
        self.conn.freeMessage(&msg);
    }

    pub fn waitMessageTimeout(self: *Service, timeout: std.Io.Timeout) !?goose.core.Message {
        return self.conn.waitMessageTimeout(timeout);
    }

    pub fn tickTimeout(self: *Service, timeout: std.Io.Timeout) !bool {
        return self.conn.tickTimeout(timeout);
    }

    pub fn runEventLoop(self: *Service, comptime tick_ms: u64, ctx: anytype, comptime onTick: fn (@TypeOf(ctx)) void) !void {
        while (true) {
            _ = try self.tickTimeout(.{ .duration = .fromMillis(tick_ms) });
            onTick(ctx);
        }
    }

    pub fn processNext(self: *Service) !void {
        while (true) try self.dispatchOne();
    }
};

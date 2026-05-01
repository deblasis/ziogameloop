//! Fixed-timestep game loop with variable rendering.
//!
//! Implements the "Fix Your Timestep" pattern: accumulator-based fixed update
//! with interpolation for smooth rendering. Frame rate control optional.

const std = @import("std");

/// Configuration for the game loop.
pub const Config = struct {
    /// Fixed update rate in updates per second (e.g., 60).
    tick_rate: u32 = 60,
    /// Maximum number of catch-up updates per frame (prevents spiral of death).
    max_catchup: u32 = 5,
    /// Target frame rate for rendering (0 = uncapped).
    target_fps: u32 = 0,
};

/// State for a fixed-timestep game loop.
pub const GameLoop = struct {
    tick_dt_ns: u64,
    max_catchup: u32,
    target_frame_ns: u64,
    accumulator_ns: u64,
    frame_count: u64,
    update_count: u64,
    last_time_ns: ?u64,

    pub fn init(config: Config) @This() {
        const tick_dt_ns: u64 = std.time.ns_per_s / config.tick_rate;
        const target_frame_ns: u64 = if (config.target_fps > 0)
            std.time.ns_per_s / config.target_fps
        else
            0;
        return .{
            .tick_dt_ns = tick_dt_ns,
            .max_catchup = config.max_catchup,
            .target_frame_ns = target_frame_ns,
            .accumulator_ns = 0,
            .frame_count = 0,
            .update_count = 0,
            .last_time_ns = null,
        };
    }

    /// Tick result — tells you what to do this frame.
    pub const TickResult = struct {
        /// Number of fixed updates to run.
        updates: u32,
        /// Alpha value for interpolation (0..1).
        alpha: f32,
        /// Time to sleep before next frame (0 if uncapped).
        sleep_ns: u64,
    };

    /// Feed current time, get back what to do.
    /// `now_ns` is a monotonic timestamp in nanoseconds.
    pub fn tick(self: *@This(), now_ns: u64) TickResult {
        if (self.last_time_ns == null) {
            self.last_time_ns = now_ns;
            return .{ .updates = 0, .alpha = 0, .sleep_ns = 0 };
        }

        const dt = now_ns - self.last_time_ns.?;
        self.last_time_ns = now_ns;
        self.accumulator_ns += dt;
        self.frame_count += 1;

        var updates: u32 = 0;
        var catchup: u32 = 0;
        while (self.accumulator_ns >= self.tick_dt_ns and catchup < self.max_catchup) {
            self.accumulator_ns -= self.tick_dt_ns;
            updates += 1;
            catchup += 1;
            self.update_count += 1;
        }

        const alpha: f32 = if (self.tick_dt_ns > 0)
            @as(f32, @floatFromInt(self.accumulator_ns)) / @as(f32, @floatFromInt(self.tick_dt_ns))
        else
            0;

        const sleep_ns: u64 = if (self.target_frame_ns > 0 and dt < self.target_frame_ns)
            self.target_frame_ns - dt
        else
            0;

        return .{ .updates = updates, .alpha = alpha, .sleep_ns = sleep_ns };
    }

    /// Total updates processed.
    pub fn totalUpdates(self: *const @This()) u64 {
        return self.update_count;
    }

    /// Total frames rendered.
    pub fn totalFrames(self: *const @This()) u64 {
        return self.frame_count;
    }
};

/// Simple delta-time tracker for variable-step loops.
pub const DeltaTracker = struct {
    last_ns: ?u64,
    dt_ns: u64,
    dt_sec: f32,

    pub fn init() @This() {
        return .{ .last_ns = null, .dt_ns = 0, .dt_sec = 0 };
    }

    pub fn update(self: *@This(), now_ns: u64) void {
        if (self.last_ns) |last| {
            self.dt_ns = now_ns - last;
            self.dt_sec = @as(f32, @floatFromInt(self.dt_ns)) / @as(f32, @floatFromInt(std.time.ns_per_s));
        }
        self.last_ns = now_ns;
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "GameLoop init" {
    const loop = GameLoop.init(.{ .tick_rate = 60 });
    try std.testing.expectEqual(@as(u64, std.time.ns_per_s / 60), loop.tick_dt_ns);
    try std.testing.expect(loop.last_time_ns == null);
}

test "GameLoop first tick returns zero updates" {
    var loop = GameLoop.init(.{ .tick_rate = 60 });
    const result = loop.tick(0);
    try std.testing.expectEqual(@as(u32, 0), result.updates);
}

test "GameLoop triggers update after tick interval" {
    var loop = GameLoop.init(.{ .tick_rate = 60 });
    _ = loop.tick(0); // initialize

    const dt = std.time.ns_per_s / 60; // exactly one tick
    const result = loop.tick(dt);
    try std.testing.expectEqual(@as(u32, 1), result.updates);
    try std.testing.expect(result.alpha >= 0 and result.alpha <= 1);
}

test "GameLoop accumulator carries over" {
    var loop = GameLoop.init(.{ .tick_rate = 60 });
    _ = loop.tick(0);

    const half_tick = (std.time.ns_per_s / 60) / 2;
    const r1 = loop.tick(half_tick);
    try std.testing.expectEqual(@as(u32, 0), r1.updates);

    const r2 = loop.tick(half_tick * 2);
    try std.testing.expectEqual(@as(u32, 1), r2.updates);
}

test "GameLoop max catchup prevents spiral" {
    var loop = GameLoop.init(.{ .tick_rate = 60, .max_catchup = 3 });
    _ = loop.tick(0);

    // Jump ahead by 10 ticks
    const big_dt = (std.time.ns_per_s / 60) * 10;
    const result = loop.tick(big_dt);
    try std.testing.expectEqual(@as(u32, 3), result.updates); // capped
}

test "GameLoop alpha interpolation" {
    var loop = GameLoop.init(.{ .tick_rate = 60 });
    _ = loop.tick(0);

    const three_quarters = (std.time.ns_per_s / 60) * 3 / 4;
    const result = loop.tick(three_quarters);
    try std.testing.expectEqual(@as(u32, 0), result.updates);
    try std.testing.expect(result.alpha > 0.5);
}

test "GameLoop frame rate cap" {
    var loop = GameLoop.init(.{ .tick_rate = 60, .target_fps = 120 });
    _ = loop.tick(0);

    // Very small dt — should suggest sleeping
    const result = loop.tick(1000); // 1µs
    try std.testing.expect(result.sleep_ns > 0);
}

test "GameLoop totalUpdates tracks count" {
    var loop = GameLoop.init(.{ .tick_rate = 60 });
    _ = loop.tick(0);
    _ = loop.tick(std.time.ns_per_s / 60);
    _ = loop.tick(std.time.ns_per_s / 60 * 2);
    try std.testing.expect(loop.totalUpdates() >= 1);
    try std.testing.expect(loop.totalFrames() >= 1);
}

test "DeltaTracker" {
    var dt = DeltaTracker.init();
    dt.update(0);
    dt.update(std.time.ns_per_s / 60);
    try std.testing.expectApproxEqAbs(@as(f32, 1.0 / 60.0), dt.dt_sec, 0.001);
}

test "DeltaTracker first update has zero dt" {
    var dt = DeltaTracker.init();
    dt.update(1000000);
    try std.testing.expectEqual(@as(u64, 0), dt.dt_ns);
}

test "GameLoop tick_dt_ns calculation" {
    const loop = GameLoop.init(.{ .tick_rate = 30 });
    try std.testing.expectEqual(@as(u64, std.time.ns_per_s / 30), loop.tick_dt_ns);
}

test "GameLoop multiple updates in one big jump" {
    var loop = GameLoop.init(.{ .tick_rate = 60 });
    _ = loop.tick(0);
    // Jump ahead 5 ticks worth of time
    const result = loop.tick(std.time.ns_per_s / 60 * 5);
    try std.testing.expect(result.updates >= 1);
    try std.testing.expect(result.updates <= 5); // capped by max_catchup
}

test "GameLoop alpha is 0 after exact tick" {
    var loop = GameLoop.init(.{ .tick_rate = 60 });
    _ = loop.tick(0);
    const result = loop.tick(std.time.ns_per_s / 60);
    try std.testing.expect(result.alpha < 0.01);
}

test "DeltaTracker multiple updates" {
    var dt = DeltaTracker.init();
    dt.update(0);
    dt.update(500_000); // 0.5ms
    dt.update(1_500_000); // 1ms later
    try std.testing.expectEqual(@as(u64, 1_000_000), dt.dt_ns);
    try std.testing.expectApproxEqAbs(@as(f32, 0.001), dt.dt_sec, 0.0001);
}

test "GameLoop config defaults" {
    const config = Config{};
    try std.testing.expectEqual(@as(u32, 60), config.tick_rate);
    try std.testing.expectEqual(@as(u32, 5), config.max_catchup);
    try std.testing.expectEqual(@as(u32, 0), config.target_fps);
}

test "GameLoop totalFrames increments" {
    var loop = GameLoop.init(.{ .tick_rate = 60 });
    _ = loop.tick(0);
    _ = loop.tick(std.time.ns_per_s / 60);
    _ = loop.tick(std.time.ns_per_s / 60 * 2);
    try std.testing.expect(loop.totalFrames() >= 2);
}

test "DeltaTracker sub-millisecond" {
    var dt = DeltaTracker.init();
    dt.update(0);
    dt.update(1); // 1 nanosecond
    try std.testing.expectEqual(@as(u64, 1), dt.dt_ns);
    try std.testing.expect(dt.dt_sec > 0);
}

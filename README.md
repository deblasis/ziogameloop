# ziogameloop

> Fixed-timestep game loop for Zig. Accumulator-based update, frame rate control.

Part of the [zio-zig](https://github.com/deblasis/zio-zig) ecosystem.

## Quick start

```zig
const gameloop = @import("ziogameloop");

var loop = gameloop.GameLoop.init(.{
    .tick_rate = 60,       // 60 updates per second
    .max_catchup = 5,      // max updates per frame to prevent spiral
});

var dt = gameloop.DeltaTracker.init();

// Game loop
var ns: u64 = 0;
while (true) {
    const now = std.time.nanoTimestamp();
    dt.update(@intCast(now));
    ns += @intCast(dt.dt_ns);

    const result = loop.tick(ns);
    
    // Fixed-rate update (may run multiple times)
    for (0..result.updates) |_| {
        updatePhysics();
    }
    
    // Variable-rate render with interpolation
    render(result.alpha); // alpha ∈ [0, 1] for smooth rendering
}
```

```bash
zig build test          # Run 37 tests
zig build run-example   # Run example
```

## API

### Config

| Field | Default | Description |
|-------|---------|-------------|
| `tick_rate` | 60 | Updates per second |
| `max_catchup` | 5 | Max updates per frame |
| `target_fps` | 0 | 0 = unlimited |

### GameLoop

| Method | Description |
|--------|-------------|
| `init(config)` | Create game loop |
| `tick(current_ns)` | Process frame, returns `TickResult` |
| `totalFrames()` | Total frames processed |
| `totalUpdates()` | Total fixed updates run |

### TickResult

| Field | Description |
|-------|-------------|
| `updates` | Number of fixed updates to run this frame |
| `alpha` | Interpolation factor [0, 1] for smooth rendering |

### DeltaTracker

Tracks frame-to-frame delta time.

| Method | Description |
|--------|-------------|
| `init()` | Create tracker |
| `update(current_ns)` | Update delta |
| `dt_ns` | Delta time in nanoseconds |
| `dt_sec` | Delta time in seconds (f32) |

## License

MIT. Copyright (c) 2026 Alessandro De Blasis.

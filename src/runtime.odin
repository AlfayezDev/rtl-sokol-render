package main
import "base:runtime"
import "core:c"
import "core:log"
import "core:mem/virtual"
import rl "vendor:raylib"
import stbsp "vendor:stb/sprintf"

logger: log.Logger
arena: virtual.Arena


g_ctx: runtime.Context
main :: proc() {

	arenaErr := virtual.arena_init_static(&arena)
	assert(arenaErr == nil)
	arenaAlloc := virtual.arena_allocator(&arena)
	context.allocator = arenaAlloc

	logger = log.create_console_logger()
	context.logger = logger
	g_ctx = context

	rl.SetTraceLogLevel(.ALL)
	rl.SetTraceLogCallback(
		proc "c" (rl_level: rl.TraceLogLevel, message: cstring, args: ^c.va_list) {
			context = g_ctx

			level: log.Level
			switch rl_level {
			case .TRACE, .DEBUG:
				level = .Debug
			case .INFO:
				level = .Info
			case .WARNING:
				level = .Warning
			case .ERROR:
				level = .Error
			case .FATAL:
				level = .Fatal
			case .ALL, .NONE:
				fallthrough
			case:
				log.panicf("unexpected log level %v", rl_level)
			}

			@(static) buf: [dynamic]byte
			log_len: i32
			for {
				buf_len := i32(len(buf))
				log_len = stbsp.vsnprintf(raw_data(buf), buf_len, message, args)
				if log_len <= buf_len {
					break
				}

				non_zero_resize(&buf, max(128, len(buf) * 2))
			}

			context.logger.procedure(
				context.logger.data,
				level,
				string(buf[:log_len]),
				context.logger.options,
			)
		},
	)
	rl.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, SCREEN_TITLE)
	setup()
	rl.SetTargetFPS(60)
	for !rl.WindowShouldClose() {
		frame()
		draw()
	}
	rl.CloseWindow()
}

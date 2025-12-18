package main
import "base:runtime"
import "core:log"
import "core:mem/virtual"

logger: log.Logger
arena: virtual.Arena
main :: proc() {

	arena_err := virtual.arena_init_static(&arena)
	assert(arena_err == nil)
	arena_alloc := virtual.arena_allocator(&arena)
	context.allocator = arena_alloc

	logger = log.create_console_logger()
	context.logger = logger

}

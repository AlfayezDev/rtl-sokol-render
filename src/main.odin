package main
import "base:runtime"
import "core:dynlib"
import "core:fmt"
import "core:log"
import "core:mem/virtual"
import "core:os/os2"
import "core:time"
import game "game"
import libs "libs:/"
import sapp "libs:sokol/app"
import shelper "libs:sokol/helpers"

logger: log.Logger
arena: virtual.Arena
frameArena: virtual.Arena
g_ctx: runtime.Context
lastCheck: time.Time
lockGame := false
gameSetup := game.setup
gameFrame := game.frame
gameShutdown := game.shutdown
when ODIN_OS == .Windows {
	DLL_EXT :: ".dll"
} else when ODIN_OS == .Darwin {
	DLL_EXT :: ".dylib"
} else {
	DLL_EXT :: ".so"
}

dllVersion: int
GAME_DLL_DIR :: "build/dll/"
GAME_DLL_PATH :: GAME_DLL_DIR + "game" + DLL_EXT
Game_API :: struct {
	lib:         dynlib.Library,
	setup:       proc(),
	frame:       proc(),
	event:       proc(e: ^sapp.Event),
	shutdown:    proc(),
	api_version: int,
}
copyDll :: proc(to: string) -> bool {
	copy_err := os2.copy_file(to, GAME_DLL_PATH)
	return copy_err == nil
}
loadGameApi :: proc() -> bool {
	gameDllName := fmt.tprintf(GAME_DLL_DIR + "game_{0}" + DLL_EXT, dllVersion)
	copyDll(gameDllName) or_return
	api: Game_API
	_, ok := dynlib.initialize_symbols(&api, gameDllName, "game_", "lib")
	if !ok {
		log.errorf("Failed initializing symbols: {0}", dynlib.last_error())
	}
	gameSetup = api.setup
	gameShutdown = api.shutdown
	gameFrame = api.frame
	return true
}
reload :: proc() {
	lockGame = true
	gameShutdown()
	loadGameApi()
	gameSetup()
	dllVersion += 1
	lockGame = false

}
main :: proc() {

	arenaErr := virtual.arena_init_static(&arena)
	assert(arenaErr == nil)
	_ = virtual.arena_init_growing(&arena)
	context.allocator = virtual.arena_allocator(&arena)
	_ = virtual.arena_init_growing(&frameArena)
	context.temp_allocator = virtual.arena_allocator(&frameArena)
	logger = log.create_console_logger()
	context.logger = logger
	g_ctx = context

	lastCheck = time.now()
	sapp.run(sapp.Desc {
		logger = sapp.Logger(shelper.logger(&g_ctx)),
		allocator = sapp.Allocator(shelper.allocator(&g_ctx)),
		init_cb = proc "c" () {
			context = g_ctx
			gameSetup()
		},
		frame_cb = proc "c" () {
			context = g_ctx
			if lockGame {
				return
			}
			free_all(context.temp_allocator)

			if libs.watchDirectory(GAME_DLL_DIR, &lastCheck, {DLL_EXT}, context.temp_allocator) {
				log.info("Rebuilding...")
				reload()
				return
			}
			gameFrame()
		},
		cleanup_cb = proc "c" () {
			context = g_ctx
			gameShutdown()
		},
		event_cb = proc "c" (e: ^sapp.Event) {
			context = g_ctx
			if e.type == .KEY_DOWN && e.key_code == .ESCAPE {
				sapp.request_quit()
			}

		},
		icon = {sokol_default = true},
		width = 1080,
		height = 920,
	})
}

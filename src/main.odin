package main
import "base:runtime"
import "core:dynlib"
import "core:fmt"
import "core:log"
import "core:mem/virtual"
import "core:os/os2"
import "core:time"
import libs "libs:/"
import sapp "libs:sokol/app"
import shelper "libs:sokol/helpers"

logger: log.Logger
arena: virtual.Arena
frameArena: virtual.Arena
g_ctx: runtime.Context
lastCheck: time.Time
lockGame := false
when ODIN_OS == .Windows {
	DLL_EXT :: ".dll"
} else when ODIN_OS == .Darwin {
	DLL_EXT :: ".dylib"
} else {
	DLL_EXT :: ".so"
}

dllVersion: int = 0
GAME_DLL_DIR :: "build/dll/"
GAME_DLL_PATH :: GAME_DLL_DIR + "game" + DLL_EXT
Game_API :: struct {
	lib:         dynlib.Library,
	setup:       proc "c" (ctx: ^runtime.Context),
	frame:       proc "c" (),
	event:       proc "c" (e: ^sapp.Event),
	shutdown:    proc "c" (),
	api_version: int,
}
api: Game_API
copyDll :: proc(to: string) -> bool {
	copy_err := os2.copy_file(to, GAME_DLL_PATH)
	if copy_err != nil {
		log.errorf("Copying to %v failed error %v", to, copy_err)
	}
	return copy_err == nil
}
loadGameApi :: proc() -> bool {
	gameDllName := fmt.tprintf(GAME_DLL_DIR + "game_{0}" + DLL_EXT, dllVersion)
	copyDll(gameDllName) or_return
	log.info("Loading", gameDllName)
	_, ok := dynlib.initialize_symbols(&api, gameDllName, "game_", "lib")
	if !ok {
		log.errorf("Failed initializing symbols: {0}", dynlib.last_error())
	}
	api.api_version = dllVersion
	return true
}
unload_game_api :: proc() {

	if api.lib != nil {
		if !dynlib.unload_library(api.lib) {
			fmt.printfln("Failed unloading lib: {0}", dynlib.last_error())
		}
	}

	if os2.remove(fmt.tprintf(GAME_DLL_DIR + "game_{0}" + DLL_EXT, api.api_version)) != nil {
		fmt.printfln(
			"Failed to remove {0}game_{1}" + DLL_EXT + " copy",
			GAME_DLL_DIR,
			api.api_version,
		)
	}
}
reload :: proc() {
	lockGame = true
	if dllVersion > 0 {
		api.shutdown()
		unload_game_api()
	}
	loadGameApi()
	api.setup(&g_ctx)
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
			reload()
		},
		frame_cb = proc "c" () {
			context = g_ctx
			if lockGame {
				return
			}
			free_all(context.temp_allocator)

			if libs.watchDirectory(GAME_DLL_DIR, &lastCheck, {DLL_EXT}, context.temp_allocator) {
				log.info("Reloading...")
				reload()
				return
			}
			api.frame()
		},
		cleanup_cb = proc "c" () {
			context = g_ctx
			api.shutdown()
		},
		event_cb = proc "c" (e: ^sapp.Event) {
			context = g_ctx
			if e.type == .KEY_DOWN && e.key_code == .ESCAPE {
				sapp.request_quit()
			}
			if api.event != nil {
				api.event(e)
			}
		},
		icon = {sokol_default = true},
		width = 1080,
		height = 920,
	})
}

package main
import "base:runtime"
import "core:c"
import "core:log"
import rl "vendor:raylib"
import stbsp "vendor:stb/sprintf"

SCREEN_WIDTH :: 800
SCREEN_HEIGHT :: 450

g_ctx: runtime.Context
setup :: proc() {
	context.logger = log.create_console_logger(.Debug)
}
shutdown::proc(){

}

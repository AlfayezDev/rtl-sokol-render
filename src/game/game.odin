package game
import "base:runtime"
import log "core:log"
import sapp "libs:sokol/app"
import sdt "libs:sokol/debugtext"
import sg "libs:sokol/gfx"
import sgl "libs:sokol/gl"
import sglue "libs:sokol/glue"
import shelper "libs:sokol/helpers"

SCREEN_WIDTH :: 800
SCREEN_HEIGHT :: 600

g_ctx: runtime.Context
typography: Typography
sokolInitialized := false

setup :: proc(firstLoad: bool) {
	ctx := context
	if firstLoad {
		sg.setup(
			sg.Desc {
				environment = sglue.environment(),
				logger = sg.Logger(shelper.logger(&ctx)),
				allocator = sg.Allocator(shelper.allocator(&ctx)),
			},
		)
		sgl.setup(
			sgl.Desc {
				logger = sgl.Logger(shelper.logger(&ctx)),
				allocator = sgl.Allocator(shelper.allocator(&ctx)),
			},
		)
		sdt.setup(
			sdt.Desc {
				logger = sdt.Logger(shelper.logger(&ctx)),
				allocator = sdt.Allocator(shelper.allocator(&ctx)),
			},
		)
	}
	if typographySetup(&typography) == false {
		log.error("FAILED TO LOAD TYPOGRAPHY")
	}
	log.info("Setup complete")
}
frame :: proc() {
	w := sapp.widthf()
	h := sapp.heightf()

	sgl.defaults()
	sgl.matrix_mode_projection()
	sgl.ortho(0, w, h, 0, -1, 1)
	sgl.matrix_mode_modelview()
	typographyBeginFrame(&typography)
	text(&typography, "Hello123 World!", 0, 10)
	text(&typography, "مرحبا بالعالم", 50, 100)
	text(&typography, "More text", 50, 150, {255, 0, 0, 255})
	typographyEndFrame(&typography)
	sg.begin_pass(
		{
			action = {colors = {0 = {load_action = .CLEAR, clear_value = {0.1, 0.1, 0.15, 1}}}},
			swapchain = sglue.swapchain(),
		},
	)
	sgl.draw()
	sg.end_pass()
	sg.commit()
}

shutdown :: proc(finalShutdown: bool) {
	typographyShutdown(&typography)
	log.info("Shutting down")
	if finalShutdown {
		sdt.shutdown()
		sgl.shutdown()
		sg.shutdown()
	}
}
@(export)
game_setup :: proc "c" (ctx: ^runtime.Context, firstLoad: bool) {
	g_ctx = ctx^
	context = g_ctx
	setup(firstLoad)
}

@(export)
game_shutdown :: proc "c" (finalShutdown: bool) {
	context = g_ctx
	shutdown(finalShutdown)
}

@(export)
game_frame :: proc "c" () {
	context = g_ctx
	frame()
}

@(export)
game_event :: proc "c" (e: ^sapp.Event) {
	context = g_ctx
	// handle events here
}

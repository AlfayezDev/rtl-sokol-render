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

ctx: runtime.Context
typography: Typography

setup :: proc() {
	log.info("Setup sg")
	sg.setup(
		sg.Desc {
			environment = sglue.environment(),
			logger = sg.Logger(shelper.logger(&ctx)),
			allocator = sg.Allocator(shelper.allocator(&ctx)),
		},
	)
	log.info("Setup sgl")
	sgl.setup(
		sgl.Desc {
			logger = sgl.Logger(shelper.logger(&ctx)),
			allocator = sgl.Allocator(shelper.allocator(&ctx)),
		},
	)
	log.info("Setup sdt")
	sdt.setup(
		sdt.Desc {
			logger = sdt.Logger(shelper.logger(&ctx)),
			allocator = sdt.Allocator(shelper.allocator(&ctx)),
		},
	)
	log.info("Setup typography")
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
	text(&typography, "H11ello123 World!", 100, 50)
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

shutdown :: proc() {
	typographyShutdown(&typography)
	sdt.shutdown()
	log.info("Shutting sgl")
	sgl.shutdown()
	log.info("Shutting sg")
	sg.shutdown()
	log.info("Shutdown Complete")
}
@(export)
game_setup :: proc "c" (_ctx: ^runtime.Context) {
	ctx = _ctx^
	context = ctx
	setup()
}

@(export)
game_shutdown :: proc "c" () {
	context = ctx
	shutdown()
}

@(export)
game_frame :: proc "c" () {
	context = ctx
	frame()
}

@(export)
game_event :: proc "c" (e: ^sapp.Event) {
	context = ctx
	// handle events here
}

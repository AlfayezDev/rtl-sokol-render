package main
import log "core:log"
import sg "libs:sokol/gfx"
import sgl "libs:sokol/gl"
import sglue "libs:sokol/glue"

SCREEN_WIDTH :: 800
SCREEN_HEIGHT :: 600


setup :: proc() {
	typography_setup()
	log.info("Setup complete")
}
frame :: proc() {
	sgl.disable_texture()
	sgl.begin_quads()
	sgl.c4b(255, 0, 0, 255)
	sgl.v2f(100, 100)
	sgl.v2f(200, 100)
	sgl.v2f(200, 200)
	sgl.v2f(100, 200)
	sgl.end()
	text("Hello World!", 50, 50)
	// text("مرحبا بالعالم", 50, 100)
}
draw :: proc() {
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
}

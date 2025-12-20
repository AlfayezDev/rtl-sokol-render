package main
import log "core:log"
import ig "libs:imgui"

SCREEN_WIDTH :: 800
SCREEN_HEIGHT :: 600


setup :: proc() {
	log.info("Setup complete")
}
frame :: proc() {
	text("Hello World!", 50, 50)
	text("مرحبا بالعالم", 50, 100)
	text("More text", 50, 150, {255, 0, 0, 255})
	ig.ShowDemoWindow()


}

shutdown :: proc() {
}

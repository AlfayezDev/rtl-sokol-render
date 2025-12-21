package main
import log "core:log"

SCREEN_WIDTH :: 800
SCREEN_HEIGHT :: 600


setup :: proc() {
	log.info("Setup complete")
}
frame :: proc() {
	text(&typography, "Hello World!", 0, 10)
	text(&typography, "مرحبا بالعالم", 50, 100)
	text(&typography, "More text", 50, 150, {255, 0, 0, 255})
}

shutdown :: proc() {
}

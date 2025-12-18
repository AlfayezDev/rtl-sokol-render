package main
import rl "vendor:raylib"

SCREEN_WIDTH :: 800
SCREEN_TITLE :: "Window"
SCREEN_HEIGHT :: 450

setup :: proc() {
}
frame :: proc() {
}
draw :: proc() {
	rl.BeginDrawing()
	rl.DrawFPS(0, 0)
	rl.ClearBackground(rl.BLACK)
	rl.EndDrawing()
}
shutdown :: proc() {}

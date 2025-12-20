package main
import "base:runtime"
import "core:log"
import "core:mem/virtual"
import sapp "libs:sokol/app"
import sdt "libs:sokol/debugtext"
import sg "libs:sokol/gfx"
import sgl "libs:sokol/gl"
import sglue "libs:sokol/glue"
import shelper "libs:sokol/helpers"

logger: log.Logger
arena: virtual.Arena

g_ctx: runtime.Context
main :: proc() {

	arenaErr := virtual.arena_init_static(&arena)
	assert(arenaErr == nil)
	arenaAlloc := virtual.arena_allocator(&arena)
	context.allocator = arenaAlloc

	logger = log.create_console_logger()
	context.logger = logger
	g_ctx = context

	sapp.run(sapp.Desc {
		logger = sapp.Logger(shelper.logger(&g_ctx)),
		allocator = sapp.Allocator(shelper.allocator(&g_ctx)),
		init_cb = proc "c" () {
			context = g_ctx
			sg.setup(
				sg.Desc {
					environment = sglue.environment(),
					logger = sg.Logger(shelper.logger(&g_ctx)),
					allocator = sg.Allocator(shelper.allocator(&g_ctx)),
				},
			)
			sgl.setup(
				sgl.Desc {
					logger = sgl.Logger(shelper.logger(&g_ctx)),
					allocator = sgl.Allocator(shelper.allocator(&g_ctx)),
				},
			)
			sdt.setup(
				sdt.Desc {
					logger = sdt.Logger(shelper.logger(&g_ctx)),
					allocator = sdt.Allocator(shelper.allocator(&g_ctx)),
				},
			)
			setup()

		},
		frame_cb = proc "c" () {
			context = g_ctx
			w := sapp.widthf()
			h := sapp.heightf()

			sgl.defaults()
			sgl.matrix_mode_projection()
			sgl.ortho(0, w, h, 0, -1, 1)
			sgl.matrix_mode_modelview()
			frame()
			draw()
		},
		cleanup_cb = proc "c" () {
			context = g_ctx
			shutdown()
			sdt.shutdown()
			sgl.shutdown()
			sg.shutdown()
		},
		icon = {sokol_default = true},
		width = 800,
		height = 600,
	})
}

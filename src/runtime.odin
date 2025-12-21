package main
import "base:runtime"
import "core:log"
import "core:mem/virtual"
import sapp "libs:sokol/app"
import cimgui "libs:sokol/cimgui"
import sdt "libs:sokol/debugtext"
import sg "libs:sokol/gfx"
import sgl "libs:sokol/gl"
import sglue "libs:sokol/glue"
import shelper "libs:sokol/helpers"

logger: log.Logger
arena: virtual.Arena
frameArena: virtual.Arena

g_ctx: runtime.Context
cimguiContext: ^cimgui.Context
typography: Typography
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
			if typographySetup(&typography) == false {
				log.error("FAILED TO LOAD TYPOGRAPHY")
			}
			cimguiContext = cimgui.setup()
			setup()

		},
		frame_cb = proc "c" () {
			context = g_ctx
			free_all(context.temp_allocator)


			w := sapp.widthf()
			h := sapp.heightf()

			sgl.defaults()
			sgl.matrix_mode_projection()
			sgl.ortho(0, w, h, 0, -1, 1)
			sgl.matrix_mode_modelview()
			cimgui.new_frame(
				{
					width = sapp.width(),
					height = sapp.height(),
					delta_time = sapp.frame_duration(),
					dpi_scale = sapp.dpi_scale(),
				},
			)
			typographyBeginFrame(&typography)
			frame()
			typographyEndFrame(&typography)
			sg.begin_pass(
				{
					action = {
						colors = {0 = {load_action = .CLEAR, clear_value = {0.1, 0.1, 0.15, 1}}},
					},
					swapchain = sglue.swapchain(),
				},
			)
			sgl.draw()
			cimgui.render()
			sg.end_pass()
			sg.commit()
		},
		cleanup_cb = proc "c" () {
			context = g_ctx
			shutdown()
			typographyShutdown(&typography)
			cimgui.shutdown()
			sdt.shutdown()
			sgl.shutdown()
			sg.shutdown()
		},
		event_cb = proc "c" (e: ^sapp.Event) {
			context = g_ctx
			if cimgui.handle_event(e) {
				return
			}

			if e.type == .KEY_DOWN && e.key_code == .ESCAPE {
				sapp.request_quit()
			}

		},
		icon = {sokol_default = true},
		width = 1080,
		height = 920,
	})
}

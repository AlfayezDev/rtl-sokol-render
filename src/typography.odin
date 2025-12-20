package main

import "base:runtime"
import "core:log"
import sg "libs:sokol/gfx"
import sgl "libs:sokol/gl"
import fons "vendor:fontstash"
import kbts "vendor:kb_text_shape"

FONT_SIZE :: 32.0
FONT_DATA :: #load("/System/Library/Fonts/Supplemental/Arial Unicode.ttf")
shapeContext: ^kbts.shape_context
fontContext: ^fons.FontContext
typographySampler: sg.Sampler
OdinAllocator: runtime.Allocator
typography_setup :: proc() {
	OdinAllocator = context.allocator
	shapeContext = kbts.CreateShapeContext(kbts.AllocatorFromOdinAllocator(&OdinAllocator))
	if shapeContext == nil {
		log.error("Failed to create shape context")
		return
	}
	kbts.ShapePushFontFromMemory(shapeContext, FONT_DATA, 1)
	// fons.AddFontMem(fontContext, "Aria", FONT_DATA, true, 1)

}

text :: proc(text_str: string, x, y: f32, color: [4]u8 = {255, 255, 255, 255}) {
	kbts.ShapeBegin(shapeContext, .DONT_KNOW, .DONT_KNOW)
	kbts.ShapeUtf8(shapeContext, text_str, .CODEPOINT_INDEX)
	kbts.ShapeEnd(shapeContext)

	cursor_x: f32 = 0
	cursor_y: f32 = 0
	run_count := 0
	glyph_count := 0

	for run in kbts.ShapeRun(shapeContext) {
		run := run
		run_count += 1
		for glyph in kbts.GlyphIteratorNext(&run.Glyphs) {
			glyph_count += 1
			drawGlyph(glyph, x + cursor_x, y + cursor_y, color)
			cursor_x += f32(glyph.AdvanceX) / 64.0
			cursor_y += f32(glyph.AdvanceY) / 64.0
		}
	}

}
drawGlyph :: proc(glyph: ^kbts.glyph, base_x, base_y: f32, color: [4]u8 = {255, 255, 255, 255}) {
	offset_x := f32(glyph.OffsetX) / 64.0
	offset_y := f32(glyph.OffsetY) / 64.0
	advance_x := f32(glyph.AdvanceX) / 64.0

	x := base_x + offset_x
	y := base_y + offset_y - FONT_SIZE * 0.8
	w := max(advance_x, 4.0)
	h := f32(FONT_SIZE)

	sgl.disable_texture()
	sgl.begin_line_strip()
	{
		sgl.c4b(color.r, color.g, color.b, color.a)
		sgl.v2f(x, y)
		sgl.v2f(x + w, y)
		sgl.v2f(x + w, y + h)
		sgl.v2f(x, y + h)
		sgl.v2f(x, y)
	}
	sgl.end()

}

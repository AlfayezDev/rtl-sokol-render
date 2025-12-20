package main

import "base:runtime"
import sg "libs:sokol/gfx"
import sgl "libs:sokol/gl"
import fons "vendor:fontstash"
import kbts "vendor:kb_text_shape"

FONT_SIZE :: 32.0
ATLAS_WIDTH :: 512
ATLAS_HEIGHT :: 512
MAX_TEXT_COMMANDS :: 256
FONT_DATA :: #load("/System/Library/Fonts/Supplemental/Arial Unicode.ttf")

TextCommand :: struct {
	str:   string,
	x, y:  f32,
	color: [4]u8,
}

textCommands: [MAX_TEXT_COMMANDS]TextCommand
textCommandCount: int

shapeContext: ^kbts.shape_context
fontContext: ^fons.FontContext
typographySampler: sg.Sampler
OdinAllocator: runtime.Allocator
fontNormal: int
typographyPipeline: sgl.Pipeline
typographyData: []byte
typographyImage: sg.Image
typographyView: sg.View

typography_setup :: proc() {
	OdinAllocator = context.allocator
	shapeContext = kbts.CreateShapeContext(kbts.AllocatorFromOdinAllocator(&OdinAllocator))
	kbts.ShapePushFontFromMemory(shapeContext, FONT_DATA, 0)

	fontContext = new(fons.FontContext)
	fons.Init(fontContext, ATLAS_WIDTH, ATLAS_HEIGHT, .TOPLEFT)
	fontNormal = fons.AddFontMem(fontContext, "main", FONT_DATA, false)

	typographyData = make([]byte, ATLAS_WIDTH * ATLAS_HEIGHT * 4)
	typographyImage = sg.make_image(
		sg.Image_Desc {
			width = ATLAS_WIDTH,
			height = ATLAS_HEIGHT,
			pixel_format = .RGBA8,
			usage = {dynamic_update = true, immutable = false},
		},
	)
	typographyView = sg.make_view(sg.View_Desc{texture = {image = typographyImage}})
	typographySampler = sg.make_sampler(
		sg.Sampler_Desc{min_filter = .LINEAR, mag_filter = .LINEAR},
	)
	typographyPipeline = sgl.make_pipeline(
		sg.Pipeline_Desc {
			colors = {
				0 = {
					blend = {
						enabled = true,
						src_factor_rgb = .SRC_ALPHA,
						dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
					},
				},
			},
		},
	)
}

text :: proc(str: string, x, y: f32, color: [4]u8 = {255, 255, 255, 255}) {
	if textCommandCount >= MAX_TEXT_COMMANDS do return
	textCommands[textCommandCount] = {str, x, y, color}
	textCommandCount += 1
}

typography_flush :: proc() {
	if textCommandCount == 0 do return
	font := fons.__getFont(fontContext, fontNormal)
	scale := fons.__getPixelHeightScale(font, FONT_SIZE)
	// Pass 1: populate atlas
	for i in 0 ..< textCommandCount {
		cmd := &textCommands[i]
		kbts.ShapeBegin(shapeContext, .DONT_KNOW, .DONT_KNOW)
		kbts.ShapeUtf8(shapeContext, cmd.str, .CODEPOINT_INDEX)
		kbts.ShapeEnd(shapeContext)

		for run in kbts.ShapeRun(shapeContext) {
			run := run
			for glyph in kbts.GlyphIteratorNext(&run.Glyphs) {
				fons.__getGlyph(
					fontContext,
					fons.__getFont(fontContext, fontNormal),
					glyph.Codepoint,
					i16(FONT_SIZE * 10),
				)
			}
		}
	}

	// Upload atlas
	for i in 0 ..< (ATLAS_WIDTH * ATLAS_HEIGHT) {
		a := fontContext.textureData[i]
		typographyData[i * 4 + 0] = 255
		typographyData[i * 4 + 1] = 255
		typographyData[i * 4 + 2] = 255
		typographyData[i * 4 + 3] = a
	}
	sg.update_image(
		typographyImage,
		sg.Image_Data {
			mip_levels = {0 = {ptr = raw_data(typographyData), size = len(typographyData)}},
		},
	)

	// Pass 2: draw
	sgl.load_pipeline(typographyPipeline)
	sgl.enable_texture()
	sgl.texture(typographyView, typographySampler)
	sgl.begin_quads()

	for i in 0 ..< textCommandCount {
		cmd := &textCommands[i]
		kbts.ShapeBegin(shapeContext, .DONT_KNOW, .DONT_KNOW)
		kbts.ShapeUtf8(shapeContext, cmd.str, .CODEPOINT_INDEX)
		kbts.ShapeEnd(shapeContext)

		cursor_x: f32 = 0
		cursor_y: f32 = 0

		for run in kbts.ShapeRun(shapeContext) {
			run := run
			for glyph in kbts.GlyphIteratorNext(&run.Glyphs) {
				fons_glyph, ok := fons.__getGlyph(
					fontContext,
					font,
					glyph.Codepoint,
					i16(FONT_SIZE * 10),
				)
				if ok {
					drawGlyph(
						fons_glyph,
						cmd.x + cursor_x + f32(glyph.OffsetX) * scale,
						cmd.y + cursor_y + f32(glyph.OffsetY) * scale,
						cmd.color,
					)
				}
				cursor_x += f32(glyph.AdvanceX) * scale
				cursor_y += f32(glyph.AdvanceY) * scale
			}
		}
	}

	sgl.end()
	sgl.disable_texture()

	textCommandCount = 0
}

drawGlyph :: proc(glyph: ^fons.Glyph, x, y: f32, color: [4]u8) {
	x0 := x + f32(glyph.xoff)
	y0 := y + f32(glyph.yoff)
	x1 := x0 + f32(glyph.x1 - glyph.x0)
	y1 := y0 + f32(glyph.y1 - glyph.y0)

	s0 := f32(glyph.x0) / ATLAS_WIDTH
	t0 := f32(glyph.y0) / ATLAS_HEIGHT
	s1 := f32(glyph.x1) / ATLAS_WIDTH
	t1 := f32(glyph.y1) / ATLAS_HEIGHT

	sgl.c4b(color.r, color.g, color.b, color.a)
	sgl.v2f_t2f(x0, y0, s0, t0)
	sgl.v2f_t2f(x1, y0, s1, t0)
	sgl.v2f_t2f(x1, y1, s1, t1)
	sgl.v2f_t2f(x0, y1, s0, t1)
}

typography_shutdown :: proc() {
	kbts.DestroyShapeContext(shapeContext)
	delete(typographyData)
	fons.Destroy(fontContext)
	free(fontContext)
}

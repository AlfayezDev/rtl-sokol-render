package main

import "base:runtime"
import sg "libs:sokol/gfx"
import sgl "libs:sokol/gl"
import kbts "vendor:kb_text_shape"
import stbtt "vendor:stb/truetype"

FONT_SIZE :: 32.0
ATLAS_SIZE :: 1024
MAX_TEXT_COMMANDS :: 256
FONT_DATA :: #load("/System/Library/Fonts/Supplemental/Arial Unicode.ttf")

TextCommand :: struct {
	str:   string,
	x, y:  f32,
	color: [4]u8,
}

GlyphEntry :: struct {
	id:             u16,
	x0, y0, x1, y1: i16, // atlas coords
	xoff, yoff:     f32, // render offset
	advance:        f32,
}

textCommands: [MAX_TEXT_COMMANDS]TextCommand
textCommandCount: int

shapeContext: ^kbts.shape_context
OdinAllocator: runtime.Allocator

fontInfo: stbtt.fontinfo
fontScale: f32

// Atlas
atlasData: []byte
atlasImage: sg.Image
atlasView: sg.View
atlasSampler: sg.Sampler
atlasPipeline: sgl.Pipeline
atlasDirty: bool
atlasX, atlasY, atlasRowH: int

// Glyph cache (glyph ID -> entry)
glyphCache: map[u16]GlyphEntry

typography_setup :: proc() {
	OdinAllocator = context.allocator

	shapeContext = kbts.CreateShapeContext(kbts.AllocatorFromOdinAllocator(&OdinAllocator))
	kbts.ShapePushFontFromMemory(shapeContext, FONT_DATA, 0)

	stbtt.InitFont(&fontInfo, raw_data(FONT_DATA), 0)
	fontScale = stbtt.ScaleForPixelHeight(&fontInfo, FONT_SIZE)

	atlasData = make([]byte, ATLAS_SIZE * ATLAS_SIZE * 4)
	atlasImage = sg.make_image(
		sg.Image_Desc {
			width = ATLAS_SIZE,
			height = ATLAS_SIZE,
			pixel_format = .RGBA8,
			usage = {dynamic_update = true},
		},
	)
	atlasView = sg.make_view(sg.View_Desc{texture = {image = atlasImage}})
	atlasSampler = sg.make_sampler(sg.Sampler_Desc{min_filter = .LINEAR, mag_filter = .LINEAR})
	atlasPipeline = sgl.make_pipeline(
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

	glyphCache = make(map[u16]GlyphEntry)
	atlasX, atlasY, atlasRowH = 1, 1, 0
}

getGlyph :: proc(glyphId: u16) -> (GlyphEntry, bool) {
	if entry, ok := glyphCache[glyphId]; ok {
		return entry, true
	}

	// Rasterize
	x0, y0, x1, y1: i32
	stbtt.GetGlyphBitmapBox(&fontInfo, i32(glyphId), fontScale, fontScale, &x0, &y0, &x1, &y1)

	gw := int(x1 - x0)
	gh := int(y1 - y0)

	if gw == 0 || gh == 0 {
		return {}, false
	}

	// Atlas allocation (simple row packing)
	if atlasX + gw + 1 >= ATLAS_SIZE {
		atlasX = 1
		atlasY += atlasRowH + 1
		atlasRowH = 0
	}
	if atlasY + gh + 1 >= ATLAS_SIZE {
		return {}, false // Atlas full
	}

	ax, ay := atlasX, atlasY
	atlasX += gw + 1
	atlasRowH = max(atlasRowH, gh)

	// Render to temp buffer then copy as RGBA
	temp := make([]byte, gw * gh)
	defer delete(temp)
	stbtt.MakeGlyphBitmap(
		&fontInfo,
		raw_data(temp),
		i32(gw),
		i32(gh),
		i32(gw),
		fontScale,
		fontScale,
		i32(glyphId),
	)

	for py in 0 ..< gh {
		for px in 0 ..< gw {
			alpha := temp[py * gw + px]
			idx := ((ay + py) * ATLAS_SIZE + (ax + px)) * 4
			atlasData[idx + 0] = 255
			atlasData[idx + 1] = 255
			atlasData[idx + 2] = 255
			atlasData[idx + 3] = alpha
		}
	}
	atlasDirty = true

	advance, _: i32
	stbtt.GetGlyphHMetrics(&fontInfo, i32(glyphId), &advance, nil)

	entry := GlyphEntry {
		id      = glyphId,
		x0      = i16(ax),
		y0      = i16(ay),
		x1      = i16(ax + gw),
		y1      = i16(ay + gh),
		xoff    = f32(x0),
		yoff    = f32(y0),
		advance = f32(advance) * fontScale,
	}
	glyphCache[glyphId] = entry
	return entry, true
}

text :: proc(str: string, x, y: f32, color: [4]u8 = {255, 255, 255, 255}) {
	if textCommandCount >= MAX_TEXT_COMMANDS do return
	textCommands[textCommandCount] = {str, x, y, color}
	textCommandCount += 1
}

typography_flush :: proc() {
	if textCommandCount == 0 do return

	// Pass 1: ensure glyphs in atlas
	for i in 0 ..< textCommandCount {
		cmd := &textCommands[i]
		kbts.ShapeBegin(shapeContext, .DONT_KNOW, .DONT_KNOW)
		kbts.ShapeUtf8(shapeContext, cmd.str, .CODEPOINT_INDEX)
		kbts.ShapeEnd(shapeContext)

		for run in kbts.ShapeRun(shapeContext) {
			run := run
			for glyph in kbts.GlyphIteratorNext(&run.Glyphs) {
				getGlyph(glyph.Id)
			}
		}
	}

	// Upload atlas if dirty
	if atlasDirty {
		sg.update_image(
			atlasImage,
			sg.Image_Data{mip_levels = {0 = {ptr = raw_data(atlasData), size = len(atlasData)}}},
		)
		atlasDirty = false
	}

	// Pass 2: draw
	sgl.load_pipeline(atlasPipeline)
	sgl.enable_texture()
	sgl.texture(atlasView, atlasSampler)
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
				if entry, ok := getGlyph(glyph.Id); ok {
					x := cmd.x + cursor_x + f32(glyph.OffsetX) * fontScale + entry.xoff
					y := cmd.y + cursor_y + f32(glyph.OffsetY) * fontScale + entry.yoff

					x1 := x + f32(entry.x1 - entry.x0)
					y1 := y + f32(entry.y1 - entry.y0)

					s0 := f32(entry.x0) / ATLAS_SIZE
					t0 := f32(entry.y0) / ATLAS_SIZE
					s1 := f32(entry.x1) / ATLAS_SIZE
					t1 := f32(entry.y1) / ATLAS_SIZE

					sgl.c4b(cmd.color.r, cmd.color.g, cmd.color.b, cmd.color.a)
					sgl.v2f_t2f(x, y, s0, t0)
					sgl.v2f_t2f(x1, y, s1, t0)
					sgl.v2f_t2f(x1, y1, s1, t1)
					sgl.v2f_t2f(x, y1, s0, t1)
				}
				cursor_x += f32(glyph.AdvanceX) * fontScale
				cursor_y += f32(glyph.AdvanceY) * fontScale
			}
		}
	}

	sgl.end()
	sgl.disable_texture()
	textCommandCount = 0
}

typography_shutdown :: proc() {
	kbts.DestroyShapeContext(shapeContext)
	delete(atlasData)
	delete(glyphCache)
}

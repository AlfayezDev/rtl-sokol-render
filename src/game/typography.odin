package game

import "core:log"
import "core:mem"
import "core:strings"
import sg "libs:sokol/gfx"
import sgl "libs:sokol/gl"
import kbts "vendor:kb_text_shape"
import stbtt "vendor:stb/truetype"

// =============================================================================
// Constants
// =============================================================================

FontSize :: 32.0
AtlasSize :: 1024
MaxCommands :: 256

FontData :: #load("/System/Library/Fonts/Supplemental/Arial Unicode.ttf")

// =============================================================================
// Types
// =============================================================================

TextCommand :: struct {
	text:  string,
	x, y:  f32,
	color: [4]u8,
}

GlyphEntry :: struct {
	id:             u16,
	x0, y0, x1, y1: i16,
	xoff, yoff:     f32,
	advance:        f32,
}

AtlasPacker :: struct {
	x, y: int,
	rowH: int,
}

// =============================================================================
// Typography System
// =============================================================================

Typography :: struct {
	// Allocators (not owned, just referenced)
	sessionAllocator: mem.Allocator,
	frameAllocator:   mem.Allocator,

	// Session lifetime
	fontInfo:         stbtt.fontinfo,
	fontScale:        f32,
	shapeContext:     ^kbts.shape_context,
	glyphCache:       map[u16]GlyphEntry,
	atlasData:        []byte,
	atlasPacker:      AtlasPacker,
	atlasDirty:       bool,

	// GPU resources (session lifetime)
	atlasImage:       sg.Image,
	atlasView:        sg.View,
	atlasSampler:     sg.Sampler,
	pipeline:         sgl.Pipeline,

	// Frame lifetime
	commands:         [dynamic]TextCommand,
}

// =============================================================================
// Lifecycle
// =============================================================================

typographySetup :: proc(
	t: ^Typography,
	sessionAllocator: mem.Allocator = context.allocator,
	frameAllocator: mem.Allocator = context.temp_allocator,
) -> bool {
	t.sessionAllocator = sessionAllocator
	t.frameAllocator = frameAllocator

	// Initialize font
	if !stbtt.InitFont(&t.fontInfo, raw_data(FontData), 0) {
		log.error("stbtt.InitFont failed")
		return false
	}
	t.fontScale = stbtt.ScaleForPixelHeight(&t.fontInfo, FontSize)
	log.info("Font initialized, scale:", t.fontScale)

	// Initialize text shaper
	shaperAllocFn, allocationData := kbts.AllocatorFromOdinAllocator(&t.sessionAllocator)
	log.info("Created shaper allocator fn")
	t.shapeContext = kbts.CreateShapeContext(shaperAllocFn, allocationData)
	if t.shapeContext == nil {
		log.error("kbts.CreateShapeContext failed")
		return false
	}
	log.info("Shape context created")

	kbts.ShapePushFontFromMemory(t.shapeContext, FontData, 0)
	log.info("Font pushed to shaper")

	// Initialize glyph cache (allocator is stored in the map)
	t.glyphCache = make(map[u16]GlyphEntry, 256, sessionAllocator)

	// Initialize atlas
	t.atlasData = make([]byte, AtlasSize * AtlasSize * 4, sessionAllocator)
	t.atlasPacker = {
		x    = 1,
		y    = 1,
		rowH = 0,
	}
	t.atlasDirty = false

	// Initialize GPU resources
	t.atlasImage = sg.make_image(
		{
			width = AtlasSize,
			height = AtlasSize,
			pixel_format = .RGBA8,
			usage = {dynamic_update = true},
		},
	)

	t.atlasView = sg.make_view({texture = {image = t.atlasImage}})

	t.atlasSampler = sg.make_sampler({min_filter = .LINEAR, mag_filter = .LINEAR})

	t.pipeline = sgl.make_pipeline(
		{
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

	// Initialize frame storage
	t.commands = make([dynamic]TextCommand, 0, MaxCommands, frameAllocator)

	return true
}

typographyShutdown :: proc(t: ^Typography) {
	sgl.destroy_pipeline(t.pipeline)
	sg.destroy_sampler(t.atlasSampler)
	sg.destroy_view(t.atlasView)
	sg.destroy_image(t.atlasImage)

	delete(t.atlasData, t.sessionAllocator)
	delete(t.glyphCache) // Map stores its allocator internally
	kbts.DestroyShapeContext(t.shapeContext)

	t^ = {}
}

// =============================================================================
// Frame Lifecycle
// =============================================================================

typographyBeginFrame :: proc(t: ^Typography) {
	t.commands = make([dynamic]TextCommand, 0, MaxCommands, t.frameAllocator)
}

typographyEndFrame :: proc(t: ^Typography) {
	if len(t.commands) == 0 {
		return
	}

	// Pass 1: ensure all glyphs are in atlas
	for &cmd in t.commands {
		ensureGlyphsForText(t, cmd.text)
	}

	// Upload atlas if dirty
	if t.atlasDirty {
		sg.update_image(
			t.atlasImage,
			{mip_levels = {0 = {ptr = raw_data(t.atlasData), size = len(t.atlasData)}}},
		)
		t.atlasDirty = false
	}

	// Pass 2: emit quads
	sgl.load_pipeline(t.pipeline)
	sgl.enable_texture()
	sgl.texture(t.atlasView, t.atlasSampler)
	sgl.begin_quads()

	for &cmd in t.commands {
		drawTextCommand(t, &cmd)
	}

	sgl.end()
	sgl.disable_texture()
}

// =============================================================================
// Text Commands
// =============================================================================

text :: proc(t: ^Typography, str: string, x, y: f32, color: [4]u8 = {255, 255, 255, 255}) {
	if len(t.commands) >= MaxCommands {
		return
	}

	strCopy := strings.clone(str, t.frameAllocator)

	append(&t.commands, TextCommand{text = strCopy, x = x, y = y, color = color})
}

// =============================================================================
// Internal: Text Shaping
// =============================================================================

@(private = "file")
ensureGlyphsForText :: proc(t: ^Typography, str: string) {
	kbts.ShapeBegin(t.shapeContext, .DONT_KNOW, .DONT_KNOW)
	kbts.ShapeUtf8(t.shapeContext, str, .CODEPOINT_INDEX)
	kbts.ShapeEnd(t.shapeContext)

	for run in kbts.ShapeRun(t.shapeContext) {
		run := run
		for glyph in kbts.GlyphIteratorNext(&run.Glyphs) {
			ensureGlyph(t, glyph.Id)
		}
	}
}

@(private = "file")
drawTextCommand :: proc(t: ^Typography, cmd: ^TextCommand) {
	kbts.ShapeBegin(t.shapeContext, .DONT_KNOW, .DONT_KNOW)
	kbts.ShapeUtf8(t.shapeContext, cmd.text, .CODEPOINT_INDEX)
	kbts.ShapeEnd(t.shapeContext)

	cursorX: f32 = 0
	cursorY: f32 = 0

	for run in kbts.ShapeRun(t.shapeContext) {
		run := run
		for glyph in kbts.GlyphIteratorNext(&run.Glyphs) {
			entry, ok := t.glyphCache[glyph.Id]
			if ok {
				emitGlyphQuad(t, cmd, &entry, glyph, cursorX, cursorY)
			}

			cursorX += f32(glyph.AdvanceX) * t.fontScale
			cursorY += f32(glyph.AdvanceY) * t.fontScale
		}
	}
}

@(private = "file")
emitGlyphQuad :: proc(
	t: ^Typography,
	cmd: ^TextCommand,
	entry: ^GlyphEntry,
	glyph: ^kbts.glyph,
	cursorX: f32,
	cursorY: f32,
) {
	x0 := cmd.x + cursorX + f32(glyph.OffsetX) * t.fontScale + entry.xoff
	y0 := cmd.y + cursorY + f32(glyph.OffsetY) * t.fontScale + entry.yoff
	x1 := x0 + f32(entry.x1 - entry.x0)
	y1 := y0 + f32(entry.y1 - entry.y0)

	s0 := f32(entry.x0) / AtlasSize
	t0 := f32(entry.y0) / AtlasSize
	s1 := f32(entry.x1) / AtlasSize
	t1 := f32(entry.y1) / AtlasSize

	sgl.c4b(cmd.color.r, cmd.color.g, cmd.color.b, cmd.color.a)
	sgl.v2f_t2f(x0, y0, s0, t0)
	sgl.v2f_t2f(x1, y0, s1, t0)
	sgl.v2f_t2f(x1, y1, s1, t1)
	sgl.v2f_t2f(x0, y1, s0, t1)
}

// =============================================================================
// Internal: Glyph Rasterization & Atlas
// =============================================================================

@(private = "file")
ensureGlyph :: proc(t: ^Typography, glyphId: u16) {
	if glyphId in t.glyphCache {
		return
	}

	bx0, by0, bx1, by1: i32
	stbtt.GetGlyphBitmapBox(
		&t.fontInfo,
		i32(glyphId),
		t.fontScale,
		t.fontScale,
		&bx0,
		&by0,
		&bx1,
		&by1,
	)

	glyphW := int(bx1 - bx0)
	glyphH := int(by1 - by0)

	// Empty glyph (space, etc)
	if glyphW == 0 || glyphH == 0 {
		return
	}

	atlasX, atlasY, packOk := atlasPack(t, glyphW, glyphH)
	if !packOk {
		return // Atlas full
	}

	rasterizeGlyph(t, glyphId, glyphW, glyphH, atlasX, atlasY)

	advance: i32
	stbtt.GetGlyphHMetrics(&t.fontInfo, i32(glyphId), &advance, nil)

	t.glyphCache[glyphId] = GlyphEntry {
		id      = glyphId,
		x0      = i16(atlasX),
		y0      = i16(atlasY),
		x1      = i16(atlasX + glyphW),
		y1      = i16(atlasY + glyphH),
		xoff    = f32(bx0),
		yoff    = f32(by0),
		advance = f32(advance) * t.fontScale,
	}
}

@(private = "file")
atlasPack :: proc(t: ^Typography, w, h: int) -> (x, y: int, ok: bool) {
	packer := &t.atlasPacker

	if packer.x + w + 1 >= AtlasSize {
		packer.x = 1
		packer.y += packer.rowH + 1
		packer.rowH = 0
	}

	if packer.y + h + 1 >= AtlasSize {
		return 0, 0, false
	}

	x = packer.x
	y = packer.y

	packer.x += w + 1
	packer.rowH = max(packer.rowH, h)

	return x, y, true
}

@(private = "file")
rasterizeGlyph :: proc(t: ^Typography, glyphId: u16, w, h: int, atlasX, atlasY: int) {
	temp := make([]byte, w * h, t.frameAllocator)

	stbtt.MakeGlyphBitmap(
		&t.fontInfo,
		raw_data(temp),
		i32(w),
		i32(h),
		i32(w),
		t.fontScale,
		t.fontScale,
		i32(glyphId),
	)

	for py in 0 ..< h {
		for px in 0 ..< w {
			alpha := temp[py * w + px]
			idx := ((atlasY + py) * AtlasSize + (atlasX + px)) * 4

			t.atlasData[idx + 0] = 255
			t.atlasData[idx + 1] = 255
			t.atlasData[idx + 2] = 255
			t.atlasData[idx + 3] = alpha
		}
	}

	t.atlasDirty = true
}

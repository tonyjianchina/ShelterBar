import AppKit
import Testing
@testable import ShelterBar

@Test("menu bar glyphs keep native size and text items get wider shelf cells")
@MainActor
func menuBarIconNativeSizing() {
    let small = NSImage(size: NSSize(width: 12, height: 18))
    #expect(MenuBarIconPresentation.displaySize(for: small) == NSSize(width: 12, height: 18))
    #expect(MenuBarIconPresentation.shelfWidth(for: small) == 32)
    #expect(MenuBarIconPresentation.drawingRect(for: small, in: NSRect(x: 0, y: 0, width: 32, height: 42))
        == NSRect(x: 10, y: 12, width: 12, height: 18))

    let text = NSImage(size: NSSize(width: 90, height: 20))
    #expect(MenuBarIconPresentation.displaySize(for: text) == NSSize(width: 90, height: 20))
    #expect(MenuBarIconPresentation.shelfWidth(for: text) == 104)
}

@Test("oversize glyphs fit the shelf without changing their aspect ratio")
@MainActor
func menuBarIconAspectRatio() {
    let tall = NSImage(size: NSSize(width: 30, height: 60))
    #expect(MenuBarIconPresentation.displaySize(for: tall) == NSSize(width: 12, height: 24))

    let wide = NSImage(size: NSSize(width: 212, height: 20))
    #expect(MenuBarIconPresentation.displaySize(for: wide) == NSSize(width: 106, height: 10))
    #expect(MenuBarIconPresentation.shelfWidth(for: wide) == 120)

    let constrained = MenuBarIconPresentation.drawingRect(
        for: wide, in: NSRect(x: 0, y: 0, width: 67, height: 42)
    )
    #expect(constrained.size == NSSize(width: 53, height: 5))
    #expect(constrained.midX == 33.5 && constrained.midY == 21)
}

@Test("unavailable menu bar icons use a small template placeholder")
@MainActor
func menuBarIconPlaceholder() {
    let placeholder = MenuBarIconPresentation.placeholder(accessibilityDescription: "Example")
    #expect(placeholder.isTemplate)
    #expect(placeholder.size.height == 18)
    #expect(MenuBarIconPresentation.shelfWidth(for: placeholder) == 32)
    let empty = NSImage(size: .zero)
    #expect(MenuBarIconPresentation.displaySize(for: empty) == .zero)
    #expect(MenuBarIconPresentation.shelfWidth(for: empty) == 32)
}

@MainActor
private func sampleIcon(template: Bool) -> NSImage {
    let image = NSImage(size: NSSize(width: 16, height: 12), flipped: false) { _ in
        NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1).setFill()
        NSRect(x: 4, y: 2, width: 8, height: 8).fill()
        return true
    }
    image.isTemplate = template
    return image
}

@MainActor
private func raster(_ image: NSImage) throws -> NSBitmapImageRep {
    let context = try #require(CGContext(
        data: nil, width: Int(image.size.width), height: Int(image.size.height),
        bitsPerComponent: 8, bytesPerRow: Int(image.size.width) * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    image.draw(in: NSRect(origin: .zero, size: image.size))
    let cgImage = try #require(context.makeImage())
    return NSBitmapImageRep(cgImage: cgImage)
}

@Test("template dragging images take the label tint while preserving transparent pixels")
@MainActor
func menuBarIconTemplateTint() throws {
    let rendered = MenuBarIconPresentation.renderedImage(
        for: sampleIcon(template: true), tintColor: NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
    )
    #expect(!rendered.isTemplate)
    #expect(rendered.size == NSSize(width: 16, height: 12))
    let bitmap = try raster(rendered)
    var center = [Int](repeating: 0, count: 4)
    bitmap.getPixel(&center, atX: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)
    #expect(center[0] > 242)
    #expect(center[1] < 13 && center[2] < 13)
    #expect(center[3] > 242)
    var corner = [Int](repeating: 0, count: 4)
    bitmap.getPixel(&corner, atX: 0, y: 0)
    #expect(corner[3] < 3)
}

@Test("colored menu bar images retain their original colors")
@MainActor
func menuBarIconPreservesColor() throws {
    let bitmap = try raster(MenuBarIconPresentation.renderedImage(
        for: sampleIcon(template: false), tintColor: NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
    ))
    var center = [Int](repeating: 0, count: 4)
    bitmap.getPixel(&center, atX: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)
    #expect(center[2] > 242)
    #expect(center[0] < 13 && center[1] < 13)
}

@Test("template tint only changes glyph pixels, leaving the shelf background intact")
@MainActor
func menuBarIconTintKeepsBackground() throws {
    let glyph = sampleIcon(template: true)
    let canvas = NSImage(size: NSSize(width: 32, height: 42), flipped: false) { rect in
        NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1).setFill()
        rect.fill()
        MenuBarIconPresentation.draw(glyph, in: rect, tintColor: NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        return true
    }
    let bitmap = try raster(canvas)
    var background = [Int](repeating: 0, count: 4)
    bitmap.getPixel(&background, atX: 0, y: 0)
    var center = [Int](repeating: 0, count: 4)
    bitmap.getPixel(&center, atX: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)
    #expect(background[1] > 242 && background[0] < 13)
    #expect(center[0] > 242 && center[1] < 13)
}

@MainActor
private func shadedCapturedGlyph(bright: Bool, coloredBadge: Bool = false) throws -> NSImage {
    let context = try #require(CGContext(data: nil, width: 48, height: 48, bitsPerComponent: 8,
        bytesPerRow: 48 * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(CGColor(gray: 0, alpha: 0.35))
    context.fill(CGRect(x: 6, y: 6, width: 36, height: 36))
    context.setFillColor(CGColor(gray: bright ? 1 : 0, alpha: 1))
    context.fill(CGRect(x: 10, y: 10, width: 28, height: 28))
    context.setFillColor(CGColor(gray: 0.6, alpha: 1))
    context.fill(CGRect(x: 20, y: 20, width: 8, height: 8))
    if coloredBadge {
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 30, y: 30, width: 8, height: 8))
    }
    return try #require(MenuBarGlyphImage.make(from: context.makeImage()!, logicalSize: CGSize(width: 24, height: 24)))
}

@Test("captured grayscale glyphs with shading stay legible on light and dark shelves without flattening details")
@MainActor
func capturedShadedGlyphContrast() throws {
    for bright in [true, false] {
        let image = try shadedCapturedGlyph(bright: bright)
        #expect(!image.isTemplate)
        for (tint, expectedBright) in [(NSColor.black, false), (NSColor.white, true)] {
            let bitmap = try raster(MenuBarIconPresentation.renderedImage(for: image, tintColor: tint))
            let body = try #require(bitmap.colorAt(x: 8, y: 8)?.usingColorSpace(.deviceRGB))
            let detail = try #require(bitmap.colorAt(x: 12, y: 12)?.usingColorSpace(.deviceRGB))
            #expect(expectedBright ? body.redComponent > 0.75 : body.redComponent < 0.25)
            #expect(abs(body.redComponent - detail.redComponent) > 0.2)
            #expect((bitmap.colorAt(x: 0, y: 0)?.alphaComponent ?? 1) < 0.01)
            #expect(abs((bitmap.colorAt(x: 4, y: 4)?.alphaComponent ?? 0) - 0.35) < 0.02)
        }
    }
}

@Test("a neutral icon stays readable while its small colored badge keeps its color")
@MainActor
func capturedBadgePreservesColorAndDetails() throws {
    let image = try shadedCapturedGlyph(bright: true, coloredBadge: true)
    let bitmap = try raster(MenuBarIconPresentation.renderedImage(for: image, tintColor: .black))
    let original = try raster(MenuBarIconPresentation.renderedImage(for: image, tintColor: .white))
    let body = try #require(bitmap.colorAt(x: 8, y: 8)?.usingColorSpace(.deviceRGB))
    #expect(body.redComponent < 0.25 && body.greenComponent < 0.25)
    var redPixels = 0
    var strongest: (x: Int, y: Int, chroma: CGFloat)?
    for y in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide {
            if let before = original.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
               before.alphaComponent > 0.8, before.redComponent > before.greenComponent + 0.4,
               before.redComponent > before.blueComponent + 0.4 {
                let after = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB))
                #expect(after.redComponent > after.greenComponent + 0.4)
                #expect(after.redComponent > after.blueComponent + 0.4)
                let chroma = before.redComponent - max(before.greenComponent, before.blueComponent)
                if chroma > (strongest?.chroma ?? 0) { strongest = (x, y, chroma) }
                redPixels += 1
            }
        }
    }
    #expect(redPixels >= 9)
    // Compare the solid badge center; edge antialiasing legitimately blends
    // with a different neighboring neutral shade after appearance changes.
    let point = try #require(strongest)
    let before = try #require(original.colorAt(x: point.x, y: point.y)?.usingColorSpace(.sRGB))
    let after = try #require(bitmap.colorAt(x: point.x, y: point.y)?.usingColorSpace(.sRGB))
    #expect(abs(before.redComponent - after.redComponent) < 0.03)
    #expect(abs(before.greenComponent - after.greenComponent) < 0.03)
    #expect(abs(before.blueComponent - after.blueComponent) < 0.03)
    #expect(!image.isTemplate)
}

@Test("the actual shelf drawing path follows its appearance without an explicit tint")
@MainActor
func shadedShelfDrawingFollowsAppearance() throws {
    let glyph = try shadedCapturedGlyph(bright: true)
    for (name, expectedBright) in [(NSAppearance.Name.aqua, false), (.darkAqua, true)] {
        let appearance = try #require(NSAppearance(named: name))
        let canvas = NSImage(size: CGSize(width: 44, height: 44), flipped: false) { rect in
            (expectedBright ? NSColor.black : NSColor.white).setFill()
            rect.fill()
            MenuBarIconPresentation.draw(glyph, in: rect)
            return true
        }
        var rendered: NSBitmapImageRep?
        appearance.performAsCurrentDrawingAppearance { rendered = try? raster(canvas) }
        let bitmap = try #require(rendered)
        let body = try #require(bitmap.colorAt(x: 18, y: 18)?.usingColorSpace(.deviceRGB))
        #expect(expectedBright ? body.redComponent > 0.75 : body.redComponent < 0.25)
    }
}

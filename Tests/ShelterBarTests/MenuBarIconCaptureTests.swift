import AppKit
import Testing
@testable import ShelterBar

@Test("a capture must match one status window by process, layer and full geometry")
func captureWindowIdentityIsStrict() {
    let frame = CGRect(x: 900, y: 0, width: 24, height: 24)
    let layer = Int(CGWindowLevelForKey(.statusWindow))
    let valid = MenuBarCaptureWindow(id: 1, pid: 42, layer: layer, frame: frame)
    let wrongOwner = MenuBarCaptureWindow(id: 2, pid: 7, layer: layer, frame: frame)
    let ordinaryWindow = MenuBarCaptureWindow(id: 3, pid: 42, layer: 0, frame: frame)
    let neighbor = MenuBarCaptureWindow(id: 4, pid: 42, layer: layer, frame: frame.offsetBy(dx: 30, dy: 0))
    #expect(MenuBarIconMatcher.match(frame: frame, pid: 42, windows: [wrongOwner, ordinaryWindow, neighbor]) == nil)
    #expect(MenuBarIconMatcher.match(frame: frame, pid: 42, windows: [valid, wrongOwner, ordinaryWindow, neighbor]) == 1)
    let duplicate = MenuBarCaptureWindow(id: 5, pid: 42, layer: layer, frame: frame)
    #expect(MenuBarIconMatcher.match(frame: frame, pid: 42, windows: [valid, duplicate]) == nil)
}

@Test("offscreen glyphs can match but large application windows cannot become captures")
func captureBoundsAreRestricted() {
    let layer = Int(CGWindowLevelForKey(.statusWindow))
    let offscreen = CGRect(x: -1800, y: 0, width: 30, height: 24)
    #expect(MenuBarIconMatcher.match(frame: offscreen, pid: 42, windows: [
        MenuBarCaptureWindow(id: 1, pid: 42, layer: layer, frame: offscreen)
    ]) == 1)
    let large = CGRect(x: 0, y: 0, width: 800, height: 600)
    #expect(MenuBarIconMatcher.match(frame: large, pid: 42, windows: [
        MenuBarCaptureWindow(id: 2, pid: 42, layer: layer, frame: large)
    ]) == nil)
}

@Test("a padded status window matches its shorter AX glyph and crops at Retina scale")
func paddedStatusWindowKeepsNativeGlyphSize() {
    let window = CGRect(x: 900, y: 0, width: 34, height: 37)
    let item = CGRect(x: 900, y: 6.5, width: 34, height: 24)
    #expect(MenuBarIconMatcher.match(frame: item, pid: 42, windows: [
        MenuBarCaptureWindow(id: 1, pid: 42, layer: Int(CGWindowLevelForKey(.statusWindow)), frame: window)
    ]) == 1)
    #expect(MenuBarIconMatcher.pixelCrop(itemFrame: item, windowFrame: window,
                                        pixelSize: CGSize(width: 68, height: 74)) ==
            CGRect(x: 0, y: 13, width: 68, height: 48))
}

@Test("Shadowrocket's captured native window may be hosted by Control Center")
func captureMatchesVerifiedSystemHost() {
    let axFrame = CGRect(x: 990, y: 4.5, width: 36, height: 24)
    let nativeFrame = CGRect(x: 991, y: 0, width: 34, height: 33)
    let window = MenuBarCaptureWindow(
        id: 12412, pid: 1141, layer: Int(CGWindowLevelForKey(.statusWindow)),
        frame: nativeFrame, ownerBundleID: "com.apple.controlcenter"
    )
    #expect(MenuBarIconMatcher.match(frame: axFrame, pid: 97940, windows: [window]) == 12412)
    #expect(MenuBarIconMatcher.pixelCrop(itemFrame: axFrame, windowFrame: nativeFrame,
                                         pixelSize: CGSize(width: 68, height: 66)) ==
            CGRect(x: 0, y: 9, width: 68, height: 48))
}

@Test("hosted captures reject unrelated owners, ambiguous windows and whole menu bars")
func captureRejectsUnverifiedOrAmbiguousHosts() {
    let axFrame = CGRect(x: 990, y: 4.5, width: 36, height: 24)
    let nativeFrame = CGRect(x: 991, y: 0, width: 34, height: 33)
    let layer = Int(CGWindowLevelForKey(.statusWindow))
    let host = MenuBarCaptureWindow(id: 1, pid: 1141, layer: layer, frame: nativeFrame,
                                    ownerBundleID: "com.apple.controlcenter")
    let unrelated = MenuBarCaptureWindow(id: 2, pid: 7, layer: layer, frame: nativeFrame,
                                         ownerBundleID: "com.example.controlcenter")
    let unidentified = MenuBarCaptureWindow(id: 3, pid: 8, layer: layer, frame: nativeFrame)
    let duplicate = MenuBarCaptureWindow(id: 4, pid: 97940, layer: layer, frame: nativeFrame)
    let wholeBar = MenuBarCaptureWindow(id: 5, pid: 1141, layer: layer,
        frame: CGRect(x: 0, y: 0, width: 1512, height: 33),
        ownerBundleID: "com.apple.controlcenter")
    #expect(MenuBarIconMatcher.match(frame: axFrame, pid: 97940,
                                     windows: [unrelated, unidentified, wholeBar]) == nil)
    #expect(MenuBarIconMatcher.match(frame: axFrame, pid: 97940,
                                     windows: [host, unrelated, unidentified, wholeBar]) == 1)
    #expect(MenuBarIconMatcher.match(frame: axFrame, pid: 97940,
                                     windows: [host, duplicate]) == nil)
}

@Test("macOS 27 glyph capture accepts duplicate copies of one verified composite host")
func captureMatchesCompositeMenuBarHost() {
    let item = CGRect(x: 1048, y: 4.5, width: 34, height: 24)
    let layer = Int(CGWindowLevelForKey(.statusWindow)) - 1
    let host = MenuBarCaptureWindow(id: 27, pid: 9, layer: layer,
        frame: CGRect(x: 0, y: 0, width: 1512, height: 33),
        ownerBundleID: "com.apple.MenuBarAgent")
    #expect(MenuBarIconMatcher.match(frame: item, pid: 42, windows: [host]) == 27)

    let foreign = MenuBarCaptureWindow(id: 28, pid: 9, layer: layer,
        frame: host.frame, ownerBundleID: "com.example.MenuBarAgent")
    let duplicate = MenuBarCaptureWindow(id: 29, pid: 10, layer: layer,
        frame: host.frame, ownerBundleID: "com.apple.MenuBarAgent")
    let conflicting = MenuBarCaptureWindow(id: 31, pid: 10, layer: layer,
        frame: host.frame.insetBy(dx: -12, dy: 0), ownerBundleID: "com.apple.MenuBarAgent")
    let ordinary = MenuBarCaptureWindow(id: 30, pid: 9, layer: 0,
        frame: host.frame, ownerBundleID: "com.apple.MenuBarAgent")
    #expect(MenuBarIconMatcher.match(frame: item, pid: 42, windows: [foreign, ordinary]) == nil)
    #expect(MenuBarIconMatcher.match(frame: item, pid: 42, windows: [host, duplicate]) == 27)
    #expect(MenuBarIconMatcher.match(frame: item, pid: 42, windows: [host, conflicting]) == nil)
    #expect(MenuBarIconMatcher.match(frame: item.offsetBy(dx: 1600, dy: 0), pid: 42,
                                     windows: [host]) == nil)
    #expect(MenuBarIconMatcher.match(frame: item.offsetBy(dx: 0, dy: 24), pid: 42,
                                     windows: [host]) == nil)
}

private func pixels(color: CGColor?) -> CGImage {
    let context = CGContext(data: nil, width: 48, height: 48, bitsPerComponent: 8,
        bytesPerRow: 48 * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    if let color {
        context.setFillColor(color)
        context.fill(CGRect(x: 16, y: 8, width: 16, height: 32))
    }
    return context.makeImage()!
}

private func fullWidthStatusChrome() -> CGImage {
    let context = CGContext(data: nil, width: 36, height: 24, bitsPerComponent: 8,
        bytesPerRow: 36 * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 4, width: 36, height: 12))
    context.setFillColor(CGColor(gray: 0, alpha: 0.05))
    context.fill(CGRect(x: 0, y: 3, width: 36, height: 1))
    return context.makeImage()!
}

@Test("native captures reject full-width solid status-host chrome")
@MainActor
func nativeCaptureRejectsFullWidthStatusChrome() {
    #expect(MenuBarGlyphImage.make(
        from: fullWidthStatusChrome(), logicalSize: CGSize(width: 36, height: 24)
    ) == nil)
}

@Test("a real centered horizontal glyph is not mistaken for status-host chrome")
@MainActor
func nativeCaptureKeepsCenteredHorizontalGlyph() {
    let context = CGContext(data: nil, width: 36, height: 24, bitsPerComponent: 8,
        bytesPerRow: 36 * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 6, y: 9, width: 24, height: 6))
    #expect(MenuBarGlyphImage.make(
        from: context.makeImage()!, logicalSize: CGSize(width: 36, height: 24)
    )?.isTemplate == true)
}

@Test("a composite menu bar capture waits for two matching rendered frames")
func compositeCaptureWaitsForStablePixels() {
    let moving = pixels(color: CGColor(gray: 0.25, alpha: 1))
    let settled = pixels(color: CGColor(gray: 0.75, alpha: 1))
    var stability = MenuBarCaptureStability()

    #expect(stability.observe(moving) == false)
    #expect(stability.observe(settled) == false)
    #expect(stability.observe(settled) == true)
}

@Test("original monochrome glyphs adapt to appearance while colored status remains colored")
@MainActor
func capturePreservesGlyphStyle() {
    let size = CGSize(width: 24, height: 24)
    let monochrome = MenuBarGlyphImage.make(from: pixels(color: CGColor(gray: 1, alpha: 1)), logicalSize: size)
    #expect(monochrome?.isTemplate == true)
    #expect(monochrome?.size == size)
    let colored = MenuBarGlyphImage.make(from: pixels(color: CGColor(red: 1, green: 0, blue: 0, alpha: 1)), logicalSize: size)
    #expect(colored?.isTemplate == false)
    #expect(MenuBarGlyphImage.make(from: pixels(color: nil), logicalSize: size) == nil)
}

@Test("black-and-white details inside a status icon must not be flattened into a template")
@MainActor
func multitoneGlyphKeepsItsDetails() {
    let context = CGContext(data: nil, width: 48, height: 48, bitsPerComponent: 8,
        bytesPerRow: 48 * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(gray: 0, alpha: 1))
    context.fillEllipse(in: CGRect(x: 8, y: 8, width: 32, height: 32))
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 20, y: 16, width: 8, height: 16))
    let image = MenuBarGlyphImage.make(from: context.makeImage()!, logicalSize: CGSize(width: 24, height: 24))
    #expect(image?.isTemplate == false)
}

private func capturedWhiteGlyph(alpha: CGFloat) -> CGImage {
    let context = CGContext(data: nil, width: 48, height: 48, bitsPerComponent: 8,
        bytesPerRow: 48 * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // A vibrancy-rendered white glyph: partially opaque body, a darker
    // antialiased rim and a few pixels tinted by the blue wallpaper.
    context.setFillColor(CGColor(gray: 1, alpha: alpha))
    context.fillEllipse(in: CGRect(x: 10, y: 10, width: 28, height: 28))
    context.setStrokeColor(CGColor(gray: 0.65, alpha: 0.2))
    context.stroke(CGRect(x: 9, y: 9, width: 30, height: 30), width: 1)
    context.setBlendMode(.copy)
    context.setFillColor(CGColor(red: 0.8, green: 0.88, blue: 1, alpha: alpha))
    context.fill(CGRect(x: 22, y: 22, width: 3, height: 3))
    return context.makeImage()!
}

@Test("white glyphs captured over a tinted menu bar still become templates")
@MainActor
func tintedWhiteGlyphBecomesTemplate() throws {
    let size = CGSize(width: 24, height: 24)
    let opaque = try #require(MenuBarGlyphImage.make(from: capturedWhiteGlyph(alpha: 0.92), logicalSize: size))
    #expect(opaque.isTemplate)
    let faint = try #require(MenuBarGlyphImage.make(from: capturedWhiteGlyph(alpha: 0.55), logicalSize: size))
    #expect(faint.isTemplate)
    #expect(faint.size == size)
    // Faint vibrancy glyphs are restored to full opacity before tinting.
    var pixelRect = CGRect(x: 0, y: 0, width: 48, height: 48)
    let cgImage = try #require(faint.cgImage(forProposedRect: &pixelRect, context: nil, hints: nil))
    let bitmap = NSBitmapImageRep(cgImage: cgImage)
    var center = [Int](repeating: 0, count: 4)
    bitmap.getPixel(&center, atX: 24, y: 16)
    #expect(center[3] > 242)
}

@Test("genuinely colored icons with white details stay colored and get a tone")
@MainActor
func coloredIconWithWhiteDetailsStaysColored() {
    let context = CGContext(data: nil, width: 48, height: 48, bitsPerComponent: 8,
        bytesPerRow: 48 * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 0.45, green: 0.4, blue: 0.95, alpha: 1))
    context.fill(CGRect(x: 6, y: 12, width: 36, height: 24))
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fill(CGRect(x: 14, y: 18, width: 20, height: 12))
    let image = MenuBarGlyphImage.make(from: context.makeImage()!, logicalSize: CGSize(width: 24, height: 24))
    #expect(image?.isTemplate == false)
    #expect(image.map(MenuBarGlyphImage.tone(of:)) == .mixed)

    let pale = CGContext(data: nil, width: 48, height: 48, bitsPerComponent: 8,
        bytesPerRow: 48 * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    pale.setFillColor(CGColor(red: 1, green: 0.95, blue: 0.75, alpha: 1))
    pale.fill(CGRect(x: 16, y: 8, width: 16, height: 32))
    let light = MenuBarGlyphImage.make(from: pale.makeImage()!, logicalSize: CGSize(width: 24, height: 24))
    #expect(light?.isTemplate == false)
    #expect(light.map(MenuBarGlyphImage.tone(of:)) == .light)
}

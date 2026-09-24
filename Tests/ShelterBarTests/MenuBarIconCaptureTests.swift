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

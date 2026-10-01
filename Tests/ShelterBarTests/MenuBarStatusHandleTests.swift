import AppKit
import Testing
@testable import ShelterBar

@MainActor
private func visiblePixels(_ image: NSImage) throws -> CGRect {
    let pixels = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
    let bitmap = NSBitmapImageRep(cgImage: pixels)
    var bounds = CGRect.null
    for y in 0..<pixels.height {
        for x in 0..<pixels.width where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 {
            bounds = bounds.union(CGRect(x: x, y: y, width: 1, height: 1))
        }
    }
    #expect(!bounds.isNull)
    return CGRect(x: bounds.minX * image.size.width / CGFloat(pixels.width),
                  y: bounds.minY * image.size.height / CGFloat(pixels.height),
                  width: bounds.width * image.size.width / CGFloat(pixels.width),
                  height: bounds.height * image.size.height / CGFloat(pixels.height))
}

@Test("the archive glyph fits the independent square entry")
@MainActor
func statusHandleFitsSquareEntry() throws {
    _ = NSApplication.shared
    let button = NSStatusBarButton(frame: CGRect(x: 0, y: 0, width: 24, height: 24))
    MenuBarStatusHandle.install(on: button)
    for (width, height) in [(24.0, 24.0), (26.0, 24.0), (22.0, 22.0)] {
        button.setFrameSize(CGSize(width: width, height: height))
        let image = try #require(button.image)
        let imageFrame = try #require(button.cell?.imageRect(forBounds: button.bounds))
        let pixels = try visiblePixels(image)
        let actual = CGRect(x: imageFrame.minX + pixels.minX * imageFrame.width / image.size.width,
            y: imageFrame.minY + pixels.minY * imageFrame.height / image.size.height,
            width: pixels.width * imageFrame.width / image.size.width,
            height: pixels.height * imageFrame.height / image.size.height)
        let side = min(24, height)
        let visibleHandle = CGRect(x: width - side, y: 0, width: side, height: height)
        #expect(visibleHandle.contains(actual))
    }
}

@Test("the archive handle remains a native template button with accessible labeling")
@MainActor
func statusHandleKeepsNativeButton() throws {
    _ = NSApplication.shared
    let button = NSStatusBarButton(frame: CGRect(x: 0, y: 0, width: 24, height: 24))
    MenuBarStatusHandle.install(on: button)
    #expect(button.subviews.isEmpty)
    #expect(button.image?.isTemplate == true)
    #expect(button.accessibilityLabel() == "打开收纳栏")
    #expect(button.image?.size == CGSize(width: 16, height: 16))
}

@Test("a misplaced or oversized entry cannot be considered safe to collapse")
@MainActor
func statusHandleMustStayOnResidentSide() {
    let boundary = CGRect(x: 1040, y: 4.5, width: 3, height: 24)
    #expect(MenuBarGeometry.isOnResidentSide(handle: CGRect(x: 1060, y: 4.5, width: 24, height: 24), boundary: boundary))
    #expect(!MenuBarGeometry.isOnResidentSide(handle: CGRect(x: 1010, y: 4.5, width: 24, height: 24), boundary: boundary))
    #expect(!MenuBarGeometry.isOnResidentSide(handle: CGRect(x: 1042, y: 4.5, width: 24, height: 24), boundary: boundary))
    #expect(!MenuBarGeometry.isOnResidentSide(handle: CGRect(x: 1060, y: 500, width: 24, height: 24), boundary: boundary))
    #expect(!MenuBarGeometry.isOnResidentSide(handle: CGRect(x: 1060, y: 4.5, width: 3026, height: 24), boundary: boundary))
}

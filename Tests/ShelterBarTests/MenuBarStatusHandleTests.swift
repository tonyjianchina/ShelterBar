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

@Test("the archive glyph stays in the visible trailing handle through collapse and reveal")
@MainActor
func statusHandleRemainsVisibleWhenExpanded() throws {
    _ = NSApplication.shared
    let button = NSStatusBarButton(frame: CGRect(x: 0, y: 0, width: 24, height: 24))
    MenuBarStatusHandle.install(on: button)
    for (width, height) in [(24.0, 24.0), (3026.0, 24.0), (6002.0, 24.0), (3026.0, 22.0), (24.0, 24.0)] {
        button.setFrameSize(CGSize(width: width, height: height))
        MenuBarStatusHandle.refresh(on: button)
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
    let button = NSStatusBarButton(frame: CGRect(x: 0, y: 0, width: 3026, height: 24))
    MenuBarStatusHandle.install(on: button)
    #expect(button.subviews.isEmpty)
    #expect(button.image?.isTemplate == true)
    #expect(button.accessibilityLabel() == "打开收纳栏")
    let original = button.image
    MenuBarStatusHandle.refresh(on: button)
    #expect(button.image === original)
}

@Test("actual button frame notifications refresh the native image after resize")
@MainActor
func statusHandleTracksAsynchronousFrameChanges() async {
    _ = NSApplication.shared
    let button = NSStatusBarButton(frame: CGRect(x: 0, y: 0, width: 24, height: 24))
    let observation = MenuBarStatusHandle.install(on: button)
    for width in [3026.0, 24.0, 6002.0, 24.0] {
        button.setFrameSize(CGSize(width: width, height: 24))
        try? await Task.sleep(for: .milliseconds(10))
        let actualWidth = button.image?.size.width ?? 0
        let expectedWidth = CGFloat(max(16, width - 8))
        #expect(abs(actualWidth - expectedWidth) < 0.01)
    }
    withExtendedLifetime(observation) {}
}

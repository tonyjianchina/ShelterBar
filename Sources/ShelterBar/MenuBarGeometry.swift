import AppKit

@MainActor
enum MenuBarGeometry {
    static var desktopTop: CGFloat { NSScreen.screens.first?.frame.maxY ?? 0 }

    static func quartz(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: desktopTop - rect.maxY, width: rect.width, height: rect.height)
    }

    static func appKit(_ rect: CGRect) -> CGRect { quartz(rect) }

    static var menuBarRegions: [CGRect] {
        NSScreen.screens.map { screen in
            let height = max(NSStatusBar.system.thickness, screen.safeAreaInsets.top)
            let frame = quartz(screen.frame)
            return CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: height)
        }
    }

    static var dropRegions: [CGRect] {
        zip(NSScreen.screens, menuBarRegions).map { screen, region in
            let minX = screen.auxiliaryTopRightArea?.minX ?? screen.frame.midX
            return CGRect(x: minX + 4, y: region.minY, width: region.maxX - minX - 8, height: region.height)
        }
    }

    static func isOnMenuBar(_ frame: CGRect) -> Bool {
        frame.width > 1 && frame.height > 1 && menuBarRegion(containing: frame) != nil
    }

    static func menuBarRegion(containing frame: CGRect) -> CGRect? {
        menuBarRegion(containing: frame, regions: menuBarRegions)
    }

    static func menuBarRegion(containing frame: CGRect, regions: [CGRect]) -> CGRect? {
        // The revealed divider is one point wide; it still belongs to a display.
        guard frame.width > 0, frame.height > 0 else { return nil }
        return regions.first { $0.contains(CGPoint(x: frame.midX, y: frame.midY)) }
    }

    static func isSafeDrop(_ point: CGPoint) -> Bool { dropRegions.contains { $0.contains(point) } }

    static func statusFrame(_ item: NSStatusItem, help: String) -> CGRect? {
        if AccessibilityPermission.isGranted, let frame = MenuBarAX.ownItemFrame(help: help),
           menuBarRegion(containing: frame) != nil { return frame }
        guard let button = item.button, let window = button.window else { return nil }
        let frame = quartz(window.convertToScreen(button.convert(button.bounds, to: nil)))
        return menuBarRegion(containing: frame) != nil ? frame : nil
    }
}

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
        isOnMenuBar(frame, regions: menuBarRegions, excluded: cameraHousingRegions)
    }

    static func isOnMenuBar(_ frame: CGRect, regions: [CGRect], excluded: [CGRect]) -> Bool {
        visibleFrame(frame, regions: regions, excluded: excluded) != nil
    }

    static func visibleFrame(_ frame: CGRect) -> CGRect? {
        visibleFrame(frame, regions: menuBarRegions, excluded: cameraHousingRegions)
    }

    /// Keep partially exposed residents protected. Only a completely occluded
    /// item is hidden; drag from the largest exposed section, not a notch.
    static func visibleFrame(_ frame: CGRect, regions: [CGRect], excluded: [CGRect]) -> CGRect? {
        guard frame.width > 1, frame.height > 1 else { return nil }
        var segments: [CGRect] = []
        for region in regions where frame.midY >= region.minY && frame.midY < region.maxY {
            let left = max(frame.minX, region.minX), right = min(frame.maxX, region.maxX)
            guard right > left else { continue }
            var exposed = [CGRect(x: left, y: frame.minY, width: right - left, height: frame.height)]
            for obstruction in excluded {
                exposed = exposed.flatMap { segment -> [CGRect] in
                    let overlap = segment.intersection(obstruction)
                    guard overlap.width > 0, overlap.height > 0 else { return [segment] }
                    var remainder: [CGRect] = []
                    if overlap.minX > segment.minX {
                        remainder.append(CGRect(x: segment.minX, y: segment.minY,
                                                width: overlap.minX - segment.minX, height: segment.height))
                    }
                    if overlap.maxX < segment.maxX {
                        remainder.append(CGRect(x: overlap.maxX, y: segment.minY,
                                                width: segment.maxX - overlap.maxX, height: segment.height))
                    }
                    return remainder
                }
            }
            segments.append(contentsOf: exposed)
        }
        return segments.max { $0.width < $1.width }
    }

    private static var cameraHousingRegions: [CGRect] {
        NSScreen.screens.compactMap { screen in
            guard let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea,
                  right.minX > left.maxX else { return nil }
            return quartz(CGRect(x: left.maxX, y: left.minY, width: right.minX - left.maxX,
                                 height: left.height))
        }
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

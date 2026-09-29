import SwiftUI

enum ShelfLayoutMetrics {
    static let contentHeight: CGFloat = 54
    static let panelHeight: CGFloat = contentHeight + 12
    static let menuBarGap: CGFloat = 5
    static let iconRowHeight: CGFloat = 36
    static let dividerHeight: CGFloat = 26
    static let cornerRadius: CGFloat = 15
}

struct ShelfView: View {
    @ObservedObject var model: ShelfViewModel
    let onActivate: (ShelfItem) -> Void
    let onReturn: (String, CGPoint) -> Void
    let onDragging: (Bool) -> Void
    let onPinChange: (Bool) -> Void
    let onRevealAll: () -> Void
    let onQuit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "archivebox.fill").foregroundStyle(.secondary)
                Text("收纳栏").font(.system(size: 12, weight: .semibold))
                Text("\(model.items.count)").font(.system(size: 10, weight: .bold, design: .rounded))
                    .padding(.horizontal, 6).padding(.vertical, 2).background(.quaternary, in: Capsule())
            }.fixedSize()
            Divider().frame(height: ShelfLayoutMetrics.dividerHeight)
            if !model.hasAccessibilityPermission {
                Text("允许辅助功能后，即可拖动顶部图标")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Button("授予权限", action: model.requestAccessibilityPermission).controlSize(.small)
                Button("打开设置", action: model.openAccessibilitySettings).controlSize(.small)
            } else if let message = model.message {
                Text(message).font(.system(size: 11)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .help(message)
                Button { model.message = nil } label: { Image(systemName: "xmark.circle") }.buttonStyle(.plain)
            } else if model.items.isEmpty {
                Text(model.isBusy ? "正在更新收纳栏…" : "将顶部图标拖到这里")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(model.items) { item in
                            ShelfIcon(item: item, onActivate: { onActivate(item) },
                                      onReturn: onReturn, onReorder: model.move, onDragging: onDragging)
                                .frame(width: MenuBarIconPresentation.shelfWidth(for: item.icon),
                                       height: ShelfLayoutMetrics.iconRowHeight)
                        }
                    }
                }
            }
            if model.hasAccessibilityPermission && !model.hasScreenCapturePermission {
                Button(action: model.requestScreenCapturePermission) {
                    Image(systemName: "photo.badge.plus").frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(model.screenCapturePermissionHint
                    ?? "收纳功能已可用。允许屏幕录制后可显示原始菜单栏图标，内容仅在本机读取。")
            }
            if model.isBusy {
                ProgressView().controlSize(.small).help("正在移动图标…")
            }
            Divider().frame(height: ShelfLayoutMetrics.dividerHeight)
            Button { onPinChange(!model.isPinned) } label: {
                Image(systemName: model.isPinned ? "pin.fill" : "pin").frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(model.isPinned ? Color.accentColor : .secondary)
            .help(model.isPinned ? "取消固定" : "固定收纳栏")
            Menu {
                Button("刷新并恢复收纳") { model.onRefresh?() }
                Button("显示全部顶部图标", action: onRevealAll)
                Divider()
                Button("辅助功能设置", action: model.openAccessibilitySettings)
                Button("屏幕录制设置", action: model.openScreenCaptureSettings)
                Button("退出 ShelterBar", action: onQuit)
            } label: {
                Image(systemName: "ellipsis.circle").frame(width: 24, height: 24)
            }.menuStyle(.borderlessButton).fixedSize().help("更多")
        }
        .padding(.horizontal, 14).padding(.vertical, 8).frame(height: ShelfLayoutMetrics.contentHeight)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: ShelfLayoutMetrics.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: ShelfLayoutMetrics.cornerRadius)
                .strokeBorder(model.isDropTargeted ? Color.accentColor : .white.opacity(0.18),
                              lineWidth: model.isDropTargeted ? 2 : 0.5)
        }
        .overlay(alignment: .bottom) {
            if model.isDraggingToMenuBar {
                Text("拖到上方菜单栏松开，即可移回").font(.system(size: 10))
                    .padding(5).background(.regularMaterial, in: Capsule()).offset(y: 18)
            }
        }
        .padding(6)
    }
}

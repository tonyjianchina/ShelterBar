import SwiftUI

enum ShelfLayoutMetrics {
    static let contentHeight: CGFloat = 54
    static let panelHeight: CGFloat = contentHeight + 12
    static let menuBarGap: CGFloat = 5
    static let iconRowHeight: CGFloat = 36
    static let dividerHeight: CGFloat = 26
    static let cornerRadius: CGFloat = 15

    static func panelHeight(notice: ShelfNotice?) -> CGFloat {
        panelHeight + (notice?.height ?? 0)
    }
}

/// Notices occupy their own row. Optional permissions and status messages must
/// never remove the controls users need to open or return a collected item.
enum ShelfNotice: Equatable {
    case inputPermission(String)
    case recordingPermission(String)
    case message(String)
    case dragHint

    var height: CGFloat {
        switch self {
        case .inputPermission, .recordingPermission: 64
        case .message, .dragHint: 42
        }
    }

    @MainActor static func current(_ model: ShelfViewModel) -> ShelfNotice? {
        if model.isDraggingToMenuBar { return .dragHint }
        if !model.hasAccessibilityPermission { return .inputPermission(model.inputPermissionGuidance) }
        // Surface operation feedback even when recording is declined. The
        // optional permission reminder reappears after the message is closed.
        if let message = model.message { return .message(message) }
        if !model.hasScreenCapturePermission {
            return .recordingPermission(model.screenCapturePermissionHint
                ?? "收纳与点击照常可用。允许录屏可显示原始图标。")
        }
        return nil
    }
}

struct ShelfView: View {
    @ObservedObject var model: ShelfViewModel
    let onActivate: (ShelfItem) -> Void
    let onReturn: (String, CGPoint) -> Void
    let onDragging: (Bool) -> Void
    let onDragPosition: (String, CGPoint) -> Void
    let onPinChange: (Bool) -> Void
    let onRevealAll: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            iconRow
                .padding(.horizontal, 14)
                .frame(height: ShelfLayoutMetrics.contentHeight)
            if let notice = ShelfNotice.current(model) {
                noticeRow(notice)
                    .frame(height: notice.height)
                    .overlay(alignment: .top) { Divider().padding(.horizontal, 14) }
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: ShelfLayoutMetrics.cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: ShelfLayoutMetrics.cornerRadius)
                .strokeBorder(model.isDropTargeted ? Color.accentColor : .white.opacity(0.18),
                              lineWidth: model.isDropTargeted ? 2 : 0.5)
        }
        .padding(6)
    }

    private var iconRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "archivebox.fill").foregroundStyle(.secondary)
                Text("收纳栏").font(.system(size: 12, weight: .semibold))
                Text("\(model.items.count)").font(.system(size: 10, weight: .bold, design: .rounded))
                    .padding(.horizontal, 6).padding(.vertical, 2).background(.quaternary, in: Capsule())
            }
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("收纳栏，\(model.items.count) 个图标")
            Divider().frame(height: ShelfLayoutMetrics.dividerHeight)
            if model.items.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: model.isDropTargeted ? "arrow.down.to.line" : "cursorarrow.and.square.on.square.dashed")
                    Text(model.isBusy ? "正在整理…" : (model.isDropTargeted ? "松开即可收纳" : "拖入顶部图标"))
                }
                .font(.system(size: 11))
                .foregroundStyle(model.isDropTargeted ? Color.accentColor : .secondary)
                .frame(maxWidth: .infinity)
                .lineLimit(1)
                .help("将可移动的顶部菜单栏图标拖入这里；拖回顶部即可恢复。")
            } else {
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(spacing: 5) {
                        ForEach(model.items) { item in
                            ShelfIcon(item: item, onActivate: { onActivate(item) },
                                      onReturn: onReturn, onReorder: model.move, onDragging: onDragging,
                                      onDragPosition: onDragPosition)
                                .frame(width: MenuBarIconPresentation.shelfWidth(for: item.icon),
                                       height: ShelfLayoutMetrics.iconRowHeight)
                        }
                    }
                }
                .frame(height: ShelfLayoutMetrics.iconRowHeight + 8)
                .accessibilityLabel("已收纳的图标")
            }
            if model.isBusy {
                ProgressView().controlSize(.small).help("正在移动图标…")
                    .accessibilityLabel("正在整理收纳栏")
            }
            Divider().frame(height: ShelfLayoutMetrics.dividerHeight)
            Button { onPinChange(!model.isPinned) } label: {
                Image(systemName: model.isPinned ? "pin.fill" : "pin").frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(model.isPinned ? Color.accentColor : .secondary)
            .help(model.isPinned ? "取消固定" : "固定收纳栏")
            .accessibilityLabel(model.isPinned ? "取消固定收纳栏" : "固定收纳栏")
            .accessibilityIdentifier("shelterbar.pin")
            Menu {
                Button("刷新并恢复收纳") { model.onRefresh?() }
                Button("显示全部顶部图标", action: onRevealAll)
                Divider()
                Button(action: model.checkForUpdates) {
                    Label(model.updateMenuTitle, systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(model.isUpdating)
                .accessibilityIdentifier("shelterbar.check-updates")
                Divider()
                Button("输入控制权限", action: model.openAccessibilitySettings)
                Button("屏幕录制设置", action: model.openScreenCaptureSettings)
                Button("退出 ShelterBar", action: onQuit)
                Divider()
                Text(verbatim: AppVersion.menuTitle()).foregroundStyle(.secondary)
            } label: {
                Image(systemName: "ellipsis.circle").frame(width: 24, height: 24)
            }
            .menuStyle(.borderlessButton).fixedSize().help("更多")
            .accessibilityLabel("收纳栏更多操作")
        }
    }

    @ViewBuilder private func noticeRow(_ notice: ShelfNotice) -> some View {
        switch notice {
        case let .inputPermission(text):
            permissionNotice(text, actionTitle: "授予输入权限", action: model.requestAccessibilityPermission,
                             settings: model.openAccessibilitySettings)
        case let .recordingPermission(text):
            permissionNotice(text, actionTitle: "允许录屏", action: model.requestScreenCapturePermission,
                             settings: model.openScreenCaptureSettings)
        case let .message(text):
            HStack(spacing: 8) {
                Image(systemName: "info.circle").foregroundStyle(.secondary)
                Text(text).font(.system(size: 11)).lineLimit(2).help(text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button { model.message = nil } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .accessibilityLabel("关闭提示")
                .accessibilityIdentifier("shelterbar.dismiss-notice")
            }.padding(.horizontal, 14)
        case .dragHint:
            Label("拖到上方菜单栏松开，即可移回", systemImage: "arrow.up")
                .font(.system(size: 11)).foregroundStyle(Color.accentColor)
                .frame(maxWidth: .infinity)
        }
    }

    private func permissionNotice(_ text: String, actionTitle: String,
                                  action: @escaping () -> Void, settings: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text).font(.system(size: 11)).foregroundStyle(.secondary)
                .lineLimit(2).help(text).frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                Button(actionTitle, action: action).controlSize(.small)
                Button("打开设置", action: settings).controlSize(.small)
            }
        }.padding(.horizontal, 14).padding(.vertical, 8)
    }
}

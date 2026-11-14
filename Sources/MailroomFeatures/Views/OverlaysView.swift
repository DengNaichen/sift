import SwiftUI
import MailroomCore

struct InboxZeroView: View {
    @Environment(\.palette) private var p
    let vm: DeckViewModel

    private var personalHandledCount: Int {
        vm.state.tally.archived + vm.state.tally.kept + vm.state.tally.trashed
    }

    private var stats: [(String, Int)] {
        [
            ("阅毕归档", vm.state.tally.archived),
            ("重要保留", vm.state.tally.kept),
            ("判为推广", vm.state.tally.trashed),
            ("AI 自动挡下", vm.state.handled.count)
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            InboxZeroRidgeArtView()
                .frame(height: 148)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(p.line).frame(height: 1)
                }

            VStack(spacing: 0) {
                Text("待处理收件箱已清零")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(p.ink)

                Group {
                    if personalHandledCount > 0 {
                        Text("今天你亲自拍板了 \(personalHandledCount) 封信，其余推广与系统通知已由 AI 静默分拣。")
                    } else {
                        Text("没有需要你处理的事。去做点更重要的事吧。")
                    }
                }
                .font(.system(size: 13))
                .foregroundStyle(p.ink3)
                .lineSpacing(3)
                .multilineTextAlignment(.center)
                .padding(.top, 8)

                HStack(spacing: 0) {
                    ForEach(Array(stats.enumerated()), id: \.offset) { idx, pair in
                        VStack(spacing: 3) {
                            Text("\(pair.1)")
                                .font(.system(size: 17, weight: .semibold, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(p.ink)
                            Text(pair.0)
                                .font(.system(size: 11))
                                .foregroundStyle(p.ink3)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .overlay(alignment: .trailing) {
                            if idx < stats.count - 1 {
                                Rectangle().fill(p.line).frame(width: 1)
                            }
                        }
                    }
                }
                .background(p.sunken, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(p.line, lineWidth: 1)
                )
                .padding(.top, 22)

                HStack(spacing: 8) {
                    if vm.sourceMode == .appleMail {
                        Button {
                            Task { await vm.reloadSnapshot(initial: false) }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 12.5, weight: .medium))
                                Text("刷新 Apple Mail 收件箱")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundStyle(p.canvas)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(p.ink, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    } else if vm.supportsDemoControls {
                        Button {
                            Task { await vm.simulateIncoming() }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "tray.and.arrow.down")
                                    .font(.system(size: 12.5, weight: .medium))
                                Text("模拟收到 3 封新邮件")
                                    .font(.system(size: 13, weight: .medium))
                            }
                            .foregroundStyle(p.canvas)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(p.ink, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button {
                            Task { await vm.resetDemo() }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 12))
                                Text("重置演示数据")
                                    .font(.system(size: 13))
                            }
                            .foregroundStyle(p.ink2)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(p.lineStrong, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 22)

                if !vm.state.undo.isEmpty {
                    HStack(spacing: 5) {
                        Text("手滑了？按")
                        KbdView(text: "Z")
                        Text("把上一封邮件拿回来")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(p.ink3)
                    .padding(.top, 16)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 26)
        }
        .background(p.paper)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(p.line, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 18, y: 8)
    }
}

private struct InboxZeroRidgeArtView: View {
    @Environment(\.palette) private var p

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                LinearGradient(
                    colors: [p.ridgeSkyTop, p.ridgeSkyBottom],
                    startPoint: .top,
                    endPoint: .bottom
                )

                // Sun / Moon geometric disc
                Circle()
                    .fill(p.cobalt.opacity(0.22))
                    .frame(width: 32, height: 32)
                    .position(x: w * 0.77, y: h * 0.30)

                // Far ridge
                Path { path in
                    path.move(to: CGPoint(x: 0, y: h * 0.76))
                    path.addLine(to: CGPoint(x: w * 0.20, y: h * 0.50))
                    path.addLine(to: CGPoint(x: w * 0.42, y: h * 0.67))
                    path.addLine(to: CGPoint(x: w * 0.68, y: h * 0.42))
                    path.addLine(to: CGPoint(x: w * 0.87, y: h * 0.60))
                    path.addLine(to: CGPoint(x: w, y: h * 0.50))
                    path.addLine(to: CGPoint(x: w, y: h))
                    path.addLine(to: CGPoint(x: 0, y: h))
                    path.closeSubpath()
                }
                .fill(p.ridge1)

                // Mid ridge
                Path { path in
                    path.move(to: CGPoint(x: 0, y: h * 0.85))
                    path.addLine(to: CGPoint(x: w * 0.29, y: h * 0.58))
                    path.addLine(to: CGPoint(x: w * 0.55, y: h * 0.78))
                    path.addLine(to: CGPoint(x: w * 0.82, y: h * 0.55))
                    path.addLine(to: CGPoint(x: w, y: h * 0.72))
                    path.addLine(to: CGPoint(x: w, y: h))
                    path.addLine(to: CGPoint(x: 0, y: h))
                    path.closeSubpath()
                }
                .fill(p.ridge2)

                // Near ridge
                Path { path in
                    path.move(to: CGPoint(x: 0, y: h * 0.92))
                    path.addLine(to: CGPoint(x: w * 0.39, y: h * 0.73))
                    path.addLine(to: CGPoint(x: w * 0.70, y: h * 0.88))
                    path.addLine(to: CGPoint(x: w, y: h * 0.68))
                    path.addLine(to: CGPoint(x: w, y: h))
                    path.addLine(to: CGPoint(x: 0, y: h))
                    path.closeSubpath()
                }
                .fill(p.ridge3)
            }
        }
    }
}

struct KeyboardHUDView: View {
    @Environment(\.palette) private var p
    let items: [HudItem]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                if idx > 0 {
                    Rectangle()
                        .fill(p.ink.opacity(0.09))
                        .frame(width: 1, height: 12)
                        .padding(.horizontal, 2)
                }
                HudPillButton(item: item)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4.5)
        .deckGlassCapsule(interactive: true)
    }
}

private struct HudPillButton: View {
    @Environment(\.palette) private var p
    let item: HudItem
    @State private var hovered = false

    var body: some View {
        Button(action: item.action) {
            HStack(spacing: 5) {
                HStack(spacing: 2) {
                    ForEach(item.keys, id: \.self) { k in
                        KbdView(text: k)
                    }
                }
                Text(item.label)
                    .font(.system(size: 11.5))
                    .foregroundStyle(hovered && !item.disabled ? p.ink : p.ink2)
            }
            .padding(.horizontal, 7.5)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(hovered && !item.disabled ? p.ink.opacity(p.mode == .dark ? 0.10 : 0.055) : .clear)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(item.disabled)
        .opacity(item.disabled ? 0.38 : 1.0)
        .onHover { hovered = $0 }
    }
}

struct UndoToastView: View {
    @Environment(\.palette) private var p
    let toast: DeckToast
    let onUndo: () -> Void
    @State private var undoHovered = false

    var body: some View {
        HStack(spacing: 10) {
            if toast.kind == .done {
                Text(toast.entry.descriptionText)
                    .font(.system(size: 12.5))
                    .foregroundStyle(p.ink)
                    .lineLimit(1)

                Spacer(minLength: 4)

                Button(action: onUndo) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(p.ink2)
                        Text("撤销")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(p.ink)
                        KbdView(text: "Z")
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4.5)
                    .background(
                        Capsule()
                            .fill(p.ink.opacity(undoHovered ? (p.mode == .dark ? 0.16 : 0.10) : (p.mode == .dark ? 0.11 : 0.065)))
                    )
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .onHover { undoHovered = $0 }
            } else {
                Image(systemName: "checkmark")
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(p.ink)
                Text("已撤销，邮件已放回原位")
                    .font(.system(size: 12.5))
                    .foregroundStyle(p.ink)
                Spacer()
            }
        }
        .padding(.leading, 15)
        .padding(.trailing, 7)
        .padding(.vertical, 6)
        .frame(width: 356)
        .deckGlassCapsule(interactive: true)
    }
}

struct NativeNoticeBanner: View {
    @Environment(\.palette) private var p
    let url: String

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(p.ink.opacity(p.mode == .dark ? 0.11 : 0.065))
                    .frame(width: 28, height: 28)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(p.ink)
            }
            VStack(alignment: .leading, spacing: 1.5) {
                Text("正在 Apple Mail 中打开原信")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(p.ink)
                Text(url.removingPercentEncoding ?? url)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(p.ink3)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 8)
        .padding(.leading, 9)
        .padding(.trailing, 16)
        .frame(maxWidth: 420)
        .deckGlassCapsule()
    }
}

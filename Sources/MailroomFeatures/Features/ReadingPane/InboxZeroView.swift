import SwiftUI
import MailroomCore

struct InboxZeroView: View {
    @Environment(\.palette) private var p
    let model: InboxZeroViewModel

    private var personalHandledCount: Int { model.personalHandledCount }
    private var stats: [(String, Int)] { model.stats }

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
                    if model.isLiveSource {
                        Button {
                            model.perform(.syncNow)
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
                    } else if model.showsDemoControls {
                        Button {
                            model.perform(.simulateIncoming)
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
                            model.perform(.resetDemo)
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

                if model.canUndo {
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

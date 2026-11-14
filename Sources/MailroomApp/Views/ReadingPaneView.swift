import SwiftUI
import MailroomCore

struct ReadingPaneView: View {
    @Environment(\.palette) private var p
    let vm: DeckViewModel
    @State private var webContentHeight: CGFloat = 220
    @State private var openMailHovered = false
    @Namespace private var topGlassNS
    @Namespace private var bottomGlassNS

    private var activeRow: FolderRow? { vm.activeRow }
    private var content: MailContent? { activeRow?.content }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // 1. 权限引导或操作错误提示条（非阻塞）
                if case .fullDiskAccessRequired = vm.accessStatus, vm.sourceMode == .demo {
                    fdaOnboardingBanner
                } else if let err = vm.errorMessage {
                    errorBanner(err)
                }

                // 2. 全高沉浸阅读区 + 顶部悬浮 Liquid Glass 拍板胶囊组（向上滚动时正文从玻璃下方折射穿过）
                ZStack(alignment: .top) {
                    if let content {
                        ScrollViewReader { proxy in
                            ScrollView(.vertical) {
                                VStack(alignment: .leading, spacing: 0) {
                                    articleHeader(content: content)
                                        .id("mail-top")

                                    if vm.hydratingIds.contains(content.id) {
                                        hydratingBanner
                                    }

                                    if let html = content.htmlBody, !html.isEmpty, !vm.preferPlainText {
                                        if content.hasRemoteImages && !vm.allowedRemoteImageIds.contains(content.id) {
                                            remoteImagePrivacyBar(for: content.id)
                                        }

                                        MailHTMLWebView(
                                            messageId: content.id,
                                            html: html,
                                            allowRemoteImages: vm.allowedRemoteImageIds.contains(content.id),
                                            themeMode: vm.themeMode,
                                            dynamicHeight: $webContentHeight
                                        )
                                        .frame(height: max(120, webContentHeight))
                                        .padding(.horizontal, 32)
                                        .padding(.top, 20)
                                        .padding(.bottom, 108)
                                        .frame(maxWidth: 784, alignment: .leading)
                                    } else {
                                        PlainTextBodyView(text: content.plainText)
                                            .padding(.horizontal, 32)
                                            .padding(.top, 22)
                                            .padding(.bottom, 108)
                                            .frame(maxWidth: 784, alignment: .leading)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .borderlessScroller()
                            }
                            .onChange(of: content.id) { _, _ in
                                vm.hydrateIfNeeded(for: content)
                                scrollToTop(proxy: proxy)
                            }
                            .onAppear {
                                vm.hydrateIfNeeded(for: content)
                                scrollToTop(proxy: proxy)
                            }
                        }
                    } else {
                        emptyReadingArea
                    }

                    floatingTopToolbar
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // 3. 底部悬浮撤销提示与快捷键胶囊 HUD（GlassEffectContainer 水滴聚拢）
            DeckGlassCluster(spacing: 16) {
                VStack(spacing: 10) {
                    if let toast = vm.state.toast {
                        UndoToastView(toast: toast) {
                            _ = vm.undo()
                        }
                        .deckGlassID("undo-toast", in: bottomGlassNS)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    if vm.showKeyboardHUD {
                        KeyboardHUDView(items: vm.hudItems)
                            .deckGlassID("keyboard-hud", in: bottomGlassNS)
                    }
                }
            }
            .animation(.bouncy(duration: 0.34, extraBounce: 0.05), value: vm.state.toast)
            .animation(.snappy(duration: 0.22), value: vm.showKeyboardHUD)
            .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(p.paper)
    }

    private func scrollToTop(proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(.easeInOut(duration: 0.22)) {
                proxy.scrollTo("mail-top", anchor: .top)
            }
        }
    }

    // MARK: - Subviews

    private var floatingTopToolbar: some View {
        HStack(spacing: 8) {
            if let idx = vm.activeIndex {
                Text("\(idx + 1) / \(vm.visibleRows.count)")
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(p.ink2)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .deckGlassCapsule()
            }

            Spacer(minLength: 8)

            DeckGlassCluster(spacing: 8) {
                HStack(spacing: 7) {
                    if activeRow != nil || !vm.state.undo.isEmpty {
                        HStack(spacing: 2) {
                            if let row = activeRow {
                                switch row {
                                case .inbox:
                                    PaneToolbarButton(title: "归档", systemImage: "archivebox", help: "阅毕归档（Space）") {
                                        vm.actOnCard(.archive)
                                    }
                                    PaneToolbarButton(title: "保留", systemImage: "flag", help: "重要保留（⇧K）") {
                                        vm.actOnCard(.keep)
                                    }
                                    PaneToolbarButton(title: "推广", systemImage: "trash", help: "判为推广并移入废纸篓（⌫）") {
                                        vm.actOnCard(.trash)
                                    }

                                case .handled:
                                    PaneToolbarButton(title: "拉回待处理", systemImage: "arrow.uturn.backward", help: "拉回待处理（R）") {
                                        vm.rescueFocused()
                                    }

                                case .kept:
                                    HStack(spacing: 5) {
                                        Image(systemName: "flag.fill")
                                            .font(.system(size: 11))
                                            .foregroundStyle(p.amber)
                                        Text("已标旗保留")
                                            .font(.system(size: 12))
                                            .foregroundStyle(p.ink2)
                                    }
                                    .padding(.horizontal, 8)
                                    .frame(height: 26)
                                }

                                Rectangle()
                                    .fill(p.ink.opacity(0.09))
                                    .frame(width: 1, height: 12)
                                    .padding(.horizontal, 2)
                            }

                            PaneToolbarButton(
                                title: "撤销",
                                systemImage: "arrow.uturn.backward",
                                disabled: vm.state.undo.isEmpty,
                                help: "撤销上一步（Z）"
                            ) {
                                _ = vm.undo()
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .frame(minHeight: 30)
                        .deckGlassCapsule(interactive: true)
                        .deckGlassID("triage-actions", in: topGlassNS)
                    }

                    if content != nil {
                        Button {
                            vm.openFocusedInNativeMail()
                        } label: {
                            HStack(spacing: 4.5) {
                                Text("Apple Mail")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(openMailHovered ? p.ink : p.ink2)
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(openMailHovered ? p.ink2 : p.ink3)
                            }
                            .padding(.horizontal, 11)
                            .frame(height: 30)
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .onHover { openMailHovered = $0 }
                        .help("在 Apple Mail 中打开（↵）")
                        .deckGlassCapsule(interactive: true)
                        .deckGlassID("open-apple-mail", in: topGlassNS)
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 9)
    }

    private var fdaOnboardingBanner: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(p.amber)
                .frame(width: 6.5, height: 6.5)
            Text("当前正在浏览演示数据。授权「完全磁盘访问权限」即可实时接入本机 Apple Mail。")
                .font(.system(size: 12))
                .foregroundStyle(p.ink2)
                .lineLimit(1)
            Spacer()
            Button("打开系统设置") {
                MailStoreEnvironment.openFullDiskAccessSettings()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(p.ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(p.paper, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(p.lineStrong, lineWidth: 1))

            Button("重新连接") {
                vm.recheckAccessAndSwitchToAppleMail()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(p.canvas)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(p.ink, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(p.sunken)
        .overlay(alignment: .bottom) {
            Rectangle().fill(p.line).frame(height: 1)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(p.coral)
                .frame(width: 6.5, height: 6.5)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(p.ink2)
                .lineLimit(2)
            Spacer()
            Button("关闭") {
                vm.dismissError()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11.5))
            .foregroundStyle(p.ink3)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(p.sunken)
        .overlay(alignment: .bottom) {
            Rectangle().fill(p.line).frame(height: 1)
        }
    }

    private var hydratingBanner: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("正在从 Apple Mail 同步完整邮件内容…")
                .font(.system(size: 12))
                .foregroundStyle(p.ink2)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(p.sunken, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .padding(.horizontal, 32)
        .padding(.top, 14)
        .frame(maxWidth: 784, alignment: .leading)
    }

    private func remoteImagePrivacyBar(for messageId: MessageId) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "eye.slash")
                .font(.system(size: 11.5))
                .foregroundStyle(p.ink3)
            Text("已拦截远程图片以防追踪")
                .font(.system(size: 12))
                .foregroundStyle(p.ink2)
            Spacer()
            Button {
                vm.allowRemoteImages(for: messageId)
            } label: {
                Text("显示图片")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(p.ink)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3.5)
                    .background(p.paper, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(p.lineStrong, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help("仅对当前邮件加载外部远程图片")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(p.sunken, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .padding(.horizontal, 32)
        .padding(.top, 14)
        .frame(maxWidth: 784, alignment: .leading)
    }

    private func articleHeader(content: MailContent) -> some View {
        let avatarTone = p.pickTone(seed: content.from.address.isEmpty ? content.from.name : content.from.address)
        let avatarLetter = String(content.from.name.prefix(1)).uppercased()

        return VStack(alignment: .leading, spacing: 14) {
            Text(content.subject)
                .font(.system(size: 18.5, weight: .semibold))
                .foregroundStyle(p.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(avatarTone.opacity(0.11))
                    Text(avatarLetter)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(avatarTone)
                }
                .frame(width: 28, height: 28)
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(content.from.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(p.ink)
                        if !content.from.address.isEmpty {
                            Text("<\(content.from.address)>")
                                .font(.system(size: 12))
                                .foregroundStyle(p.ink3)
                                .textSelection(.enabled)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(MailFormatting.formatTime(content.receivedAt))
                            .font(.system(size: 11.5, design: .monospaced))
                            .monospacedDigit()
                            .foregroundStyle(p.ink3)
                    }

                    HStack(spacing: 6) {
                        Text("发至")
                            .font(.system(size: 12))
                            .foregroundStyle(p.ink3)

                        Circle()
                            .fill(p.accountDotColor(content.account.id))
                            .frame(width: 5.5, height: 5.5)

                        Text(content.account.label)
                            .font(.system(size: 12))
                            .foregroundStyle(p.ink2)

                        if !content.account.address.isEmpty {
                            Text("(\(content.account.address))")
                                .font(.system(size: 12))
                                .foregroundStyle(p.ink3)
                                .textSelection(.enabled)
                                .lineLimit(1)
                        }
                    }
                }
            }

            if !content.attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(content.attachments) { att in
                            HStack(spacing: 6) {
                                Image(systemName: att.kind == .pdf ? "doc.text" : "paperclip")
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(p.ink3)
                                Text(att.name)
                                    .font(.system(size: 12))
                                    .foregroundStyle(p.ink2)
                                Text(att.size)
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(p.ink3)
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4.5)
                            .background(p.sunken, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                    }
                }
                .padding(.leading, 40)
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 56)
        .padding(.bottom, 6)
        .frame(maxWidth: 784, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyReadingArea: some View {
        VStack {
            Spacer()
            if vm.state.folder.isInboxFolder {
                InboxZeroView(vm: vm)
                    .frame(maxWidth: 492)
            } else {
                Text("该分拣夹当前没有邮件")
                    .font(.system(size: 13))
                    .foregroundStyle(p.ink3)
            }
            Spacer()
        }
        .padding(32)
        .padding(.bottom, 60)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PlainTextBodyView: View {
    @Environment(\.palette) private var p
    let text: String

    private var paragraphs: [String] {
        text.components(separatedBy: "\n\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, para in
                Text(para)
                    .font(.system(size: 13.5))
                    .foregroundStyle(p.ink2)
                    .lineSpacing(6.5)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct PaneToolbarButton: View {
    @Environment(\.palette) private var p
    let title: String
    let systemImage: String
    var active: Bool = false
    var disabled: Bool = false
    let help: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 11.5, weight: .medium))
                Text(title)
                    .font(.system(size: 12, weight: active ? .medium : .regular))
            }
            .foregroundStyle((active || (hovered && !disabled)) ? p.ink : p.ink2)
            .padding(.horizontal, 8.5)
            .frame(height: 26)
            .background {
                if active {
                    Capsule()
                        .fill(p.ink.opacity(p.mode == .dark ? 0.14 : 0.085))
                } else if hovered && !disabled {
                    Capsule()
                        .fill(p.ink.opacity(p.mode == .dark ? 0.10 : 0.055))
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.38 : 1.0)
        .onHover { hovered = $0 }
        .help(help)
    }
}

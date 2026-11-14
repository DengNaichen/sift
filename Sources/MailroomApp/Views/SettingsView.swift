import AppKit
import SwiftUI
import MailroomCore

struct SettingsSidebarView: View {
    @Environment(\.palette) private var p
    let vm: DeckViewModel
    @State private var backHovered = false
    @State private var searchHovered = false

    private var connectionSections: [SettingsSection] {
        [.accounts, .triage, .ai]
    }

    private var workspaceSections: [SettingsSection] {
        [.appearance, .diagnostics]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 1. 返回收件箱顶栏（与 SidebarView 32pt 品牌栏等高对齐）
            Button {
                vm.closeSettings()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(backHovered ? p.ink : p.ink2)
                    Text("返回收件箱")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(p.ink)
                    Spacer()
                    KbdView(text: "esc")
                }
                .padding(.horizontal, 8)
                .frame(height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(backHovered ? p.ink.opacity(0.045) : Color.clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { backHovered = $0 }
            .help("返回收件箱（Esc）")

            // 2. 搜索与命令入口（与收件箱侧栏一致的交互式 Liquid Glass 胶囊）
            Button {
                vm.paletteOpen = true
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(searchHovered ? p.ink2 : p.ink3)
                    Text("搜索与命令")
                        .font(.system(size: 12))
                        .foregroundStyle(searchHovered ? p.ink2 : p.ink3)
                    Spacer()
                    KbdView(text: "⌘K")
                }
                .padding(.leading, 10)
                .padding(.trailing, 7)
                .frame(height: 29)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .onHover { searchHovered = $0 }
            .deckGlassCapsule(interactive: true)
            .padding(.top, 8)

            // 3. 五大设置分组
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    sectionGroup(title: "连接与分拣", items: connectionSections)
                    sectionGroup(title: "工作台", items: workspaceSections)
                }
                .padding(.vertical, 14)
            }

            Spacer(minLength: 0)

            // 4. 底部控制按钮（与收件箱侧栏一致极简留白）
            HStack(spacing: 0) {
                Spacer(minLength: 0)

                Button {
                    vm.closeSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(p.ink)
                        .frame(width: 28, height: 28)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .deckGlassCapsule(interactive: true)
                .help("关闭设置（⌘,）")
            }
            .frame(height: 30)
            .padding(.trailing, 1)
        }
        .padding(.horizontal, 10)
        .padding(.top, 4)
        .padding(.bottom, 8)
        .frame(width: 206)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func sectionGroup(title: String, items: [SettingsSection]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10.5, weight: .medium))
                .tracking(0.3)
                .foregroundStyle(p.ink3)
                .padding(.horizontal, 8)
                .padding(.bottom, 2)

            ForEach(items) { sec in
                let active = (vm.settings.activeSection == sec)
                Button {
                    withAnimation(.snappy(duration: 0.16)) {
                        vm.settings.activeSection = sec
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: sec.iconName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(active ? p.ink : p.ink3)
                            .frame(width: 15)

                        Text(sec.title)
                            .font(.system(size: 12.5, weight: active ? .medium : .regular))
                            .foregroundStyle(active ? p.ink : p.ink2)
                            .lineLimit(1)

                        Spacer(minLength: 4)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(active ? p.ink.opacity(0.065) : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct SettingsWorkspaceView: View {
    @Environment(\.palette) private var p
    let vm: DeckViewModel

    private var s: SettingsShellState { vm.settings }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 0) {
                // 44pt 顶栏面包屑（与邮件列表/阅读区顶栏严格同高）
                HStack(spacing: 7) {
                    Text("设置")
                        .font(.system(size: 12.5))
                        .foregroundStyle(p.ink3)
                    Text("/")
                        .font(.system(size: 12.5))
                        .foregroundStyle(p.ink3.opacity(0.6))
                    Text(s.activeSection.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(p.ink)

                    Spacer()

                    KbdView(text: "⌘,")
                }
                .padding(.horizontal, 28)
                .padding(.top, 4)
                .frame(height: 44)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(p.line).frame(height: 1)
                }

                // 主体单栏居中滚动区
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 26) {
                            Color.clear
                                .frame(height: 0)
                                .id("settings-top")

                            Text(s.activeSection.title)
                                .font(.system(size: 17.5, weight: .semibold))
                                .foregroundStyle(p.ink)

                            switch s.activeSection {
                            case .accounts:
                                AccountsSettingsTabView(vm: vm)
                            case .triage:
                                TriageSettingsTabView(vm: vm)
                            case .ai:
                                AIClassifierSettingsTabView(vm: vm)
                            case .appearance:
                                AppearanceSettingsTabView(vm: vm)
                            case .diagnostics:
                                DiagnosticsSettingsTabView(vm: vm)
                            }
                        }
                        .frame(maxWidth: 620, alignment: .leading)
                        .padding(.horizontal, 36)
                        .padding(.top, 26)
                        .padding(.bottom, 48)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .borderlessScroller()
                    }
                    .onChange(of: s.activeSection) { _, _ in
                        proxy.scrollTo("settings-top", anchor: .top)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            if let banner = s.transientBannerText {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(p.ink2)
                    Text(banner)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(p.ink)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7.5)
                .deckGlassCapsule()
                .padding(.trailing, 22)
                .padding(.bottom, 18)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(p.paper)
        .onAppear {
            s.syncAccountsIfNeeded(from: vm.accounts)
        }
        .onChange(of: vm.accounts) { _, updated in
            s.syncAccountsIfNeeded(from: updated)
        }
    }
}

// MARK: - Tab 1: 邮箱与连接

private struct AccountsSettingsTabView: View {
    @Environment(\.palette) private var p
    let vm: DeckViewModel

    private var s: SettingsShellState { vm.settings }

    private var isFDAReady: Bool {
        if case .ready = vm.accessStatus { return true }
        return false
    }

    private var lockedPrimaryAddresses: [String] {
        let live = vm.accounts.map(\.address).filter { !$0.isEmpty }
        if !live.isEmpty { return live }
        return s.accountItems.map(\.address).filter { !$0.isEmpty }
    }

    var body: some View {
        @Bindable var bindable = s

        VStack(alignment: .leading, spacing: 24) {
            SettingsSectionBlock(title: "连接与权限") {
                SunkenCardGroup {
                    SettingsRowView(title: "数据源") {
                        MonochromeSegmentedControl(
                            options: [
                                ("appleMail", "Apple Mail"),
                                ("demo", "演示数据")
                            ],
                            selection: vm.sourceMode.rawValue
                        ) { picked in
                            if picked == "appleMail" {
                                vm.recheckAccessAndSwitchToAppleMail()
                            } else {
                                vm.switchToDemoMode()
                            }
                        }
                    }

                    SunkenRowDivider()

                    SettingsRowView(
                        title: "完全磁盘访问",
                        subtitle: isFDAReady ? nil : "尚未授权读取 ~/Library/Mail"
                    ) {
                        HStack(spacing: 10) {
                            HStack(spacing: 5.5) {
                                Circle()
                                    .fill(isFDAReady ? p.sage : p.amber)
                                    .frame(width: 5.5, height: 5.5)
                                Text(isFDAReady ? "已就绪" : "待授权")
                                    .font(.system(size: 12))
                                    .foregroundStyle(p.ink3)
                            }

                            if !isFDAReady {
                                QuietActionButton(title: "系统设置") {
                                    MailStoreEnvironment.openFullDiskAccessSettings()
                                }
                            }

                            QuietActionButton(title: isFDAReady ? "重新检测" : "重连", prominent: !isFDAReady) {
                                vm.recheckAccessAndSwitchToAppleMail()
                            }
                        }
                    }

                    SunkenRowDivider()

                    SettingsRowView(title: "自动化控制「邮件」") {
                        HStack(spacing: 10) {
                            HStack(spacing: 5.5) {
                                Circle()
                                    .fill(p.sage)
                                    .frame(width: 5.5, height: 5.5)
                                Text("已授权")
                                    .font(.system(size: 12))
                                    .foregroundStyle(p.ink3)
                            }

                            QuietActionButton(title: s.automationVerifyStatus ?? "验证") {
                                s.triggerAutomationPreview()
                            }
                        }
                    }

                    SunkenRowDivider()

                    SettingsRowView(title: "单次同步上限") {
                        MonochromeSegmentedControl(
                            options: [
                                (50, "50"),
                                (100, "100"),
                                (200, "200"),
                                (500, "500")
                            ],
                            selection: s.syncLimit
                        ) { limit in
                            s.syncLimit = limit
                        }
                    }
                }
            }

            SettingsSectionBlock(title: "邮箱账户") {
                SunkenCardGroup {
                    ForEach(Array(s.accountItems.enumerated()), id: \.element.id) { idx, item in
                        if idx > 0 {
                            SunkenRowDivider()
                        }
                        AccountShellRowView(item: $bindable.accountItems[idx])
                    }
                }
            }

            SettingsSectionBlock(
                title: "本人发件别名",
                footnote: "包含本人地址参与回复的线程受保护，不会自动移入废纸篓。"
            ) {
                SunkenCardGroup {
                    TagChipsEditorView(
                        lockedChips: lockedPrimaryAddresses,
                        customChips: s.customAliases,
                        draft: $bindable.aliasDraft,
                        placeholder: "添加别名后回车…",
                        onSubmit: { s.submitAliasDraft() },
                        onRemove: { idx in s.removeAlias(at: idx) }
                    )
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                }
            }
        }
    }
}

private struct AccountShellRowView: View {
    @Environment(\.palette) private var p
    @Binding var item: SettingsAccountShellItem

    var body: some View {
        HStack(spacing: 10) {
            MonochromeToggle(isOn: $item.enabled)

            Button {
                item.tone = item.tone.next
            } label: {
                Circle()
                    .fill(item.tone.color(in: p))
                    .frame(width: 7, height: 7)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("点击切换圆点色")

            TextField("名称", text: $item.label)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(p.ink)
                .padding(.horizontal, 6)
                .frame(width: 70, height: 24)
                .background(p.paper.opacity(0.7), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(p.line, lineWidth: 1)
                )

            Text(item.address)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(p.ink3)
                .lineLimit(1)

            Spacer(minLength: 8)

            Text("\(item.archivePath) · \(item.trashPath)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(p.ink3)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .opacity(item.enabled ? 1.0 : 0.48)
    }
}

// MARK: - Tab 2: 分拣与护栏

private struct TriageSettingsTabView: View {
    let vm: DeckViewModel

    private var s: SettingsShellState { vm.settings }

    var body: some View {
        @Bindable var bindable = s

        VStack(alignment: .leading, spacing: 24) {
            SettingsSectionBlock(title: "自动分拣去向") {
                SunkenCardGroup {
                    ForEach(Array(s.triageMatrix.enumerated()), id: \.element.id) { idx, row in
                        if idx > 0 {
                            SunkenRowDivider()
                        }
                        SettingsRowView(title: row.title) {
                            MonochromeSegmentedControl(
                                options: TriageDispositionChoice.allCases.map { ($0, $0.label) },
                                selection: row.choice
                            ) { picked in
                                s.triageMatrix[idx].choice = picked
                            }
                        }
                    }
                }
            }

            SettingsSectionBlock(
                title: "护栏与白名单",
                footnote: "星标邮件、本人参与的对话线程，以及合同签署与账单异常始终留在待处理。"
            ) {
                SunkenCardGroup {
                    SettingsRowView(title: "残缺或纯图片邮件留待人工核实") {
                        MonochromeToggle(isOn: $bindable.reviewIncompleteMails)
                    }

                    SunkenRowDivider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("受保护域名与发件人")
                            .font(.system(size: 13))
                            .foregroundStyle(vm.palette.ink)

                        TagChipsEditorView(
                            lockedChips: [".edu", ".edu.cn", ".gov"],
                            customChips: s.customProtectedEntries,
                            draft: $bindable.protectedDraft,
                            placeholder: "添加域名或邮箱后回车…",
                            onSubmit: { s.submitProtectedDraft() },
                            onRemove: { idx in s.removeProtectedEntry(at: idx) }
                        )
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                }
            }
        }
    }
}

// MARK: - Tab 3: AI 分类引擎

private struct AIClassifierSettingsTabView: View {
    @Environment(\.palette) private var p
    let vm: DeckViewModel

    private var s: SettingsShellState { vm.settings }

    var body: some View {
        @Bindable var bindable = s

        VStack(alignment: .leading, spacing: 24) {
            SettingsSectionBlock(title: "引擎模式") {
                HStack(spacing: 8) {
                    ForEach(ClassifierEngineChoice.allCases) { mode in
                        EngineModeCardView(
                            mode: mode,
                            selected: s.engineMode == mode
                        ) {
                            withAnimation(.snappy(duration: 0.16)) {
                                s.selectEngine(mode)
                            }
                        }
                    }
                }
            }

            if s.engineMode != .rules {
                SettingsSectionBlock(title: "模型连接") {
                    SunkenCardGroup {
                        if s.engineMode == .hybrid {
                            SettingsRowView(title: "服务商") {
                                MonochromeSegmentedControl(
                                    options: LLMProviderChoice.allCases.map { ($0, $0.label) },
                                    selection: s.provider
                                ) { picked in
                                    s.selectProvider(picked)
                                }
                            }

                            SunkenRowDivider()
                        }

                        SettingsRowView(title: "Endpoint") {
                            SettingsMonospaceInput(
                                text: $bindable.endpoint,
                                placeholder: "https://...",
                                width: 288
                            )
                        }

                        if s.engineMode == .hybrid {
                            SunkenRowDivider()

                            SettingsRowView(title: "API Key", badge: "钥匙串") {
                                HStack(spacing: 6) {
                                    SettingsSecretInput(
                                        text: $bindable.apiKey,
                                        revealed: s.apiKeyRevealed,
                                        placeholder: "输入密钥…",
                                        width: 224
                                    )
                                    QuietActionButton(title: s.apiKeyRevealed ? "隐藏" : "显示") {
                                        s.apiKeyRevealed.toggle()
                                    }
                                }
                            }
                        }

                        SunkenRowDivider()

                        SettingsRowView(title: "模型") {
                            HStack(spacing: 6) {
                                SettingsMonospaceInput(
                                    text: $bindable.modelName,
                                    placeholder: "model-id",
                                    width: 204
                                )
                                QuietActionButton(title: s.connectionTestStatus ?? "测试连接") {
                                    s.triggerConnectionPreview()
                                }
                            }
                        }
                    }
                }
            }

            SettingsSectionBlock(title: "判别门限与数据范围") {
                SunkenCardGroup {
                    SettingsRowView(
                        title: "自动分拣确信度门限",
                        subtitle: "低于门限的邮件留在待处理并以虚线标出"
                    ) {
                        HStack(spacing: 10) {
                            Text("\(Int(s.confidenceThreshold.rounded()))%")
                                .font(.system(size: 12.5, design: .monospaced))
                                .monospacedDigit()
                                .foregroundStyle(p.ink)
                                .frame(width: 36, alignment: .trailing)

                            Slider(value: $bindable.confidenceThreshold, in: 80...98, step: 1)
                                .tint(p.ink)
                                .frame(width: 146)
                        }
                    }

                    if s.engineMode != .rules {
                        SunkenRowDivider()

                        SettingsRowView(title: "送审内容范围") {
                            MonochromeSegmentedControl(
                                options: PayloadScopeChoice.allCases.map { ($0, $0.label) },
                                selection: s.payloadScope
                            ) { picked in
                                s.payloadScope = picked
                            }
                        }

                        SunkenRowDivider()

                        SettingsRowView(title: "本地缓存判别结果") {
                            MonochromeToggle(isOn: $bindable.cacheDecisions)
                        }
                    }
                }
            }
        }
    }
}

private struct EngineModeCardView: View {
    @Environment(\.palette) private var p
    let mode: ClassifierEngineChoice
    let selected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(mode.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(p.ink)
                    Spacer(minLength: 0)
                    if let badge = mode.badgeText {
                        QuietTagView(text: badge)
                    }
                }

                Text(mode.subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(p.ink3)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? p.paper : p.sunken)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        selected ? p.ink.opacity(p.mode == .dark ? 0.42 : 0.48) : p.line,
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Tab 4: 阅读与外观

private struct AppearanceSettingsTabView: View {
    let vm: DeckViewModel

    private var s: SettingsShellState { vm.settings }

    var body: some View {
        @Bindable var bindableVM = vm

        VStack(alignment: .leading, spacing: 24) {
            SettingsSectionBlock(title: "主题") {
                HStack(spacing: 10) {
                    ThemePreviewCardView(
                        preference: .system,
                        title: "跟随系统",
                        selected: vm.themePreference == .system
                    ) {
                        vm.setThemePreference(.system)
                    }

                    ThemePreviewCardView(
                        preference: .light,
                        title: "浅色",
                        selected: vm.themePreference == .light
                    ) {
                        vm.setThemePreference(.light)
                    }

                    ThemePreviewCardView(
                        preference: .dark,
                        title: "深色",
                        selected: vm.themePreference == .dark
                    ) {
                        vm.setThemePreference(.dark)
                    }
                }
            }

            SettingsSectionBlock(title: "阅读与界面") {
                SunkenCardGroup {
                    SettingsRowView(title: "默认正文格式") {
                        MonochromeSegmentedControl(
                            options: [
                                (false, "富文本"),
                                (true, "纯文本")
                            ],
                            selection: vm.preferPlainText
                        ) { plain in
                            vm.preferPlainText = plain
                        }
                    }

                    SunkenRowDivider()

                    SettingsRowView(title: "远程图片") {
                        MonochromeSegmentedControl(
                            options: RemoteImageChoice.allCases.map { ($0, $0.label) },
                            selection: s.remoteImageChoice
                        ) { picked in
                            s.remoteImageChoice = picked
                        }
                    }

                    SunkenRowDivider()

                    SettingsRowView(title: "底部快捷键提示条") {
                        MonochromeToggle(isOn: $bindableVM.showKeyboardHUD)
                    }

                    SunkenRowDivider()

                    SettingsRowView(title: "默认展开 AI 判据条") {
                        MonochromeToggle(isOn: $bindableVM.aiReasoningExpanded)
                    }
                }
            }
        }
    }
}

private struct ThemePreviewCardView: View {
    @Environment(\.palette) private var p
    let preference: ThemePreference
    let title: String
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                miniatureCanvas
                    .frame(height: 58)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.gray.opacity(0.16), lineWidth: 1)
                    )

                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(p.ink)
                    .padding(.horizontal, 2)
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(selected ? p.paper : p.sunken)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        selected ? p.ink.opacity(p.mode == .dark ? 0.42 : 0.48) : p.line,
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var miniatureCanvas: some View {
        switch preference {
        case .system:
            HStack(spacing: 0) {
                miniHalf(canvas: Color(hex: 0xFAFBFD), paper: .white, bar: Color(hex: 0x0F1117), active: Color.black.opacity(0.07))
                miniHalf(canvas: Color(hex: 0x101114), paper: Color(hex: 0x16171B), bar: Color(hex: 0xECEDEF), active: Color.white.opacity(0.11))
            }
        case .light:
            miniFull(canvas: Color(hex: 0xFAFBFD), paper: .white, ink: Color(hex: 0x0F1117), active: Color.black.opacity(0.07))
        case .dark:
            miniFull(canvas: Color(hex: 0x101114), paper: Color(hex: 0x16171B), ink: Color(hex: 0xECEDEF), active: Color.white.opacity(0.11))
        }
    }

    private func miniHalf(canvas: Color, paper: Color, bar: Color, active: Color) -> some View {
        ZStack {
            canvas
            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                .fill(paper)
                .overlay(
                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(active)
                            .frame(height: 10)
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(bar.opacity(0.18))
                            .frame(width: 34, height: 3.5)
                        Spacer(minLength: 0)
                    }
                    .padding(5)
                )
                .padding(5)
        }
    }

    private func miniFull(canvas: Color, paper: Color, ink: Color, active: Color) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                RoundedRectangle(cornerRadius: 1.5).fill(ink.opacity(0.2)).frame(width: 24, height: 3.5)
                RoundedRectangle(cornerRadius: 1.5).fill(ink.opacity(0.2)).frame(width: 32, height: 3.5)
                Spacer(minLength: 0)
            }
            .padding(7)
            .frame(width: 44, alignment: .leading)

            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(paper)
                .overlay(
                    VStack(alignment: .leading, spacing: 5) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(active)
                            .frame(height: 10)
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(ink.opacity(0.18))
                            .frame(width: 68, height: 3.5)
                        Spacer(minLength: 0)
                    }
                    .padding(7)
                )
                .padding(.vertical, 4)
                .padding(.trailing, 4)
        }
        .background(canvas)
    }
}

// MARK: - Tab 5: 快捷键与诊断

private struct DiagnosticsSettingsTabView: View {
    @Environment(\.palette) private var p
    let vm: DeckViewModel

    private var s: SettingsShellState { vm.settings }

    private let leftShortcuts: [(String, [String])] = [
        ("上下移动焦点", ["J", "K"]),
        ("阅毕归档", ["Space"]),
        ("重要保留", ["⇧K"]),
        ("移入废纸篓", ["⌫"]),
        ("拉回待处理", ["R"]),
        ("撤销", ["Z"])
    ]

    private let rightShortcuts: [(String, [String])] = [
        ("切换分拣夹", ["1", "2", "3"]),
        ("在 Apple Mail 打开", ["↵"]),
        ("展开 / 收起判据", ["I"]),
        ("收起 / 展开侧栏", ["["]),
        ("搜索与命令", ["⌘K"]),
        ("打开 / 关闭设置", ["⌘,"])
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsSectionBlock(title: "快捷键") {
                HStack(alignment: .top, spacing: 10) {
                    shortcutColumn(items: leftShortcuts)
                    shortcutColumn(items: rightShortcuts)
                }
            }

            SettingsSectionBlock(title: "诊断与缓存") {
                VStack(spacing: 10) {
                    // 四宫格只读健康概览（同源 InboxZeroView 统计卡）
                    HStack(spacing: 0) {
                        diagnosticMetricCell(value: s.walStatusText, label: "Envelope Index", showReadyDot: true)
                        verticalCellDivider
                        diagnosticMetricCell(value: s.hitRateText, label: ".emlx 命中率", showReadyDot: false)
                        verticalCellDivider
                        diagnosticMetricCell(value: s.pendingLedgerText, label: "待结算变更", showReadyDot: false)
                        verticalCellDivider
                        diagnosticMetricCell(value: s.cacheSizeText, label: "本地缓存", showReadyDot: false)
                    }
                    .background(p.sunken, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(p.line, lineWidth: 1)
                    )

                    SunkenCardGroup {
                        SettingsRowView(title: "连接诊断") {
                            HStack(spacing: 6) {
                                QuietActionButton(title: "重新自检") {
                                    s.showTransientFeedback("自检预览完成")
                                }
                                QuietActionButton(title: "复制报告") {
                                    s.showTransientFeedback("复制报告将在接入诊断逻辑后启用")
                                }
                            }
                        }

                        SunkenRowDivider()

                        SettingsRowView(title: "本地解析缓存") {
                            if s.confirmingCacheRebuild {
                                HStack(spacing: 6) {
                                    QuietActionButton(title: "取消") {
                                        s.confirmingCacheRebuild = false
                                    }
                                    QuietActionButton(title: "确认重建", destructiveText: true) {
                                        s.confirmCacheRebuildPreview()
                                    }
                                }
                            } else {
                                QuietActionButton(title: "重建缓存…") {
                                    s.confirmingCacheRebuild = true
                                }
                            }
                        }

                        SunkenRowDivider()

                        SettingsRowView(title: "离线评测样本") {
                            QuietActionButton(title: "导出 JSON…") {
                                s.showTransientFeedback("导出评测样本将在接入后端逻辑后启用")
                            }
                        }
                    }
                }
            }
        }
    }

    private var verticalCellDivider: some View {
        Rectangle().fill(p.line).frame(width: 1)
    }

    private func diagnosticMetricCell(value: String, label: String, showReadyDot: Bool) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 5) {
                if showReadyDot {
                    Circle()
                        .fill(p.sage)
                        .frame(width: 5.5, height: 5.5)
                }
                Text(value)
                    .font(.system(size: 14.5, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(p.ink)
            }
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(p.ink3)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private func shortcutColumn(items: [(String, [String])]) -> some View {
        SunkenCardGroup {
            ForEach(Array(items.enumerated()), id: \.offset) { idx, pair in
                if idx > 0 {
                    SunkenRowDivider()
                }
                HStack {
                    Text(pair.0)
                        .font(.system(size: 12.5))
                        .foregroundStyle(p.ink2)
                    Spacer()
                    HStack(spacing: 4) {
                        ForEach(pair.1, id: \.self) { key in
                            KbdView(text: key)
                        }
                    }
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 8.5)
            }
        }
    }
}

// MARK: - 通用单色沉降卡片与基础控件

private struct SettingsSectionBlock<Content: View>: View {
    @Environment(\.palette) private var p
    let title: String
    var footnote: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(p.ink3)
                .padding(.horizontal, 2)

            content

            if let footnote {
                Text(footnote)
                    .font(.system(size: 11.5))
                    .foregroundStyle(p.ink3)
                    .padding(.horizontal, 2)
                    .padding(.top, 1)
            }
        }
    }
}

private struct SunkenCardGroup<Content: View>: View {
    @Environment(\.palette) private var p
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(p.sunken, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(p.line, lineWidth: 1)
        )
    }
}

private struct SunkenRowDivider: View {
    @Environment(\.palette) private var p

    var body: some View {
        Rectangle()
            .fill(p.line)
            .frame(height: 1)
    }
}

private struct SettingsRowView<Trailing: View>: View {
    @Environment(\.palette) private var p
    let title: String
    var badge: String? = nil
    var subtitle: String? = nil
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2.5) {
                HStack(spacing: 7) {
                    Text(title)
                        .font(.system(size: 13))
                        .foregroundStyle(p.ink)
                    if let badge {
                        QuietTagView(text: badge)
                    }
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(p.ink3)
                }
            }

            Spacer(minLength: 8)

            trailing
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .padding(.vertical, subtitle == nil ? 0 : 6)
    }
}

private struct QuietTagView: View {
    @Environment(\.palette) private var p
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10.5))
            .foregroundStyle(p.ink3)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(p.ink.opacity(0.055), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

private struct QuietActionButton: View {
    @Environment(\.palette) private var p
    let title: String
    var prominent: Bool = false
    var destructiveText: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: prominent ? .medium : .regular))
                .foregroundStyle(foregroundColor)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(
                    prominent ? p.ink : p.paper,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(prominent ? p.ink : p.lineStrong, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var foregroundColor: Color {
        if prominent { return p.canvas }
        if destructiveText { return p.coral }
        return p.ink2
    }
}

private struct MonochromeToggle: View {
    @Environment(\.palette) private var p
    @Binding var isOn: Bool

    private var trackColor: Color {
        if isOn {
            return p.mode == .dark ? Color(hex: 0xE2E4E9) : Color(hex: 0x1B1E26)
        }
        return p.ink.opacity(0.15)
    }

    private var knobColor: Color {
        if isOn && p.mode == .dark {
            return Color(hex: 0x141519)
        }
        return .white
    }

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.16)) {
                isOn.toggle()
            }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule(style: .continuous)
                    .fill(trackColor)
                    .frame(width: 32, height: 18)

                Circle()
                    .fill(knobColor)
                    .frame(width: 14, height: 14)
                    .shadow(color: .black.opacity(0.16), radius: 1, y: 0.5)
                    .padding(.horizontal, 2)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct MonochromeSegmentedControl<Value: Hashable>: View {
    @Environment(\.palette) private var p
    let options: [(Value, String)]
    let selection: Value
    let onSelect: (Value) -> Void

    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, pair in
                let active = (pair.0 == selection)
                Button {
                    withAnimation(.snappy(duration: 0.14)) {
                        onSelect(pair.0)
                    }
                } label: {
                    Text(pair.1)
                        .font(.system(size: 11.5, weight: active ? .medium : .regular))
                        .foregroundStyle(active ? p.ink : p.ink3)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background {
                            if active {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(p.mode == .dark ? Color.white.opacity(0.11) : p.paper)
                                    .shadow(color: .black.opacity(p.mode == .dark ? 0.25 : 0.07), radius: 1.5, y: 0.5)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(p.ink.opacity(0.055), in: RoundedRectangle(cornerRadius: 6.5, style: .continuous))
    }
}

private struct SettingsMonospaceInput: View {
    @Environment(\.palette) private var p
    @Binding var text: String
    let placeholder: String
    let width: CGFloat

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 11.5, design: .monospaced))
            .foregroundStyle(p.ink)
            .padding(.horizontal, 9)
            .frame(width: width, height: 27)
            .background(p.paper, in: RoundedRectangle(cornerRadius: 5.5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                    .strokeBorder(p.lineStrong, lineWidth: 1)
            )
    }
}

private struct SettingsSecretInput: View {
    @Environment(\.palette) private var p
    @Binding var text: String
    let revealed: Bool
    let placeholder: String
    let width: CGFloat

    var body: some View {
        Group {
            if revealed {
                TextField(placeholder, text: $text)
            } else {
                SecureField(placeholder, text: $text)
            }
        }
        .textFieldStyle(.plain)
        .font(.system(size: 11.5, design: .monospaced))
        .foregroundStyle(p.ink)
        .padding(.horizontal, 9)
        .frame(width: width, height: 27)
        .background(p.paper, in: RoundedRectangle(cornerRadius: 5.5, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                .strokeBorder(p.lineStrong, lineWidth: 1)
        )
    }
}

private struct TagChipsEditorView: View {
    @Environment(\.palette) private var p
    let lockedChips: [String]
    let customChips: [String]
    @Binding var draft: String
    let placeholder: String
    let onSubmit: () -> Void
    let onRemove: (Int) -> Void

    var body: some View {
        FlowWrapLayout(horizontalSpacing: 6, verticalSpacing: 6) {
            ForEach(lockedChips, id: \.self) { chip in
                Text(chip)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(p.ink3)
                    .padding(.horizontal, 7.5)
                    .frame(height: 22)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                            .strokeBorder(p.line, lineWidth: 1)
                    )
            }

            ForEach(Array(customChips.enumerated()), id: \.offset) { idx, chip in
                HStack(spacing: 4) {
                    Text(chip)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(p.ink2)

                    Button {
                        onRemove(idx)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundStyle(p.ink3)
                            .frame(width: 12, height: 12)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 7.5)
                .padding(.trailing, 5)
                .frame(height: 22)
                .background(p.paper, in: RoundedRectangle(cornerRadius: 4.5, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                        .strokeBorder(p.lineStrong, lineWidth: 1)
                )
            }

            TextField(placeholder, text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(p.ink)
                .frame(minWidth: 150)
                .frame(height: 22)
                .onSubmit {
                    onSubmit()
                }
        }
    }
}

private struct FlowWrapLayout: Layout {
    var horizontalSpacing: CGFloat = 6
    var verticalSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > 0 && currentX + size.width > maxWidth {
                currentX = 0
                currentY += lineHeight + verticalSpacing
                lineHeight = 0
            }
            usedWidth = max(usedWidth, min(maxWidth, currentX + size.width))
            currentX += size.width + horizontalSpacing
            lineHeight = max(lineHeight, size.height)
        }

        return CGSize(width: proposal.width ?? usedWidth, height: currentY + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX > bounds.minX && currentX + size.width > bounds.maxX {
                currentX = bounds.minX
                currentY += lineHeight + verticalSpacing
                lineHeight = 0
            }
            let remaining = max(80, bounds.maxX - currentX)
            let itemWidth = min(size.width, remaining)
            subview.place(
                at: CGPoint(x: currentX, y: currentY),
                proposal: ProposedViewSize(width: itemWidth, height: size.height)
            )
            currentX += itemWidth + horizontalSpacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

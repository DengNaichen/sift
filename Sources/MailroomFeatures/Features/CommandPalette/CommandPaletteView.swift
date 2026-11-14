import SwiftUI
import MailroomCore

struct CommandPaletteView: View {
    @Environment(\.palette) private var p
    let commands: [PaletteCommand]
    let onClose: () -> Void
    let onRun: (DeckCommand) -> Void

    @State private var model = CommandPaletteViewModel()
    @FocusState private var inputFocused: Bool

    private var filtered: [PaletteCommand] { model.filtered(commands) }
    private var activeIndex: Int { model.activeIndex }

    var body: some View {
        ZStack(alignment: .top) {
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.32)
                Color.black.opacity(p.mode == .dark ? 0.36 : 0.13)
            }
            .ignoresSafeArea()
            .onTapGesture {
                onClose()
            }

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(p.ink3)

                    TextField("搜索邮件或输入命令…", text: $model.query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14.5))
                        .foregroundStyle(p.ink)
                        .focused($inputFocused)
                        .onSubmit {
                            executeActive()
                        }

                    KbdView(text: "esc")
                }
                .padding(.horizontal, 16)
                .frame(height: 50)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(p.lineStrong).frame(height: 1)
                }

                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            if filtered.isEmpty {
                                Text("没有匹配「\(model.query)」的邮件或命令")
                                    .font(.system(size: 13))
                                    .foregroundStyle(p.ink3)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 36)
                            } else {
                                let filtered = self.filtered
                                ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, cmd in
                                    let showGroup = CommandPaletteViewModel.showsGroupHeader(at: idx, in: filtered)
                                    if showGroup {
                                        Text(cmd.group)
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundStyle(p.ink3)
                                            .padding(.horizontal, 10)
                                            .padding(.top, 9)
                                            .padding(.bottom, 3)
                                    }

                                    Button {
                                        onClose()
                                        onRun(cmd.command)
                                    } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: cmd.systemImage)
                                                .font(.system(size: 13))
                                                .foregroundStyle(idx == activeIndex ? p.ink : p.ink3)
                                                .frame(width: 16)

                                            HStack(spacing: 6) {
                                                Text(cmd.title)
                                                    .font(.system(size: 13.5, weight: idx == activeIndex ? .medium : .regular))
                                                    .foregroundStyle(idx == activeIndex ? p.ink : p.ink2)
                                                    .lineLimit(1)
                                                if let sub = cmd.subtitle {
                                                    Text(sub)
                                                        .font(.system(size: 12))
                                                        .foregroundStyle(p.ink3)
                                                        .lineLimit(1)
                                                }
                                            }
                                            Spacer(minLength: 6)

                                            if let kbd = cmd.kbd {
                                                KbdView(text: kbd)
                                            } else if idx == activeIndex {
                                                Image(systemName: "return")
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(p.ink3)
                                            }
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 7)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .fill(idx == activeIndex ? p.sunken : Color.clear)
                                        )
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .id(cmd.id)
                                }
                            }
                        }
                        .padding(6)
                        .borderlessScroller()
                    }
                    .frame(maxHeight: 360)
                    .onChange(of: activeIndex) { _, newIdx in
                        if newIdx >= 0 && newIdx < filtered.count {
                            proxy.scrollTo(filtered[newIdx].id, anchor: nil)
                        }
                    }
                }
            }
            .frame(width: 600)
            .background(p.raised, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(
                        p.mode == .dark ? Color.white.opacity(0.11) : Color.black.opacity(0.08),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(p.mode == .dark ? 0.52 : 0.16), radius: 32, y: 14)
            .shadow(color: .black.opacity(p.mode == .dark ? 0.26 : 0.05), radius: 4, y: 1)
            .padding(.top, 92)
            .onKeyPress(.downArrow) {
                model.moveDown(count: filtered.count)
                return .handled
            }
            .onKeyPress(.upArrow) {
                model.moveUp()
                return .handled
            }
            .onKeyPress(.escape) {
                onClose()
                return .handled
            }
        }
        .onAppear {
            inputFocused = true
        }
    }

    private func executeActive() {
        guard let cmd = model.activeCommand(in: filtered) else { return }
        onClose()
        onRun(cmd.command)
    }
}

import SwiftUI
import MailroomCore

struct KeyboardHUDView: View {
    @Environment(\.palette) private var p
    let items: [HudItem]
    let onPerform: (DeckCommand) -> Void

    private var navAndCoreItems: [HudItem] {
        let filtered = items.filter { $0.priority >= .navigation }
        return filtered.isEmpty ? items : filtered
    }

    private var coreOnlyItems: [HudItem] {
        let filtered = items.filter { $0.priority == .core }
        return filtered.isEmpty ? navAndCoreItems : filtered
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            hudRow(for: items, showKeys: true)
            hudRow(for: navAndCoreItems, showKeys: true)
            hudRow(for: coreOnlyItems, showKeys: true)
            hudRow(for: coreOnlyItems, showKeys: false)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4.5)
        .deckGlassCapsule(interactive: true)
    }

    private func hudRow(for subset: [HudItem], showKeys: Bool) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(subset.enumerated()), id: \.element.id) { idx, item in
                if idx > 0 {
                    Rectangle()
                        .fill(p.ink.opacity(p.mode == .dark ? 0.13 : 0.09))
                        .frame(width: 1, height: 12)
                        .padding(.horizontal, 2)
                }
                HudPillButton(item: item, showKeys: showKeys, onPerform: onPerform)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct HudPillButton: View {
    @Environment(\.palette) private var p
    let item: HudItem
    var showKeys: Bool = true
    let onPerform: (DeckCommand) -> Void
    @State private var hovered = false

    var body: some View {
        Button {
            onPerform(item.command)
        } label: {
            HStack(spacing: 5) {
                if showKeys {
                    HStack(spacing: 2) {
                        ForEach(item.keys, id: \.self) { k in
                            KbdView(text: k)
                        }
                    }
                }
                Text(item.label)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .foregroundStyle(hovered && !item.disabled ? p.ink : p.ink.opacity(0.86))
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 7.5)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(hovered && !item.disabled ? p.ink.opacity(p.mode == .dark ? 0.12 : 0.065) : .clear)
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
                    .truncationMode(.tail)

                Spacer(minLength: 4)

                Button(action: onUndo) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(p.ink2)
                        Text("撤销")
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                            .foregroundStyle(p.ink)
                        KbdView(text: "Z")
                    }
                    .fixedSize(horizontal: true, vertical: false)
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
                    .lineLimit(1)
                    .foregroundStyle(p.ink)
                Spacer(minLength: 0)
            }
        }
        .padding(.leading, 15)
        .padding(.trailing, 7)
        .padding(.vertical, 6)
        .frame(maxWidth: 356)
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

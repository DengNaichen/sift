import SwiftUI
import MailroomCore

struct KeyboardHUDView: View {
    @Environment(\.palette) private var p
    let items: [HudItem]
    let onPerform: (DeckCommand) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                if idx > 0 {
                    Rectangle()
                        .fill(p.ink.opacity(0.09))
                        .frame(width: 1, height: 12)
                        .padding(.horizontal, 2)
                }
                HudPillButton(item: item, onPerform: onPerform)
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
    let onPerform: (DeckCommand) -> Void
    @State private var hovered = false

    var body: some View {
        Button {
            onPerform(item.command)
        } label: {
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

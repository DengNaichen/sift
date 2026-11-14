import AppKit
import SwiftUI
import MailroomCore

// MARK: - 通用单色沉降卡片与基础控件

struct SettingsSectionBlock<Content: View>: View {
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

struct SunkenCardGroup<Content: View>: View {
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

struct SunkenRowDivider: View {
    @Environment(\.palette) private var p

    var body: some View {
        Rectangle()
            .fill(p.line)
            .frame(height: 1)
    }
}

struct SettingsRowView<Trailing: View>: View {
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

struct QuietTagView: View {
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

struct QuietActionButton: View {
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

struct MonochromeToggle: View {
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

struct MonochromeSegmentedControl<Value: Hashable>: View {
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

struct SettingsMonospaceInput: View {
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

struct SettingsSecretInput: View {
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

struct TagChipsEditorView: View {
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

struct FlowWrapLayout: Layout {
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

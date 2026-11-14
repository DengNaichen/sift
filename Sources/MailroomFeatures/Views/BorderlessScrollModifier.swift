import AppKit
import ObjectiveC
import SwiftUI

/// 消除外接鼠标或「始终显示滚动条」系统偏好下 NSScroller 的 17pt 白色槽底与左右边框线，
/// 统一锁定为无框悬浮式（Overlay）滚动条。
final class BorderlessOverlayScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }

    override var scrollerStyle: NSScroller.Style {
        get { .overlay }
        set { super.scrollerStyle = .overlay }
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        // 不绘制传统滚动条外框与轨道底色，仅保留圆角滑块本身
    }
}

private struct BorderlessScrollIntrospector: NSViewRepresentable {
    func makeNSView(context: Context) -> ScrollObserverView {
        ScrollObserverView()
    }

    func updateNSView(_ nsView: ScrollObserverView, context: Context) {
        nsView.applyOverlayScrollerIfNeeded()
    }
}

final class ScrollObserverView: NSView {
    private nonisolated(unsafe) static var kvoAssociationKey: UInt8 = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScrollerStyleChange),
            name: NSScroller.preferredScrollerStyleDidChangeNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func handleScrollerStyleChange() {
        DispatchQueue.main.async { [weak self] in
            self?.applyOverlayScrollerIfNeeded()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyOverlayScrollerIfNeeded()
        DispatchQueue.main.async { [weak self] in
            self?.applyOverlayScrollerIfNeeded()
        }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        applyOverlayScrollerIfNeeded()
    }

    override func layout() {
        super.layout()
        applyOverlayScrollerIfNeeded()
    }

    func applyOverlayScrollerIfNeeded() {
        guard let scrollView = enclosingScrollView else { return }
        Self.configure(scrollView: scrollView)
    }

    static func configure(scrollView: NSScrollView) {
        var needsRetile = false

        if scrollView.hasVerticalScroller, !(scrollView.verticalScroller is BorderlessOverlayScroller) {
            let scroller = BorderlessOverlayScroller()
            scroller.controlSize = scrollView.verticalScroller?.controlSize ?? .regular
            scrollView.verticalScroller = scroller
            needsRetile = true
        }

        if scrollView.hasHorizontalScroller, !(scrollView.horizontalScroller is BorderlessOverlayScroller) {
            let scroller = BorderlessOverlayScroller()
            scroller.controlSize = scrollView.horizontalScroller?.controlSize ?? .regular
            scrollView.horizontalScroller = scroller
            needsRetile = true
        }

        if objc_getAssociatedObject(scrollView, &kvoAssociationKey) == nil {
            let observation = scrollView.observe(\.scrollerStyle, options: [.new]) { sv, _ in
                guard Thread.isMainThread else { return }
                MainActor.assumeIsolated {
                    if sv.scrollerStyle != .overlay {
                        sv.scrollerStyle = .overlay
                        sv.tile()
                    }
                }
            }
            objc_setAssociatedObject(
                scrollView,
                &kvoAssociationKey,
                observation,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }

        if scrollView.scrollerStyle != .overlay {
            scrollView.scrollerStyle = .overlay
            needsRetile = true
        }

        if scrollView.borderType != .noBorder {
            scrollView.borderType = .noBorder
            needsRetile = true
        }

        if scrollView.drawsBackground {
            scrollView.drawsBackground = false
            needsRetile = true
        }

        if needsRetile {
            scrollView.tile()
        }
    }
}

extension View {
    /// 将所在 SwiftUI `ScrollView` 底层的 `NSScrollView` 锁定为无框悬浮滚动条（不占宽度、无轨道边框）。
    func borderlessScroller() -> some View {
        background(
            BorderlessScrollIntrospector()
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        )
    }
}

import AppKit
import SwiftUI
import WebKit
import MailroomCore

@MainActor
private final class RemoteResourceBlocker {
    static let shared = RemoteResourceBlocker()

    private var cachedRuleList: WKContentRuleList?
    private var waiters: [CheckedContinuation<WKContentRuleList?, Never>] = []
    private var isCompiling = false

    private static let rulesJSON = """
    [
      {
        "trigger": {
          "url-filter": "^https?://",
          "resource-type": ["image", "media", "style-sheet", "font", "raw", "svg-document"]
        },
        "action": {
          "type": "block"
        }
      }
    ]
    """

    func cachedIfReady() -> WKContentRuleList? {
        cachedRuleList
    }

    func ruleList() async -> WKContentRuleList? {
        if let cachedRuleList {
            return cachedRuleList
        }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
            guard !isCompiling else { return }
            isCompiling = true
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "dev.mailroom.block-remote-subresources-v1",
                encodedContentRuleList: Self.rulesJSON
            ) { [weak self] list, _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.cachedRuleList = list
                    self.isCompiling = false
                    let pending = self.waiters
                    self.waiters.removeAll()
                    for waiter in pending {
                        waiter.resume(returning: list)
                    }
                }
            }
        }
    }
}

final class PassthroughWKWebView: WKWebView {
    var onWidthChanged: (() -> Void)?
    private var lastObservedWidth: CGFloat = 0

    override func scrollWheel(with event: NSEvent) {
        nextResponder?.scrollWheel(with: event)
    }

    override func layout() {
        super.layout()
        let w = bounds.width
        if w > 0, abs(w - lastObservedWidth) > 1.0 {
            lastObservedWidth = w
            onWidthChanged?()
        }
    }
}

struct MailHTMLWebView: NSViewRepresentable {
    let messageId: MessageId
    let html: String
    let allowRemoteImages: Bool
    let themeMode: ThemeMode
    @Binding var dynamicHeight: CGFloat
    var onSurfaceModeResolved: ((ThemeMode) -> Void)? = nil

    static func predictedSurfaceMode(rawHTML: String, themeMode: ThemeMode) -> ThemeMode {
        if themeMode == .dark && Coordinator.usesHardcodedLightSurface(rawHTML) {
            return .light
        }
        return themeMode
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(dynamicHeight: $dynamicHeight, onSurfaceModeResolved: onSurfaceModeResolved)
    }

    func makeNSView(context: Context) -> PassthroughWKWebView {
        let config = WKWebViewConfiguration()
        let pagePrefs = WKWebpagePreferences()
        pagePrefs.allowsContentJavaScript = false
        config.defaultWebpagePreferences = pagePrefs
        config.suppressesIncrementalRendering = false

        let webView = PassthroughWKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        webView.allowsMagnification = false
        webView.allowsBackForwardNavigationGestures = false
        webView.appearance = NSAppearance(named: themeMode == .dark ? .darkAqua : .aqua)

        let coordinator = context.coordinator
        webView.onWidthChanged = { [weak webView, weak coordinator] in
            guard let webView, let coordinator else { return }
            coordinator.measureContentHeight(in: webView)
        }

        context.coordinator.loadIfNeeded(
            in: webView,
            messageId: messageId,
            rawHTML: html,
            allowRemoteImages: allowRemoteImages,
            themeMode: themeMode
        )
        return webView
    }

    func updateNSView(_ webView: PassthroughWKWebView, context: Context) {
        context.coordinator.dynamicHeight = $dynamicHeight
        context.coordinator.onSurfaceModeResolved = onSurfaceModeResolved
        webView.appearance = NSAppearance(named: themeMode == .dark ? .darkAqua : .aqua)
        context.coordinator.loadIfNeeded(
            in: webView,
            messageId: messageId,
            rawHTML: html,
            allowRemoteImages: allowRemoteImages,
            themeMode: themeMode
        )
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        var dynamicHeight: Binding<CGFloat>
        var onSurfaceModeResolved: ((ThemeMode) -> Void)?
        private var currentRenderKey: RenderKey?
        private var loadTask: Task<Void, Never>?
        private var remeasureTask: Task<Void, Never>?

        private struct RenderKey: Equatable {
            let messageId: MessageId
            let htmlHash: Int
            let allowRemoteImages: Bool
            let themeMode: ThemeMode
        }

        private static let measureHeightJS = """
        (function() {
          var body = document.body;
          var doc = document.documentElement;
          if (!body || !doc) return 120;
          var prevDocH = doc.style.height;
          var prevBodyH = body.style.height;
          doc.style.height = 'auto';
          body.style.height = 'auto';
          var bodyTop = body.getBoundingClientRect().top;
          var maxH = Math.ceil(body.getBoundingClientRect().height);
          var children = body.children;
          for (var i = 0; i < children.length; i++) {
            var r = children[i].getBoundingClientRect();
            var b = Math.ceil(r.bottom - bodyTop);
            if (b > maxH) maxH = b;
          }
          doc.style.height = prevDocH;
          body.style.height = prevBodyH;
          return Math.max(72, maxH + 8);
        })();
        """

        init(dynamicHeight: Binding<CGFloat>, onSurfaceModeResolved: ((ThemeMode) -> Void)?) {
            self.dynamicHeight = dynamicHeight
            self.onSurfaceModeResolved = onSurfaceModeResolved
        }

        deinit {
            loadTask?.cancel()
            remeasureTask?.cancel()
        }

        func loadIfNeeded(
            in webView: PassthroughWKWebView,
            messageId: MessageId,
            rawHTML: String,
            allowRemoteImages: Bool,
            themeMode: ThemeMode
        ) {
            let key = RenderKey(
                messageId: messageId,
                htmlHash: rawHTML.hashValue,
                allowRemoteImages: allowRemoteImages,
                themeMode: themeMode
            )
            guard key != currentRenderKey else { return }
            let messageChanged = (currentRenderKey?.messageId != messageId)
            currentRenderKey = key

            loadTask?.cancel()
            remeasureTask?.cancel()

            if messageChanged {
                dynamicHeight.wrappedValue = 180
            }

            let wrappedDocument = Self.wrapEmailDocument(rawHTML: rawHTML, themeMode: themeMode)

            if allowRemoteImages {
                webView.configuration.userContentController.removeAllContentRuleLists()
                webView.loadHTMLString(wrappedDocument, baseURL: URL(string: "about:blank"))
            } else if let readyList = RemoteResourceBlocker.shared.cachedIfReady() {
                webView.configuration.userContentController.removeAllContentRuleLists()
                webView.configuration.userContentController.add(readyList)
                webView.loadHTMLString(wrappedDocument, baseURL: URL(string: "about:blank"))
            } else {
                loadTask = Task { [weak self, weak webView] in
                    let compiled = await RemoteResourceBlocker.shared.ruleList()
                    guard !Task.isCancelled, let self, let webView, self.currentRenderKey == key else { return }
                    webView.configuration.userContentController.removeAllContentRuleLists()
                    if let compiled {
                        webView.configuration.userContentController.add(compiled)
                    }
                    webView.loadHTMLString(wrappedDocument, baseURL: URL(string: "about:blank"))
                }
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            let scheme = (url.scheme ?? "").lowercased()

            if navigationAction.navigationType == .linkActivated {
                if scheme == "http" || scheme == "https" || scheme == "mailto" {
                    NSWorkspace.shared.open(url)
                }
                decisionHandler(.cancel)
                return
            }

            if scheme == "about" || scheme == "data" {
                decisionHandler(.allow)
                return
            }

            // Block embedded remote iframes or automatic redirects inside email HTML
            decisionHandler(.cancel)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            measureContentHeight(in: webView)
            measureSurfaceLuminance(in: webView)

            let shouldRemeasureForImages = currentRenderKey?.allowRemoteImages ?? false
            remeasureTask?.cancel()
            remeasureTask = Task { [weak self, weak webView] in
                let delaysNs: [UInt64] = shouldRemeasureForImages
                    ? [80_000_000, 260_000_000, 650_000_000, 1_500_000_000]
                    : [60_000_000]
                for delay in delaysNs {
                    try? await Task.sleep(nanoseconds: delay)
                    guard !Task.isCancelled, let self, let webView else { return }
                    self.measureContentHeight(in: webView)
                }
            }
        }

        func measureSurfaceLuminance(in webView: WKWebView) {
            let isDarkTheme = (currentRenderKey?.themeMode == .dark)
            let baseRGB = isDarkTheme ? "[22, 23, 27]" : "[255, 255, 255]"
            let js = """
            (function() {
              function parseRGBA(str) {
                if (!str || str === 'transparent') return null;
                var m = str.match(/rgba?\\(\\s*([\\d.]+)\\s*,\\s*([\\d.]+)\\s*,\\s*([\\d.]+)(?:\\s*,\\s*([\\d.]+))?\\s*\\)/i);
                if (!m) return null;
                var a = (m[4] === undefined) ? 1.0 : parseFloat(m[4]);
                if (a <= 0.01) return null;
                return [parseFloat(m[1]), parseFloat(m[2]), parseFloat(m[3]), Math.min(1.0, a)];
              }
              function sampleAt(x, y) {
                var el = document.elementFromPoint(x, y) || document.body;
                var layers = [];
                while (el && el.nodeType === 1) {
                  var c = parseRGBA(window.getComputedStyle(el).backgroundColor);
                  if (c) layers.push(c);
                  el = el.parentElement;
                }
                var rgb = \(baseRGB);
                for (var i = layers.length - 1; i >= 0; i--) {
                  var fg = layers[i];
                  var a = fg[3];
                  rgb = [
                    fg[0] * a + rgb[0] * (1 - a),
                    fg[1] * a + rgb[1] * (1 - a),
                    fg[2] * a + rgb[2] * (1 - a)
                  ];
                }
                return (0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]) / 255.0;
              }
              var w = Math.max(60, window.innerWidth || 400);
              var h = Math.max(60, (document.body && document.body.scrollHeight) || 160);
              var l1 = sampleAt(w * 0.5, Math.min(32, h * 0.25));
              var l2 = sampleAt(w * 0.5, Math.min(180, h * 0.5));
              var l3 = sampleAt(w * 0.5, Math.max(32, h - 32));
              return (l1 + l2 + l3) / 3.0;
            })();
            """
            webView.evaluateJavaScript(js, in: nil, in: .defaultClient) { [weak self] outcome in
                guard let self, case .success(let value) = outcome else { return }
                let lum: Double?
                if let d = value as? Double {
                    lum = d
                } else if let n = value as? NSNumber {
                    lum = n.doubleValue
                } else {
                    lum = nil
                }
                if let lum, lum.isFinite {
                    self.onSurfaceModeResolved?(lum >= 0.48 ? .light : .dark)
                }
            }
        }

        func measureContentHeight(in webView: WKWebView) {
            webView.evaluateJavaScript(Self.measureHeightJS, in: nil, in: .defaultClient) { [weak self] outcome in
                guard let self, case .success(let value) = outcome else { return }
                let numericHeight: CGFloat?
                if let d = value as? Double {
                    numericHeight = CGFloat(d)
                } else if let n = value as? NSNumber {
                    numericHeight = CGFloat(truncating: n)
                } else {
                    numericHeight = nil
                }
                if let h = numericHeight, h.isFinite, h > 0 {
                    if abs(self.dynamicHeight.wrappedValue - h) > 1.0 {
                        self.dynamicHeight.wrappedValue = h
                    }
                }
            }
        }

        // MARK: - HTML Wrapping & Theme Adaptation

        static func usesHardcodedLightSurface(_ html: String) -> Bool {
            let lower = html.lowercased()
            if lower.contains("prefers-color-scheme") {
                return false
            }
            return lower.contains("<table")
                || lower.contains("bgcolor")
                || lower.contains("background-color")
                || lower.contains("background:")
                || lower.contains("color:")
                || lower.contains("color=")
        }

        static func wrapEmailDocument(rawHTML: String, themeMode: ThemeMode) -> String {
            let needsLightPaperCard = (themeMode == .dark) && usesHardcodedLightSurface(rawHTML)

            let rootCSS: String
            let linkColor: String
            if themeMode == .light {
                rootCSS = """
                html, body {
                  background-color: transparent;
                  color: #171719;
                }
                """
                linkColor = "#3B6FD4"
            } else if needsLightPaperCard {
                rootCSS = """
                html {
                  background-color: transparent;
                }
                body {
                  background-color: #FAFAFB !important;
                  color: #171719;
                  border-radius: 10px;
                  padding: 20px 24px !important;
                  box-sizing: border-box;
                }
                """
                linkColor = "#2B5EC4"
            } else {
                rootCSS = """
                html, body {
                  background-color: transparent;
                  color: #EDEDEF;
                }
                """
                linkColor = "#6B9AFF"
            }

            let styleSheet = """
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style id="mailroom-injected-style">
              html, body {
                margin: 0;
                padding: 0;
                width: 100%;
                overflow-x: hidden;
                overflow-wrap: break-word;
                word-break: break-word;
                font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "PingFang SC", "Helvetica Neue", sans-serif;
                font-size: 13.5px;
                line-height: 1.65;
                -webkit-font-smoothing: antialiased;
              }
              \(rootCSS)
              a {
                color: \(linkColor);
              }
              img {
                max-width: 100% !important;
                height: auto !important;
              }
              table {
                max-width: 100% !important;
              }
              pre, code {
                white-space: pre-wrap;
                word-break: break-word;
                font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
              }
              blockquote {
                margin: 10px 0;
                padding-left: 12px;
                border-left: 2px solid rgba(128, 128, 136, 0.35);
              }
            </style>
            """

            if let headClose = rawHTML.range(of: "</head>", options: .caseInsensitive) {
                var doc = rawHTML
                doc.insert(contentsOf: styleSheet, at: headClose.lowerBound)
                return doc
            }
            if let htmlOpen = rawHTML.range(of: #"<html[^>]*>"#, options: [.regularExpression, .caseInsensitive]) {
                var doc = rawHTML
                doc.insert(contentsOf: "<head>\(styleSheet)</head>", at: htmlOpen.upperBound)
                return doc
            }
            return """
            <!DOCTYPE html>
            <html>
            <head>\(styleSheet)</head>
            <body>\(rawHTML)</body>
            </html>
            """
        }
    }
}

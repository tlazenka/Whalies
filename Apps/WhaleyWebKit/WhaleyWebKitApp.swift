import SwiftUI
import UIKit
import WebKit

@main
struct WhaleyWebKitApp: App {
    var body: some Scene {
        WindowGroup {
            OfflineWhaleyView()
                .ignoresSafeArea()
                .background(Color.black)
        }
    }
}

/// This is a host only: the same Scala.js Canvas bundle, gallery, controls,
/// persistence and sound engine run inside WebKit without another game model.
private struct OfflineWhaleyView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default() // retain WebKit localStorage between launches
        configuration.allowsInlineMediaPlayback = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        guard let resources = Bundle.main.resourceURL else {
            fatalError("Whaley WebKit cannot find the application resources")
        }
        configuration.setURLSchemeHandler(
            PackagedGameSchemeHandler(root: resources.appendingPathComponent("WhaleyWebBundle", isDirectory: true)),
            forURLScheme: "whaleyplaytest"
        )

        let bridge = configuration.userContentController
        bridge.add(context.coordinator, name: "diagnostics")
        bridge.addUserScript(WKUserScript(source: """
            window.addEventListener('error', event => {
              window.webkit.messageHandlers.diagnostics.postMessage(
                'JavaScript: ' + (event.message || 'unknown error'));
            }, true);
            window.addEventListener('unhandledrejection', event => {
              window.webkit.messageHandlers.diagnostics.postMessage(
                'Promise: ' + String(event.reason));
            });
            """, injectionTime: .atDocumentStart, forMainFrameOnly: true))

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.isOpaque = true
        view.backgroundColor = .black
        view.scrollView.isScrollEnabled = false
        view.scrollView.contentInsetAdjustmentBehavior = .never
        #if DEBUG
        view.isInspectable = true // Safari Develop → device → Whaley WebKit
        #endif
        let url = URL(string: "whaleyplaytest://app/index.html")!
        view.load(URLRequest(url: url))
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            print("[Whaley WebKit] \(message.body)")
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // The bundled game is fully offline. Never navigate to remote content.
            let url = navigationAction.request.url
            decisionHandler(url?.scheme == "whaleyplaytest" && url?.host == "app" ? .allow : .cancel)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!,
                     withError error: Error) {
            print("[Whaley WebKit] Navigation failed: \(error)")
        }

        func webView(_ webView: WKWebView,
                     didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            print("[Whaley WebKit] Initial load failed: \(error)")
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            print("[Whaley WebKit] Content process restarted")
            webView.reload()
        }
    }
}

import SwiftUI
import WebKit

struct ContentView: View {
    @State private var ready = false
    @State private var navTitle = "dsh 助手"
    @State private var showSpinner = true
    @State private var errorMsg: String?

    var body: some View {
        NavigationView {
            ZStack {
                if ready {
                    DashWebView(port: NodeHost.shared.port, navTitle: $navTitle)
                } else if let e = errorMsg {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 44))
                            .foregroundColor(.orange)
                        Text(e).font(.body).multilineTextAlignment(.center).padding(.horizontal)
                        Button("重试") {
                            errorMsg = nil
                            boot()
                        }.buttonStyle(.borderedProminent)
                    }
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("正在启动 dsh 环境…").foregroundColor(.secondary)
                        if #available(iOS 15.0, *) { Text("首次启动稍慢").font(.caption).foregroundColor(.secondary) }
                    }
                }
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        if !ready {
                            ProgressView()
                        }
                        Button { reload() } label: { Image(systemName: "arrow.clockwise") }
                    }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear { boot() }
        .onDisappear { NodeHost.shared.stop() }
    }

    private func boot() {
        ready = false
        showSpinner = true
        errorMsg = nil
        _ = NodeHost.shared.start()
        DispatchQueue.global(qos: .userInteractive).async {
            let ok = NodeHost.shared.waitUntilReady(timeout: 90)
            DispatchQueue.main.async {
                if ok {
                    ready = true
                } else {
                    errorMsg = "dsh 服务启动失败，请点重试。"
                }
            }
        }
    }

    private func reload() {
        NotificationCenter.default.post(name: .dshReload, object: nil)
    }
}

/// 全屏 WKWebView，无浏览器痕迹。原生导航 + 右上刷新。
struct DashWebView: UIViewRepresentable {
    let port: Int
    @Binding var navTitle: String
    let webView = WKWebView()

    func makeUIView(context: Context) -> WKWebView {
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        NotificationCenter.default.addObserver(forName: .dshReload, object: nil, queue: .main) { _ in
            webView.reload()
        }
        load()
        return webView
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func load() {
        // 首访带 token 换 cookie，之后走干净 URL
        let url = NodeHost.shared.launchURL() ?? URL(string: "http://127.0.0.1:\(port)")!
        webView.load(URLRequest(url: url))
        // 3 秒后用干净 URL 再加载一次（cookie 已种下则进入正常页）
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self = self else { return }
            let plain = URL(string: "http://127.0.0.1:\(self.port)")!
            self.webView.load(URLRequest(url: plain))
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: DashWebView
        init(_ p: DashWebView) { parent = p }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript("document.title") { v, _ in
                if let t = v as? String, !t.isEmpty {
                    DispatchQueue.main.async { self.parent.navTitle = t }
                }
            }
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            // 首次 webview 比服务早就绪时会失败，这里重试几次
            retryLoad(webView, count: 10)
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            retryLoad(webView, count: 10)
        }
        private func retryLoad(_ webView: WKWebView, count: Int) {
            guard count > 0 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                if NodeHost.shared.healthCheck(), let url = self?.parent.webView.url ?? URL(string: "http://127.0.0.1:\(self?.parent.port ?? 3280)") {
                    webView.load(URLRequest(url: url))
                } else {
                    self?.retryLoad(webView, count: count - 1)
                }
            }
        }
    }
}

extension Notification.Name {
    static let dshReload = Notification.Name("dshReload")
}
import UIKit
import WebKit

/// Full-screen web view showing the course player. The page tells us when its video goes fullscreen
/// (window.webkit.messageHandlers.kanke.postMessage({fs: true/false})) and we turn the whole phone to
/// landscape, also with the rotation lock on, so iOS's own gestures (swipe up to switch apps) work as usual.
final class PlayerViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    static let home = URL(string: "https://yuquanzhao9.github.io/studium-taeglich/player/")!
    /// Same list as WKAppBoundDomains in Info.plist (needed for the page's offline cache / service worker).
    /// Videos from the PC are plain fetches, not navigations, so its Tailscale address doesn't need to be here.
    static let ownHosts: Set<String> = ["yuquanzhao9.github.io"]

    private var web: WKWebView!
    private let failView = UIStackView()
    private var fullscreen = false

    override func loadView() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = true
        config.limitsNavigationsToAppBoundDomains = true
        config.websiteDataStore = .default()
        config.userContentController.add(WeakHandler(self), name: "kanke")

        web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.allowsBackForwardNavigationGestures = false // no edge swipe "back", the reason for this app
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.backgroundColor = .black
        web.scrollView.contentInsetAdjustmentBehavior = .never // the page pads itself with env(safe-area-inset-*)
        if #available(iOS 16.4, *) { web.isInspectable = true }

        let refresh = UIRefreshControl()
        refresh.tintColor = .lightGray
        refresh.addTarget(self, action: #selector(pullToRefresh(_:)), for: .valueChanged)
        web.scrollView.refreshControl = refresh

        view = UIView()
        view.backgroundColor = .black
        web.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(web)
        NSLayoutConstraint.activate([
            web.topAnchor.constraint(equalTo: view.topAnchor),
            web.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            web.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        buildFailView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        NotificationCenter.default.addObserver(self, selector: #selector(deviceTurned), name: UIDevice.orientationDidChangeNotification, object: nil)
        web.load(URLRequest(url: Self.home))
    }

    // MARK: fullscreen = landscape

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent } // the page is dark
    override var prefersStatusBarHidden: Bool { fullscreen }
    override var prefersHomeIndicatorAutoHidden: Bool { fullscreen }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { AppDelegate.orientations }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let on = body["fs"] as? Bool else { return }
        setFullscreen(on)
    }

    private func setFullscreen(_ on: Bool) {
        fullscreen = on
        setNeedsStatusBarAppearanceUpdate()
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        rotate(to: on ? .landscape : .portrait)
        // back upright: allow turning again once the phone itself is upright (otherwise it would flip straight back)
        if !on { DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.deviceTurned() } }
    }

    private func rotate(to mask: UIInterfaceOrientationMask) {
        AppDelegate.orientations = mask
        setNeedsUpdateOfSupportedInterfaceOrientations()
        view.window?.windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
    }

    @objc private func deviceTurned() {
        guard !fullscreen, AppDelegate.orientations == .portrait, !UIDevice.current.orientation.isLandscape else { return }
        AppDelegate.orientations = .allButUpsideDown
        setNeedsUpdateOfSupportedInterfaceOrientations()
    }

    // MARK: loading

    @objc private func pullToRefresh(_ sender: UIRefreshControl) {
        if web.url == nil { web.load(URLRequest(url: Self.home)) } else { web.reload() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { sender.endRefreshing() }
    }

    @objc private func retry() {
        failView.isHidden = true
        web.load(URLRequest(url: Self.home))
    }

    private func buildFailView() {
        let label = UILabel()
        label.text = "打不开播放器（没网？）\n下载过的课在有网时打开过一次后，离线也能看。"
        label.textColor = .lightGray
        label.numberOfLines = 0
        label.textAlignment = .center
        let button = UIButton(type: .system)
        button.setTitle("重试", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 18, weight: .semibold)
        button.addTarget(self, action: #selector(retry), for: .touchUpInside)
        failView.axis = .vertical
        failView.spacing = 16
        failView.alignment = .center
        failView.addArrangedSubview(label)
        failView.addArrangedSubview(button)
        failView.isHidden = true
        failView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(failView)
        NSLayoutConstraint.activate([
            failView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            failView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            failView.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -48),
        ])
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { failView.isHidden = true }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code == NSURLErrorCancelled { return }
        if webView.backForwardList.currentItem == nil { failView.isHidden = false } // nothing shown yet
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { webView.reload() }

    /// Our own pages stay in the app; anything else (other sites) opens in Safari.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url, let scheme = url.scheme?.lowercased() else { return decisionHandler(.cancel) }
        if scheme == "about" || scheme == "blob" || scheme == "data" { return decisionHandler(.allow) }
        if let host = url.host?.lowercased(), Self.ownHosts.contains(host) { return decisionHandler(.allow) }
        if navigationAction.targetFrame?.isMainFrame ?? true { UIApplication.shared.open(url) }
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // target=_blank: own pages load here, others open in Safari
        if let url = navigationAction.request.url {
            if let host = url.host?.lowercased(), Self.ownHosts.contains(host) { webView.load(navigationAction.request) } else { UIApplication.shared.open(url) }
        }
        return nil
    }

    // MARK: alert / confirm / prompt (the page uses them for notes, deleting downloads, the PC address)

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in completionHandler(true) })
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in completionHandler(alert.textFields?.first?.text ?? "") })
        present(alert, animated: true)
    }
}

/// WKUserContentController keeps its handlers alive; this breaks the cycle with the view controller.
private final class WeakHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}

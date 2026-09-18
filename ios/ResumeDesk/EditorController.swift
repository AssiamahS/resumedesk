import UIKit
import WebKit
import UniformTypeIdentifiers

/// Hosts the web editor (web/editor.html) and gives it what a browser can't on iOS:
/// Save to Files with write-back, opening from Files, the share sheet, and printing.
/// The page talks to us through `window.webkit.messageHandlers.desk.postMessage(...)`.
final class EditorController: UIViewController, WKScriptMessageHandlerWithReply,
                              WKNavigationDelegate, UIDocumentPickerDelegate {
    static weak var current: EditorController?

    private var web: WKWebView!
    private var pickerDone: (([URL]) -> Void)?
    private var loaded = false
    private var pendingJS: [String] = []

    private var stateURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("state.json")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        Self.current = self
        view.backgroundColor = .systemBackground

        // documents live in Application Support (not WebKit's localStorage), handed to the page at start
        let ucc = WKUserContentController()
        var saved = (try? String(contentsOf: stateURL, encoding: .utf8)) ?? "null"
        if (try? JSONSerialization.jsonObject(with: Data(saved.utf8))) == nil { saved = "null" }
        ucc.addUserScript(WKUserScript(source: "window.__DESK_STATE = \(saved);",
                                       injectionTime: .atDocumentStart, forMainFrameOnly: true))
        ucc.addScriptMessageHandler(self, contentWorld: .page, name: "desk")

        let cfg = WKWebViewConfiguration()
        cfg.userContentController = ucc
        web = WKWebView(frame: .zero, configuration: cfg)
        web.navigationDelegate = self
        web.isInspectable = true
        web.isOpaque = false
        web.backgroundColor = .systemBackground
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(web)
        NSLayoutConstraint.activate([
            web.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            web.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            web.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            web.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
        ])

        guard let dir = Bundle.main.url(forResource: "web", withExtension: nil) else { return }
        web.loadFileURL(dir.appendingPathComponent("editor.html"), allowingReadAccessTo: dir)
    }

    // MARK: page -> app

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) async -> (Any?, String?) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else {
            return (nil, "Bad message from the page")
        }
        switch type {
        case "persist":
            if let json = body["json"] as? String {
                try? json.write(to: stateURL, atomically: true, encoding: .utf8)
            }
            return (true, nil)
        case "save": return await save(body)
        case "open": return await open()
        case "share": return share(body)
        case "print": printPage(); return (true, nil)
        default: return (nil, "Unknown request \(type)")
        }
    }

    private func save(_ body: [String: Any]) async -> (Any?, String?) {
        let filename = (body["filename"] as? String) ?? "document"
        guard let b64 = body["b64"] as? String, let data = Data(base64Encoded: b64) else {
            return (nil, "Nothing to save")
        }
        // a file opened from Files: write straight back to it
        if let token = body["path"] as? String, let url = Bookmarks.resolve(token) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if (try? data.write(to: url)) != nil {
                return (["msg": "Saved to \(url.lastPathComponent)", "path": token], nil)
            }
        }
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let tmp = tmpDir.appendingPathComponent(filename)
        do { try data.write(to: tmp) } catch { return (nil, "Could not prepare \(filename)") }

        let urls = await pick(UIDocumentPickerViewController(forExporting: [tmp], asCopy: false))
        guard let dest = urls.first else { return (nil, nil) }        // cancelled
        return (["msg": "Saved to \(dest.lastPathComponent)", "path": Bookmarks.store(dest)], nil)
    }

    private func open() async -> (Any?, String?) {
        var types: [UTType] = [.plainText, .text, .html, .pdf]
        for ext in ["md", "markdown", "docx"] { if let t = UTType(filenameExtension: ext) { types.append(t) } }
        let urls = await pick(UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false))
        guard let url = urls.first else { return (nil, nil) }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            return (nil, "Could not read \(url.lastPathComponent). If it's in iCloud, wait for it to download.")
        }
        return (["name": url.lastPathComponent, "b64": data.base64EncodedString(),
                 "path": Bookmarks.store(url)], nil)
    }

    private func share(_ body: [String: Any]) -> (Any?, String?) {
        let filename = (body["filename"] as? String) ?? "document.pdf"
        guard let b64 = body["b64"] as? String, let data = Data(base64Encoded: b64) else {
            return (nil, "Nothing to share")
        }
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        let file = tmpDir.appendingPathComponent(filename)
        guard (try? data.write(to: file)) != nil else { return (nil, "Could not prepare \(filename)") }
        let sheet = UIActivityViewController(activityItems: [file], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = view
        sheet.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: 60, width: 1, height: 1)
        present(sheet, animated: true)
        return (true, nil)
    }

    private func printPage() {
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .general
        info.jobName = "Resume Desk"
        let pc = UIPrintInteractionController.shared
        pc.printInfo = info
        pc.printFormatter = web.viewPrintFormatter()
        pc.present(animated: true)
    }

    private func pick(_ picker: UIDocumentPickerViewController) async -> [URL] {
        await withCheckedContinuation { cont in
            pickerDone = { cont.resume(returning: $0) }
            picker.delegate = self
            present(picker, animated: true)
        }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        pickerDone?(urls); pickerDone = nil
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        pickerDone?([]); pickerDone = nil
    }

    // MARK: "Open in Resume Desk" from Files, Mail, etc.

    func importURL(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        let args: [Any] = [url.lastPathComponent, data.base64EncodedString(), Bookmarks.store(url)]
        guard let json = try? JSONSerialization.data(withJSONObject: args),
              let list = String(data: json, encoding: .utf8) else { return }
        let js = "window.deskImport(...\(list))"
        if loaded { web.evaluateJavaScript(js) } else { pendingJS.append(js) }
    }

    // MARK: navigation

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded = true
        pendingJS.forEach { webView.evaluateJavaScript($0) }
        pendingJS.removeAll()
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        // links inside a document open in Safari instead of replacing the editor
        if action.navigationType == .linkActivated, let url = action.request.url {
            _ = await UIApplication.shared.open(url)
            return .cancel
        }
        return .allow
    }
}

/// Security-scoped bookmarks so Save can write back to a file picked in Files, across launches.
enum Bookmarks {
    private static let key = "bookmarks"

    static func store(_ url: URL) -> String {
        let token = url.absoluteString
        if let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            var all = UserDefaults.standard.dictionary(forKey: key) as? [String: Data] ?? [:]
            all[token] = data
            UserDefaults.standard.set(all, forKey: key)
        }
        return token
    }

    static func resolve(_ token: String) -> URL? {
        guard let data = (UserDefaults.standard.dictionary(forKey: key) as? [String: Data])?[token] else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil,
                                 bookmarkDataIsStale: &stale) else { return nil }
        if stale { _ = store(url) }
        return url
    }
}

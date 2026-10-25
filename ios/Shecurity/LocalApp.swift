import Foundation
import WebKit
import UniformTypeIdentifiers

// The whole Shecurity app ships inside the iPhone app (the www folder) and is served from
// shecurity-app://localhost/app/, so it opens instantly and works without a connection.
// Only the circle (Supabase), maps and donations go to the internet.
let appScheme = "shecurity-app"
let localRoot = URL(string: "\(appScheme)://localhost/app/")!

/// Turns a shecurity.app/app link, a shortcut or a shecurity:// link into the same screen inside the app.
func localURL(for link: URL?) -> URL {
    guard let link = link else { return localRoot }
    if link.scheme == appScheme { return link }
    var comps = URLComponents(url: localRoot, resolvingAgainstBaseURL: false)!
    if let f = link.fragment, f.range(of: "^[A-Za-z0-9_-]{1,40}$", options: .regularExpression) != nil {
        comps.fragment = f
    }
    return comps.url ?? localRoot
}

final class LocalAppHandler: NSObject, WKURLSchemeHandler {
    private let base = Bundle.main.resourceURL!.appendingPathComponent("www", isDirectory: true)

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { return task.didFailWithError(URLError(.badURL)) }
        var path = url.path
        if path.hasPrefix("/app") { path = String(path.dropFirst(4)) }
        if path.isEmpty || path == "/" { path = "/index.html" }
        let file = base.appendingPathComponent(String(path.dropFirst())).standardizedFileURL
        // never serve anything outside the app's own folder
        guard file.path.hasPrefix(base.standardizedFileURL.path), let data = try? Data(contentsOf: file) else {
            let r = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
            task.didReceive(r); task.didReceive(Data()); task.didFinish()
            return
        }
        let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType
            ?? (file.pathExtension == "webmanifest" ? "application/json" : "application/octet-stream")
        let r = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                headerFields: ["Content-Type": mime, "Content-Length": "\(data.count)", "Cache-Control": "no-cache"])!
        task.didReceive(r)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}

    /// Bundled files, for native code that plays them (the fake call voice).
    func data(for url: URL) -> Data? {
        guard url.scheme == appScheme else { return nil }
        var path = url.path
        if path.hasPrefix("/app/") { path = String(path.dropFirst(5)) }
        let file = base.appendingPathComponent(path).standardizedFileURL
        guard file.path.hasPrefix(base.standardizedFileURL.path) else { return nil }
        return try? Data(contentsOf: file)
    }
}

let localApp = LocalAppHandler()

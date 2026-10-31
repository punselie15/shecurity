import UIKit
import WebKit
import AuthenticationServices
import SafariServices


func createWebView(container: UIView, WKSMH: WKScriptMessageHandler, WKND: WKNavigationDelegate, NSO: NSObject, VC: ViewController) -> WKWebView{

    let config = WKWebViewConfiguration()
    let userContentController = WKUserContentController()

    userContentController.add(WKSMH, name: "print")
    userContentController.add(WKSMH, name: "push-subscribe")
    userContentController.add(WKSMH, name: "push-permission-request")
    userContentController.add(WKSMH, name: "push-permission-state")
    userContentController.add(WKSMH, name: "push-token")
    userContentController.add(NativeGeolocation.shared, name: "geo")
    userContentController.add(WidgetBridge.shared, name: "widget-config")
    userContentController.add(EarAudio.shared, name: "call-audio")
    #if os(iOS) && !targetEnvironment(macCatalyst)
    userContentController.add(WatchBridge.shared, name: "watch-config")
    #endif
    userContentController.addUserScript(WKUserScript(source: NativeGeolocation.script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    // the phone's region setting, so the app shows the right emergency number
    let region = (Locale.current.regionCode ?? "").filter { $0.isLetter }.prefix(2)
    userContentController.addUserScript(WKUserScript(source: "window.SHECURITY_REGION = '\(region)';", injectionTime: .atDocumentStart, forMainFrameOnly: true))
    // tells the web app whether circle alerts can come through Apple push (Firebase set up)
    userContentController.addUserScript(WKUserScript(source: "window.SHECURITY_PUSH = \(pushReady ? "true" : "false");", injectionTime: .atDocumentStart, forMainFrameOnly: true))

    config.userContentController = userContentController
    config.setURLSchemeHandler(localApp, forURLScheme: appScheme)

    // the app is local now, so no domain list is needed
    config.limitsNavigationsToAppBoundDomains = false;
    config.allowsInlineMediaPlayback = true
    config.preferences.javaScriptCanOpenWindowsAutomatically = true
    config.preferences.setValue(true, forKey: "standalone")
    
    let webView = WKWebView(frame: calcWebviewFrame(webviewView: container, toolbarView: nil), configuration: config)
    setCustomCookie(webView: webView)
    NativeGeolocation.shared.webView = webView

    webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    webView.isHidden = true;
    webView.navigationDelegate = WKND
    webView.scrollView.bounces = false
    webView.scrollView.contentInsetAdjustmentBehavior = .never
    webView.allowsBackForwardNavigationGestures = true
    
    // Check if macCatalyst 16.4+ is available and if so, enable web inspector.
    // This allows the web app to be inspected using Safari Web Inspector. Supported on iOS 16.4+ and macOS 13.3+
    if #available(iOS 16.4, macOS 13.3, *) {
        webView.isInspectable = true
    }
    
    let deviceModel = UIDevice.current.model
    let osVersion = UIDevice.current.systemVersion
    webView.configuration.applicationNameForUserAgent = "Safari/604.1"
    webView.customUserAgent = "Mozilla/5.0 (\(deviceModel); CPU \(deviceModel) OS \(osVersion.replacingOccurrences(of: ".", with: "_")) like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/\(osVersion) Mobile/15E148 Safari/604.1 PWAShell ShecurityApp/5"

    webView.addObserver(NSO, forKeyPath: #keyPath(WKWebView.estimatedProgress), options: NSKeyValueObservingOptions.new, context: nil)
    
    #if DEBUG
    if #available(iOS 16.4, *) {
        webView.isInspectable = true
    }
    #endif
    
    return webView
}

func setAppStoreAsReferrer(contentController: WKUserContentController) {
    let scriptSource = "document.referrer = `app-info://platform/ios-store`;"
    let script = WKUserScript(source: scriptSource, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    contentController.addUserScript(script);
}

func setCustomCookie(webView: WKWebView) {
    let _platformCookie = HTTPCookie(properties: [
        .domain: rootUrl.host!,
        .path: "/",
        .name: platformCookie.name,
        .value: platformCookie.value,
        .secure: "FALSE",
        .expires: NSDate(timeIntervalSinceNow: 31556926)
    ])!

    webView.configuration.websiteDataStore.httpCookieStore.setCookie(_platformCookie)

}

func calcWebviewFrame(webviewView: UIView, toolbarView: UIToolbar?) -> CGRect{
    if ((toolbarView) != nil) {
        return CGRect(x: 0, y: toolbarView!.frame.height, width: webviewView.frame.width, height: webviewView.frame.height - toolbarView!.frame.height)
    }
    else {
        let winScene = UIApplication.shared.connectedScenes.first
        let windowScene = winScene as! UIWindowScene
        var statusBarHeight = windowScene.statusBarManager?.statusBarFrame.height ?? 0

        switch displayMode {
        case "fullscreen":
            #if targetEnvironment(macCatalyst)
                if let titlebar = windowScene.titlebar {
                    titlebar.titleVisibility = .hidden
                    titlebar.toolbar = nil
                }
            #endif
            return CGRect(x: 0, y: 0, width: webviewView.frame.width, height: webviewView.frame.height)
        default:
            #if targetEnvironment(macCatalyst)
            statusBarHeight = 29
            #endif
            let windowHeight = webviewView.frame.height - statusBarHeight
            return CGRect(x: 0, y: statusBarHeight, width: webviewView.frame.width, height: windowHeight)
        }
    }
}

extension ViewController: WKUIDelegate, WKDownloadDelegate {
    // redirect new tabs to main webview
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if (navigationAction.targetFrame == nil) {
            webView.load(navigationAction.request)
        }
        return nil
    }
    // restrict navigation to target host, open external links in 3rd party apps
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if (navigationAction.request.url?.scheme == "about") {
            return decisionHandler(.allow)
        }
        if (navigationAction.shouldPerformDownload || navigationAction.request.url?.scheme == "blob") {
            return decisionHandler(.download)
        }

        if let requestUrl = navigationAction.request.url{
            if requestUrl.scheme == appScheme { return decisionHandler(.allow) }
            if requestUrl.host == "shecurity.app", requestUrl.path.hasPrefix("/app") {
                decisionHandler(.cancel)
                webView.load(URLRequest(url: localURL(for: requestUrl)))
                return
            }
            // Schemes that should always be handed off to the system/other apps rather than
            // being processed as in-app navigation (e.g. phone calls, email, maps, FaceTime, etc.)
            let externalSchemes = ["tel", "telprompt", "mailto", "facetime", "facetime-audio", "fb", "fb-messenger", "sms", "itms-services", "itms-apps", "itms", "maps"]
            if let requestScheme = requestUrl.scheme?.lowercased(), externalSchemes.contains(requestScheme) {
                decisionHandler(.cancel)
                if UIApplication.shared.canOpenURL(requestUrl) {
                    UIApplication.shared.open(requestUrl)
                }
                return
            }

            if let requestHost = requestUrl.host {
                // NOTE: Match auth origin first, because host origin may be a subset of auth origin and may therefore always match
                let matchingAuthOrigin = authOrigins.first(where: { requestHost.range(of: $0) != nil })
                if (matchingAuthOrigin != nil) {
                    decisionHandler(.allow)
                    if (toolbarView.isHidden) {
                        toolbarView.isHidden = false
                        webView.frame = calcWebviewFrame(webviewView: webviewView, toolbarView: toolbarView)
                    }
                    return
                }

                let matchingHostOrigin: String? = nil // every website opens in Safari
                if (matchingHostOrigin != nil) {
                    // Open in main webview
                    decisionHandler(.allow)
                    if (!toolbarView.isHidden) {
                        toolbarView.isHidden = true
                        webView.frame = calcWebviewFrame(webviewView: webviewView, toolbarView: nil)
                    }
                    return
                }
                if (navigationAction.navigationType == .other &&
                    navigationAction.value(forKey: "syntheticClickType") as! Int == 0 &&
                    (navigationAction.targetFrame != nil) &&
                    // no error here, fake warning
                    (navigationAction.sourceFrame != nil)
                ) {
                    decisionHandler(.allow)
                    return
                }
                else {
                    decisionHandler(.cancel)
                }


                if ["http", "https"].contains(requestUrl.scheme?.lowercased() ?? "") {
                    // websites (the donate page, maps) open in the phone's browser
                    UIApplication.shared.open(requestUrl)
                } else {
                    // Scheme is not supported or no scheme is given, use openURL
                    if (UIApplication.shared.canOpenURL(requestUrl)) {
                        UIApplication.shared.open(requestUrl)
                    }
                }
            } else {
                decisionHandler(.cancel)
                if requestUrl.isFileURL {
                    // not tested
                    downloadAndOpenFile(url: requestUrl.absoluteURL)
                }
                // if (requestUrl.absoluteString.contains("base64")){
                //     downloadAndOpenBase64File(base64String: requestUrl.absoluteString)
                // }
            }
        }
        else {
            decisionHandler(.cancel)
        }

    }
    // Handle javascript: `window.alert(message: String)`
    func webView(_ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void) {

        // Set the message as the UIAlertController message
        let alert = UIAlertController(
            title: nil,
            message: message,
            preferredStyle: .alert
        )

        // Add a confirmation action “OK”
        let okAction = UIAlertAction(
            title: "OK",
            style: .default,
            handler: { _ in
                // Call completionHandler
                completionHandler()
            }
        )
        alert.addAction(okAction)

        // Display the NSAlert
        present(alert, animated: true, completion: nil)
    }
    // Handle javascript: `window.confirm(message: String)`
    func webView(_ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void) {

        // Set the message as the UIAlertController message
        let alert = UIAlertController(
            title: nil,
            message: message,
            preferredStyle: .alert
        )

        // Add a confirmation action “Cancel”
        let cancelAction = UIAlertAction(
            title: "Cancel",
            style: .cancel,
            handler: { _ in
                // Call completionHandler
                completionHandler(false)
            }
        )

        // Add a confirmation action “OK”
        let okAction = UIAlertAction(
            title: "OK",
            style: .default,
            handler: { _ in
                // Call completionHandler
                completionHandler(true)
            }
        )
        alert.addAction(cancelAction)
        alert.addAction(okAction)

        // Display the NSAlert
        present(alert, animated: true, completion: nil)
    }
    // Handle javascript: `window.prompt(prompt: String, defaultText: String?)`
    func webView(_ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void) {

        // Set the message as the UIAlertController message
        let alert = UIAlertController(
            title: nil,
            message: prompt,
            preferredStyle: .alert
        )

        // Add a confirmation action “Cancel”
        let cancelAction = UIAlertAction(
            title: "Cancel",
            style: .cancel,
            handler: { _ in
                // Call completionHandler
                completionHandler(nil)
            }
        )

        // Add a confirmation action “OK”
        let okAction = UIAlertAction(
            title: "OK",
            style: .default,
            handler: { _ in
                // Call completionHandler with Alert input
                if let input = alert.textFields?.first?.text {
                    completionHandler(input)
                }
            }
        )

        alert.addTextField { textField in
            textField.placeholder = defaultText
        }
        alert.addAction(cancelAction)
        alert.addAction(okAction)

        // Display the NSAlert
        present(alert, animated: true, completion: nil)
    }

    func downloadAndOpenFile(url: URL){

        let destinationFileUrl = url
        let sessionConfig = URLSessionConfiguration.default
        let session = URLSession(configuration: sessionConfig)
        let request = URLRequest(url:url)
        let task = session.downloadTask(with: request) { (tempLocalUrl, response, error) in
            if let tempLocalUrl = tempLocalUrl, error == nil {
                if let statusCode = (response as? HTTPURLResponse)?.statusCode {
                    print("Successfully download. Status code: \(statusCode)")
                }
                do {
                    try FileManager.default.copyItem(at: tempLocalUrl, to: destinationFileUrl)
                    self.openFile(url: destinationFileUrl)
                } catch (let writeError) {
                    print("Error creating a file \(destinationFileUrl) : \(writeError)")
                }
            } else {
                print("Error took place while downloading a file. Error description: \(error?.localizedDescription ?? "N/A") ")
            }
        }
        task.resume()
    }

    // func downloadAndOpenBase64File(base64String: String) {
    //     // Split the base64 string to extract the data and the file extension
    //     let components = base64String.components(separatedBy: ";base64,")

    //     // Make sure the base64 string has the correct format
    //     guard components.count == 2, let format = components.first?.split(separator: "/").last else {
    //         print("Invalid base64 string format")
    //         return
    //     }

    //     // Remove the data type prefix to get the base64 data
    //     let dataString = components.last!

    //     if let imageData = Data(base64Encoded: dataString) {
    //         let documentsUrl: URL  =  FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    //         let destinationFileUrl = documentsUrl.appendingPathComponent("image.\(format)")

    //         do {
    //             try imageData.write(to: destinationFileUrl)
    //             self.openFile(url: destinationFileUrl)
    //         } catch {
    //             print("Error writing image to file url: \(destinationFileUrl): \(error)")
    //         }
    //     }
    // }

    func openFile(url: URL) {
        self.documentController = UIDocumentInteractionController(url: url)
        self.documentController?.delegate = self
        self.documentController?.presentPreview(animated: true)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                suggestedFilename: String,
                completionHandler: @escaping (URL?) -> Void) {

        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsPath.appendingPathComponent(suggestedFilename)

        // Remove existing file if it exists, otherwise it may show an old file/content just by having the same name.
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.removeItem(at: fileURL)
        }

        self.openFile(url: fileURL)
        completionHandler(fileURL)
    }
}

// MARK: - Native location
// Answers navigator.geolocation from the app itself, so iOS asks
// "Allow Shecurity to use your location?" instead of showing the web address.
import CoreLocation

final class NativeGeolocation: NSObject, WKScriptMessageHandler, CLLocationManagerDelegate {
    static let shared = NativeGeolocation()
    weak var webView: WKWebView?
    private let manager = CLLocationManager()
    private var pending: [Int] = []
    private var watches = Set<Int>()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    static let script = """
    (function(){
      if (!window.webkit || !webkit.messageHandlers || !webkit.messageHandlers.geo) return;
      var n = 0, cbs = {};
      function post(m){ webkit.messageHandlers.geo.postMessage(m); }
      function err(code, msg){ return { code: code, message: msg, PERMISSION_DENIED: 1, POSITION_UNAVAILABLE: 2, TIMEOUT: 3 }; }
      window.__shecGeo = { cb: function(ids, pos, e){
        ids.forEach(function(id){
          var c = cbs[id]; if (!c) return;
          if (c.once) delete cbs[id];
          if (pos) { c.ok && c.ok(pos); } else { c.err && c.err(err(e.code, e.message)); }
        });
      }};
      var geo = {
        getCurrentPosition: function(ok, fail, opt){
          var id = ++n; cbs[id] = { ok: ok, err: fail, once: true }; post({ action: "get", id: id });
          if (opt && opt.timeout && isFinite(opt.timeout)) setTimeout(function(){ if (cbs[id]) { delete cbs[id]; fail && fail(err(3, "Timeout")); } }, opt.timeout);
        },
        watchPosition: function(ok, fail){ var id = ++n; cbs[id] = { ok: ok, err: fail }; post({ action: "watch", id: id }); return id; },
        clearWatch: function(id){ delete cbs[id]; post({ action: "clear", id: id }); }
      };
      try { Object.defineProperty(navigator, "geolocation", { value: geo, configurable: true }); } catch (e) {}
    })();
    """

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let action = body["action"] as? String else { return }
        let id = (body["id"] as? NSNumber)?.intValue ?? 0
        switch action {
        case "get": pending.append(id); start()
        case "watch": watches.insert(id); start()
        case "clear": watches.remove(id); stopIfIdle()
        default: break
        }
    }

    private func start() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied, .restricted: fail(code: 1, message: "Location is off for Shecurity in Settings")
        default: manager.startUpdatingLocation()
        }
    }

    private func stopIfIdle() {
        if pending.isEmpty && watches.isEmpty { manager.stopUpdatingLocation() }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            if !pending.isEmpty || !watches.isEmpty { manager.startUpdatingLocation() }
        case .denied, .restricted:
            fail(code: 1, message: "Location is off for Shecurity in Settings")
        default: break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let ids = pending + Array(watches)
        pending = []
        let pos: [String: Any] = [
            "coords": [
                "latitude": loc.coordinate.latitude,
                "longitude": loc.coordinate.longitude,
                "accuracy": loc.horizontalAccuracy,
                "altitude": loc.verticalAccuracy >= 0 ? (loc.altitude as Any) : (NSNull() as Any),
                "altitudeAccuracy": loc.verticalAccuracy >= 0 ? (loc.verticalAccuracy as Any) : (NSNull() as Any),
                "heading": loc.course >= 0 ? (loc.course as Any) : (NSNull() as Any),
                "speed": loc.speed >= 0 ? (loc.speed as Any) : (NSNull() as Any)
            ],
            "timestamp": loc.timestamp.timeIntervalSince1970 * 1000
        ]
        send(ids: ids, pos: pos, error: nil)
        stopIfIdle()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if (error as? CLError)?.code == .locationUnknown { return }
        fail(code: 2, message: error.localizedDescription)
    }

    private func fail(code: Int, message: String) {
        let ids = pending + Array(watches)
        pending = []
        send(ids: ids, pos: nil, error: ["code": code, "message": message])
    }

    private func send(ids: [Int], pos: [String: Any]?, error: [String: Any]?) {
        guard !ids.isEmpty,
              let a = try? JSONSerialization.data(withJSONObject: ids),
              let p = try? JSONSerialization.data(withJSONObject: pos ?? NSNull(), options: .fragmentsAllowed),
              let e = try? JSONSerialization.data(withJSONObject: error ?? NSNull(), options: .fragmentsAllowed) else { return }
        let js = "window.__shecGeo && window.__shecGeo.cb(\(String(decoding: a, as: UTF8.self)), \(String(decoding: p, as: UTF8.self)), \(String(decoding: e, as: UTF8.self)))"
        DispatchQueue.main.async { self.webView?.evaluateJavaScript(js, completionHandler: nil) }
    }
}

// MARK: - Home-screen widget
// The web app sends its four widget buttons here; the widget reads them from the shared app group.
import WidgetKit

final class WidgetBridge: NSObject, WKScriptMessageHandler {
    static let shared = WidgetBridge()

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let buttons = body["buttons"] as? [[String: Any]], buttons.count == 4,
              let data = try? JSONSerialization.data(withJSONObject: buttons),
              let defaults = UserDefaults(suiteName: "group.io.github.punselie15.shecurity") else { return }
        if defaults.data(forKey: "buttons") == data { return }
        defaults.set(data, forKey: "buttons")
        WidgetCenter.shared.reloadAllTimelines()
    }
}

// MARK: - Apple Watch
// Passes the watch its buttons and key, and opens actions the watch hands back to the phone.
#if os(iOS) && !targetEnvironment(macCatalyst)
import WatchConnectivity

final class WatchBridge: NSObject, WKScriptMessageHandler, WCSessionDelegate {
    static let shared = WatchBridge()
    private var pending: [String: Any]?
    private let actions: Set<String> = ["help", "location", "fakecall-now", "fakecall", "call", "siren", "walk", "timer", "plan", "ride", "date", "record", "lines"]

    override init() {
        super.init()
        if WCSession.isSupported() { WCSession.default.delegate = self; WCSession.default.activate() }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard WCSession.isSupported(), let body = message.body as? [String: Any] else { return }
        if WCSession.default.activationState == .activated { try? WCSession.default.updateApplicationContext(body) }
        else { pending = body }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated, let body = pending { try? session.updateApplicationContext(body); pending = nil }
    }
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let action = message["action"] as? String, actions.contains(action) else { return }
        DispatchQueue.main.async { Shecurity.webView?.evaluateJavaScript("location.hash = 'q-\(action)'", completionHandler: nil) }
    }
}
#endif

// MARK: - Fake call voice
// Plays the caller's recorded lines through the ear speaker, like a real call, and blanks the screen at the ear.
import AVFoundation

final class EarAudio: NSObject, WKScriptMessageHandler, AVAudioPlayerDelegate {
    static let shared = EarAudio()
    private var player: AVAudioPlayer?
    private var playingId: String?
    private var clips: [URL: Data] = [:]

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let action = body["action"] as? String else { return }
        switch action {
        case "start": start()
        case "stop": stop()
        case "play":
            guard let id = body["id"] as? String, let text = body["url"] as? String, let url = URL(string: text) else { return }
            if let data = localApp.data(for: url) { playData(id: id, data: data); return }
            guard let host = url.host, allowedOrigins.contains(host) else { return }
            play(id: id, url: url)
        default: break
        }
    }

    private func start() {
        let session = AVAudioSession.sharedInstance()
        // playAndRecord without defaultToSpeaker routes to the receiver; voiceChat keeps it there and leaves the mic usable
        try? session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth])
        try? session.overrideOutputAudioPort(.none)
        try? session.setActive(true)
        UIDevice.current.isProximityMonitoringEnabled = true
    }

    private func stop() {
        player?.stop(); player = nil
        if let id = playingId { playingId = nil; done(id, true) }
        UIDevice.current.isProximityMonitoringEnabled = false
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
    }

    private func play(id: String, url: URL) {
        if let data = clips[url] { playData(id: id, data: data); return }
        URLSession.shared.dataTask(with: url) { data, response, _ in
            DispatchQueue.main.async {
                guard let data = data, (response as? HTTPURLResponse)?.statusCode == 200 else { self.done(id, false); return }
                self.clips[url] = data
                self.playData(id: id, data: data)
            }
        }.resume()
    }

    private func playData(id: String, data: Data) {
        guard let p = try? AVAudioPlayer(data: data) else { done(id, false); return }
        player?.stop()
        if let old = playingId { done(old, true) }
        p.delegate = self
        player = p; playingId = id
        if !p.play() { player = nil; playingId = nil; done(id, false) }
    }

    func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully flag: Bool) {
        guard p === player, let id = playingId else { return }
        player = nil; playingId = nil
        done(id, flag)
    }

    private func done(_ id: String, _ ok: Bool) {
        Shecurity.webView?.evaluateJavaScript("window.shecurityClipDone && window.shecurityClipDone('\(id)', \(ok))", completionHandler: nil)
    }
}

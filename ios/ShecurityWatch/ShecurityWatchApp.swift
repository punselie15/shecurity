import SwiftUI
import WatchKit
import WatchConnectivity
import CoreLocation
import AVFoundation

// Shecurity on Apple Watch: hold SOS to alert your circle, plus the four buttons chosen in the iPhone app.
private let pink = Color(red: 0.898, green: 0.282, blue: 0.498)
private let ink = Color(red: 0.165, green: 0.129, blue: 0.322)

struct WatchButton: Codable, Hashable, Identifiable {
    let id: String
    let label: String
}

struct WatchConfig: Codable {
    var buttons: [WatchButton] = [
        WatchButton(id: "location", label: "My location"),
        WatchButton(id: "fakecall-now", label: "Call me in 5s"),
        WatchButton(id: "help", label: "Send help"),
        WatchButton(id: "call", label: "Call 112")
    ]
    var emergency = "112"
    var name = ""
    var key = ""
    var endpoint = ""
    var apikey = ""
    var caller = "Mom"
}

enum SendState: Equatable { case idle, sending, sent(String), failed }

final class WatchStore: NSObject, ObservableObject, WCSessionDelegate, CLLocationManagerDelegate {
    @Published var config = WatchConfig()
    @Published var state: SendState = .idle
    @Published var countdown: Int? = nil
    @Published var incomingCall = false
    @Published var inCall: Date? = nil

    private let location = CLLocationManager()
    private var locationWaiters: [(CLLocation?) -> Void] = []
    private var timer: Timer?
    private var ring: Timer?
    private let voice = AVSpeechSynthesizer()

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: "config"),
           let saved = try? JSONDecoder().decode(WatchConfig.self, from: data) { config = saved }
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyBest
        if WCSession.isSupported() { WCSession.default.delegate = self; WCSession.default.activate() }
    }

    var linked: Bool { !config.key.isEmpty && !config.endpoint.isEmpty }

    // MARK: phone link
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if !session.receivedApplicationContext.isEmpty { apply(session.receivedApplicationContext) }
    }
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) { apply(applicationContext) }

    private func apply(_ context: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: context),
              var next = try? JSONDecoder().decode(WatchConfig.self, from: data) else { return }
        if next.buttons.count != 4 { next.buttons = WatchConfig().buttons }
        UserDefaults.standard.set(try? JSONEncoder().encode(next), forKey: "config")
        DispatchQueue.main.async { self.config = next }
    }

    private func askPhone(_ action: String) {
        guard WCSession.default.activationState == .activated, WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(["action": action], replyHandler: nil, errorHandler: nil)
    }

    // MARK: actions
    func run(_ id: String) {
        switch id {
        case "help": startCountdown()
        case "location": send(kind: "location")
        case "call": callEmergency()
        case "fakecall-now", "fakecall": scheduleCall()
        default:
            askPhone(id)
            WKInterfaceDevice.current().play(.click)
            state = .sent("Opened on your iPhone")
            clearStateSoon()
        }
    }

    func startCountdown() {
        WKInterfaceDevice.current().play(.start)
        countdown = 5
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            guard let self = self, let left = self.countdown else { t.invalidate(); return }
            if left <= 1 { t.invalidate(); self.countdown = nil; self.send(kind: "sos") }
            else { self.countdown = left - 1; WKInterfaceDevice.current().play(.click) }
        }
    }

    func cancelCountdown() {
        timer?.invalidate(); countdown = nil
        WKInterfaceDevice.current().play(.stop)
        state = .sent("Cancelled. Nothing was sent.")
        clearStateSoon()
    }

    func callEmergency() {
        let digits = config.emergency.filter { $0.isNumber }
        if let url = URL(string: "tel:\(digits.isEmpty ? "112" : digits)") { WKExtension.shared().openSystemURL(url) }
    }

    func send(kind: String) {
        state = .sending
        WKInterfaceDevice.current().play(kind == "sos" ? .notification : .click)
        currentLocation { [weak self] loc in self?.post(kind: kind, loc: loc) }
    }

    private func post(kind: String, loc: CLLocation?) {
        guard linked, let url = URL(string: config.endpoint) else { fallback(kind); return }
        var body: [String: Any] = ["key": config.key, "kind": kind]
        if let loc = loc {
            body["lat"] = (loc.coordinate.latitude * 100000).rounded() / 100000
            body["lng"] = (loc.coordinate.longitude * 100000).rounded() / 100000
            body["accuracy"] = loc.horizontalAccuracy
        }
        WKInterfaceDevice.current().isBatteryMonitoringEnabled = true
        let level = WKInterfaceDevice.current().batteryLevel
        if level >= 0 { body["battery"] = Int(level * 100) }
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !config.apikey.isEmpty { req.setValue(config.apikey, forHTTPHeaderField: "apikey") }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: req) { [weak self] _, response, _ in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async {
                guard let self = self else { return }
                if ok {
                    WKInterfaceDevice.current().play(.success)
                    self.state = .sent(kind == "sos" ? "Your circle has been alerted" : "Location sent to your circle")
                    self.clearStateSoon(after: 8)
                } else { self.fallback(kind) }
            }
        }.resume()
    }

    // no internet or not linked yet: let the iPhone send it, and offer the emergency number
    private func fallback(_ kind: String) {
        askPhone(kind == "sos" ? "help" : "location")
        WKInterfaceDevice.current().play(.failure)
        state = .failed
    }

    func clearStateSoon(after seconds: Double = 3) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            if case .sent = self?.state { self?.state = .idle }
        }
    }

    // MARK: location
    private func currentLocation(_ done: @escaping (CLLocation?) -> Void) {
        switch location.authorizationStatus {
        case .denied, .restricted: done(nil); return
        case .notDetermined: location.requestWhenInUseAuthorization()
        default: break
        }
        locationWaiters.append(done)
        location.requestLocation()
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in self?.finishLocation(nil) }
    }
    private func finishLocation(_ loc: CLLocation?) {
        let waiters = locationWaiters
        locationWaiters = []
        waiters.forEach { $0(loc) }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) { finishLocation(locations.last) }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if !locationWaiters.isEmpty, manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
    }

    // MARK: fake call
    func scheduleCall() {
        WKInterfaceDevice.current().play(.click)
        state = .sent("Your watch rings in 5 seconds")
        clearStateSoon()
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.ringNow() }
    }
    private func ringNow() {
        incomingCall = true
        WKInterfaceDevice.current().play(.notification)
        ring?.invalidate()
        ring = Timer.scheduledTimer(withTimeInterval: 1.6, repeats: true) { _ in WKInterfaceDevice.current().play(.notification) }
    }
    func acceptCall() {
        ring?.invalidate(); incomingCall = false; inCall = Date()
        let lines = ["Hi, it's me. Where are you right now?", "Okay. I need you to come home now, something's come up.",
                     "I'll explain when you get here. Can you leave right away?", "Good. Stay on the phone with me while you walk."]
        for (i, line) in lines.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1 + Double(i) * 6) { [weak self] in
                guard let self = self, self.inCall != nil else { return }
                let u = AVSpeechUtterance(string: line)
                u.voice = AVSpeechSynthesisVoice(language: "en-US")
                self.voice.speak(u)
            }
        }
    }
    func endCall() {
        ring?.invalidate(); incomingCall = false; inCall = nil
        voice.stopSpeaking(at: .immediate)
    }
}

// MARK: - Views

struct SOSButton: View {
    let action: () -> Void
    @State private var holding = false
    @State private var progress: CGFloat = 0

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Color(red: 1, green: 0.55, blue: 0.71), pink], startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().trim(from: 0, to: 0.92).rotation(.degrees(-73)).stroke(Color.white.opacity(0.45), style: StrokeStyle(lineWidth: 7, lineCap: .round)).padding(16)
            Circle().trim(from: 0, to: progress).rotation(.degrees(-90)).stroke(Color.white, style: StrokeStyle(lineWidth: 7, lineCap: .round)).padding(16)
            Circle().fill(ink).padding(36)
            Text("SOS").font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundColor(.white)
        }
        .frame(width: 118, height: 118)
        .accessibilityLabel("SOS. Press and hold to alert your circle")
        .onLongPressGesture(minimumDuration: 1.5, maximumDistance: 30, perform: {
            progress = 0; holding = false; action()
        }, onPressingChanged: { pressing in
            holding = pressing
            if pressing { WKInterfaceDevice.current().play(.start); withAnimation(.linear(duration: 1.5)) { progress = 1 } }
            else { withAnimation(.easeOut(duration: 0.2)) { progress = 0 } }
        })
    }
}

private func symbol(_ id: String) -> String {
    switch id {
    case "help": return "bell.fill"
    case "location": return "location.fill"
    case "fakecall-now", "fakecall": return "phone.fill"
    case "call": return "staroflife.fill"
    case "siren": return "speaker.wave.3.fill"
    case "walk": return "figure.walk"
    case "timer": return "timer"
    case "plan": return "mappin.and.ellipse"
    case "ride": return "car.fill"
    case "date": return "heart.fill"
    case "record": return "mic.fill"
    default: return "questionmark.circle.fill"
    }
}

struct ContentView: View {
    @EnvironmentObject var store: WatchStore

    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 10) {
                    SOSButton { store.send(kind: "sos") }
                    Text(store.linked ? "Hold to alert your circle" : "Open Shecurity on your iPhone to link this watch")
                        .font(.footnote).multilineTextAlignment(.center).foregroundColor(.secondary)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(Array(store.config.buttons.enumerated()), id: \.offset) { i, b in
                            Button { store.run(b.id) } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: symbol(b.id)).font(.system(size: 18, weight: .bold))
                                    Text(b.label).font(.system(size: 12, weight: .bold, design: .rounded)).lineLimit(2).minimumScaleFactor(0.7)
                                }
                                .frame(maxWidth: .infinity, minHeight: 62)
                                .foregroundColor(i == 0 || i == 3 ? .white : ink)
                                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(i == 0 || i == 3 ? pink : .white))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
            overlay
        }
        .fullScreenCover(isPresented: Binding(get: { store.incomingCall || store.inCall != nil }, set: { if !$0 { store.endCall() } })) {
            CallView().environmentObject(store)
        }
    }

    @ViewBuilder var overlay: some View {
        if let left = store.countdown {
            VStack(spacing: 8) {
                Text("Alerting your circle in").font(.footnote)
                Text("\(left)").font(.system(size: 54, weight: .heavy, design: .rounded))
                Button("Cancel") { store.cancelCountdown() }.tint(.gray)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).background(pink.ignoresSafeArea())
        } else if store.state == .sending {
            VStack(spacing: 8) { ProgressView(); Text("Sending…").font(.headline) }
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(ink.ignoresSafeArea())
        } else if case .sent(let text) = store.state {
            Text(text).font(.headline).multilineTextAlignment(.center).padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(ink.ignoresSafeArea())
                .onTapGesture { store.state = .idle }
        } else if store.state == .failed {
            VStack(spacing: 8) {
                Text("Couldn't reach your circle from the watch. Your iPhone will try.").font(.footnote).multilineTextAlignment(.center)
                Button("Call \(store.config.emergency)") { store.callEmergency() }.tint(pink)
                Button("Close") { store.state = .idle }
            }
            .padding(6).frame(maxWidth: .infinity, maxHeight: .infinity).background(ink.ignoresSafeArea())
        }
    }
}

struct CallView: View {
    @EnvironmentObject var store: WatchStore

    var body: some View {
        VStack(spacing: 10) {
            Text(store.config.caller.isEmpty ? "Mom" : store.config.caller).font(.title3.bold())
            if let start = store.inCall {
                Text(start, style: .timer).font(.footnote).foregroundColor(.secondary)
                Button { store.endCall() } label: { Image(systemName: "phone.down.fill") }.tint(.red)
            } else {
                Text("Mobile").font(.footnote).foregroundColor(.secondary)
                HStack {
                    Button { store.endCall() } label: { Image(systemName: "phone.down.fill") }.tint(.red)
                    Button { store.acceptCall() } label: { Image(systemName: "phone.fill") }.tint(.green)
                }
            }
        }
    }
}

@main
struct ShecurityWatchApp: App {
    @StateObject private var store = WatchStore()
    var body: some Scene {
        WindowGroup { ContentView().environmentObject(store) }
    }
}

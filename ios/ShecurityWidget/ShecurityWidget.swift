import WidgetKit
import SwiftUI

// The four buttons come from the app (You > Your quick buttons) through the shared app group.
private let appGroup = "group.io.github.punselie15.shecurity"
private let pink = Color(red: 0.898, green: 0.282, blue: 0.498)
private let ink = Color(red: 0.165, green: 0.129, blue: 0.322)

struct QuickButton: Codable, Hashable {
    let id: String
    let label: String
    let url: String
}

private func link(_ id: String) -> String { "shecurity://punselie15.github.io/shecurity/app/#q-\(id)" }

private let standardButtons = [
    QuickButton(id: "location", label: "My location", url: link("location")),
    QuickButton(id: "fakecall-now", label: "Call me in 5s", url: link("fakecall-now")),
    QuickButton(id: "help", label: "Send help", url: link("help")),
    QuickButton(id: "call", label: "Call 112", url: link("call"))
]

private func savedButtons() -> [QuickButton] {
    guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: "buttons"),
          let buttons = try? JSONDecoder().decode([QuickButton].self, from: data),
          buttons.count == 4 else { return standardButtons }
    return buttons
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

struct QuickEntry: TimelineEntry {
    let date: Date
    let buttons: [QuickButton]
}

struct QuickProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickEntry { QuickEntry(date: Date(), buttons: standardButtons) }
    func getSnapshot(in context: Context, completion: @escaping (QuickEntry) -> Void) {
        completion(QuickEntry(date: Date(), buttons: context.isPreview ? standardButtons : savedButtons()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickEntry>) -> Void) {
        completion(Timeline(entries: [QuickEntry(date: Date(), buttons: savedButtons())], policy: .never))
    }
}

struct Tile: View {
    let button: QuickButton
    let filled: Bool
    var big = false

    var body: some View {
        VStack(spacing: big ? 10 : 6) {
            Image(systemName: symbol(button.id))
                .font(.system(size: big ? 34 : 22, weight: .bold))
            Text(button.label)
                .font(.system(size: big ? 17 : 14, weight: .bold, design: .rounded))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .multilineTextAlignment(.center)
        }
        .foregroundColor(filled ? .white : ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(filled ? pink : .white))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

struct QuickWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: QuickEntry

    var body: some View {
        let b = entry.buttons
        switch family {
        case .systemSmall:
            Tile(button: b[0], filled: true, big: true)
                .widgetURL(URL(string: b[0].url))
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: symbol(b[0].id)).font(.system(size: 22, weight: .bold))
            }
            .widgetURL(URL(string: b[0].url))
        default:
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow { cell(b[0], true); cell(b[1], false) }
                GridRow { cell(b[2], false); cell(b[3], true) }
            }
        }
    }

    @ViewBuilder func cell(_ button: QuickButton, _ filled: Bool) -> some View {
        if let url = URL(string: button.url) {
            Link(destination: url) { Tile(button: button, filled: filled) }
        } else {
            Tile(button: button, filled: filled)
        }
    }
}

struct ShecurityWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ShecurityQuick", provider: QuickProvider()) { entry in
            QuickWidgetView(entry: entry)
                .containerBackground(for: .widget) { ink }
        }
        .configurationDisplayName("Shecurity quick buttons")
        .description("Your four emergency buttons, one tap away. Change them in Shecurity under You.")
        .supportedFamilies([.systemMedium, .systemLarge, .systemSmall, .accessoryCircular])
    }
}

@main
struct ShecurityWidgetBundle: WidgetBundle {
    var body: some Widget { ShecurityWidget() }
}

import WidgetKit
import SwiftUI

// The four buttons come from the app (You > Your quick buttons) through the shared app group.
private let appGroup = "group.io.github.punselie15.shecurity"
private let pink = Color(red: 0.898, green: 0.282, blue: 0.498)
private let ink = Color(red: 0.165, green: 0.129, blue: 0.322)
private let inkDeep = Color(red: 0.110, green: 0.086, blue: 0.251)
private let inkTop = Color(red: 0.208, green: 0.165, blue: 0.420)
private let pinkLight = Color(red: 1.0, green: 0.478, blue: 0.659)
private let blush = Color(red: 1.0, green: 0.894, blue: 0.933)

struct QuickButton: Codable, Hashable {
    let id: String
    let label: String
    let url: String
}

private func link(_ id: String) -> String { "shecurity://shecurity.app/app/#q-\(id)" }

private let standardButtons = [
    QuickButton(id: "help", label: "Send help", url: link("help")),
    QuickButton(id: "location", label: "My location", url: link("location")),
    QuickButton(id: "fakecall-now", label: "Call me in 5s", url: link("fakecall-now")),
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
    case "lines": return "lifepreserver.fill"
    default: return "questionmark.circle.fill"
    }
}

// one short line under each button, so it's clear what a tap does
private func detail(_ id: String) -> String {
    switch id {
    case "help": return "Alerts your circle"
    case "location": return "Texts where you are"
    case "fakecall-now": return "Your phone rings"
    case "call": return "Emergency services"
    case "siren": return "Loud alarm"
    case "walk": return "Circle follows you"
    case "timer": return "Alert if no check-in"
    case "fakecall": return "Pick when it rings"
    case "plan": return "Tell your circle"
    case "ride": return "Share your ride"
    case "date": return "Date check-ins"
    case "record": return "Saves audio"
    case "lines": return "Free support"
    default: return ""
    }
}

// the actions for a real emergency are pink, the rest white
private func urgent(_ id: String) -> Bool { ["help", "call", "siren"].contains(id) }

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
    var size: CGFloat = 1   // 1 for medium, bigger for small and large

    var body: some View {
        let hot = urgent(button.id)
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: symbol(button.id))
                .font(.system(size: 17 * size, weight: .bold))
                .foregroundStyle(hot ? Color.white : pink)
                .frame(width: 34 * size, height: 34 * size)
                .background(Circle().fill(hot ? Color.white.opacity(0.24) : blush))
            Spacer(minLength: 4)
            Text(button.label)
                .font(.system(size: 16 * size, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(detail(button.id))
                .font(.system(size: 12 * min(size, 1.1), weight: .medium, design: .rounded))
                .opacity(0.7)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(hot ? Color.white : ink)
        .padding(12 * min(size, 1.3))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(hot ? AnyShapeStyle(LinearGradient(colors: [pinkLight, pink], startPoint: .topLeading, endPoint: .bottomTrailing)) : AnyShapeStyle(Color.white))
        )
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
            Tile(button: b[0], size: 1.3)
                .widgetURL(URL(string: b[0].url))
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: symbol(b[0].id)).font(.system(size: 22, weight: .bold))
            }
            .widgetURL(URL(string: b[0].url))
            .accessibilityLabel(b[0].label)
        case .accessoryRectangular:
            HStack(spacing: 8) {
                Image(systemName: symbol(b[0].id)).font(.system(size: 22, weight: .bold))
                VStack(alignment: .leading, spacing: 0) {
                    Text(b[0].label).font(.headline).lineLimit(1)
                    Text("Shecurity").font(.caption).opacity(0.8)
                }
                Spacer(minLength: 0)
            }
            .widgetURL(URL(string: b[0].url))
        case .systemLarge:
            VStack(spacing: 8) {
                HStack(spacing: 7) {
                    Image(systemName: "shield.lefthalf.filled").font(.system(size: 13, weight: .bold)).foregroundStyle(pinkLight)
                    Text("Shecurity").font(.system(size: 15, weight: .bold, design: .rounded))
                    Spacer()
                    Text("One tap does it").font(.system(size: 12, weight: .medium, design: .rounded)).opacity(0.6)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                grid(b, size: 1.25)
                Text("Change these in Shecurity › You")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
            }
        default:
            grid(b, size: 1)
        }
    }

    func grid(_ b: [QuickButton], size: CGFloat) -> some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow { cell(b[0], size); cell(b[1], size) }
            GridRow { cell(b[2], size); cell(b[3], size) }
        }
    }

    @ViewBuilder func cell(_ button: QuickButton, _ size: CGFloat) -> some View {
        if let url = URL(string: button.url) {
            Link(destination: url) { Tile(button: button, size: size) }
        } else {
            Tile(button: button, size: size)
        }
    }
}

struct ShecurityWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ShecurityQuick", provider: QuickProvider()) { entry in
            QuickWidgetView(entry: entry)
                .containerBackground(for: .widget) { LinearGradient(colors: [inkTop, inkDeep], startPoint: .top, endPoint: .bottom) }
        }
        .configurationDisplayName("Shecurity quick buttons")
        .description("Your four safety buttons, one tap away. Pink ones are for emergencies. Change them in Shecurity under You.")
        .supportedFamilies([.systemMedium, .systemLarge, .systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

@main
struct ShecurityWidgetBundle: WidgetBundle {
    var body: some Widget { ShecurityWidget() }
}

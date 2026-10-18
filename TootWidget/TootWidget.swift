import WidgetKit
import SwiftUI
import TootShared

/// No configuration needed — the widget always shows whatever's most
/// prominent in the app right now, the same "open" sticky the home stack
/// leads with. A static, unconfigured provider is the right tool here (see
/// `animate` skill's tool-selection guidance): nothing here is animated or
/// interactive, so there's no gesture/timeline complexity to justify more.
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> StickyEntry {
        StickyEntry(date: Date(), sticky: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (StickyEntry) -> Void) {
        completion(StickyEntry(date: Date(), sticky: WidgetSnapshotStore.read().first ?? .placeholder))
    }

    /// One entry, refreshed on a long fallback interval — the app calls
    /// `WidgetCenter.shared.reloadAllTimelines()` itself on every sticky
    /// change (see `WidgetSnapshotStore.write`), so this timer is just a
    /// safety net in case that notification is ever missed, not the
    /// primary way the widget stays current.
    func getTimeline(in context: Context, completion: @escaping (Timeline<StickyEntry>) -> Void) {
        let sticky = WidgetSnapshotStore.read().first
        let entry = StickyEntry(date: Date(), sticky: sticky)
        let nextRefresh = Calendar.current.date(byAdding: .hour, value: 4, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }
}

struct StickyEntry: TimelineEntry {
    let date: Date
    /// `nil` means genuinely no stickies yet (empty state) — kept distinct
    /// from `.placeholder`, which is redacted widget-gallery filler, not a
    /// real empty state the user would ever see.
    let sticky: StickyData?
}

extension StickyData {
    fileprivate static let placeholder = StickyData(
        id: UUID(), title: "To Do", day: Date(),
        items: [TodoItem(text: "Loading…")],
        colorID: .pink, fontID: .helvetica, frame: .zero, isVisible: true)
}

struct TootWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let sticky = entry.sticky {
            content(for: sticky)
        } else {
            emptyState
        }
    }

    @ViewBuilder
    private func content(for sticky: StickyData) -> some View {
        let color = sticky.colorID
        let visibleItems = sticky.items.filter { !$0.text.isEmpty }
        let itemLimit = family == .systemSmall ? 3 : 6

        VStack(alignment: .leading, spacing: 8) {
            Text(sticky.title.isEmpty ? "To Do" : sticky.title)
                .font(.custom("HelveticaNeue", size: family == .systemSmall ? 18 : 22))
                .tracking(-0.06 * (family == .systemSmall ? 18 : 22))
                .foregroundStyle(color.titleInk)
                .lineLimit(2)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(visibleItems.prefix(itemLimit)) { item in
                    row(item, color: color)
                }
            }

            if visibleItems.count > itemLimit {
                Text("+ \(visibleItems.count - itemLimit) more")
                    .font(.system(size: 11))
                    .foregroundStyle(color.ink.opacity(0.4))
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(color.paper, for: .widget)
    }

    private func row(_ item: TodoItem, color: StickyColor) -> some View {
        HStack(alignment: .top, spacing: 8) {
            ZStack {
                if item.isDone {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(color.ink.opacity(0.3))
                        .frame(width: 12, height: 12)
                    Image(systemName: "checkmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(color.paper)
                } else {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .stroke(color.ink.opacity(0.3), lineWidth: 1)
                        .frame(width: 12, height: 12)
                }
            }
            .padding(.top, 2)
            Text(item.text)
                .font(.system(size: 13))
                .foregroundStyle(item.isDone ? color.inkSecondary : color.ink.opacity(0.85))
                .strikethrough(item.isDone, color: color.inkSecondary)
                .lineLimit(1)
        }
        // Tucked-in rows line up under the text above (12pt box + 8pt gap).
        .padding(.leading, item.isNested ? 20 : 0)
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "note.text")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
            Text("No stickies yet")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(Color(hex: 0xFBF8F1), for: .widget)
    }
}

struct TootWidget: Widget {
    let kind: String = "TootWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            TootWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Tood")
        .description("Shows your top sticky, right on your Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

#Preview(as: .systemSmall) {
    TootWidget()
} timeline: {
    StickyEntry(date: .now, sticky: .placeholder)
}

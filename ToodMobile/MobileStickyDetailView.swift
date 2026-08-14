import SwiftUI
import TootShared

/// Full-screen, editable view of one sticky — opened by tapping a card in
/// the home stack. Every edit funnels straight through `MobileStickyStore`,
/// which persists locally and queues the iCloud upload the same way a Mac
/// edit does.
struct MobileStickyDetailView: View {
    let id: UUID
    @Environment(MobileStickyStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedField: UUID?

    private var data: StickyData? { store.stickies.first { $0.id == id } }

    var body: some View {
        if let data {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(Self.dateFormatter.string(from: data.day))
                        .font(.system(size: 14))
                        .foregroundStyle(data.colorID.ink.opacity(0.35))

                    TextField("To Do", text: titleBinding(data))
                        .font(.custom("HelveticaNeue", size: 36))
                        .tracking(36 * -0.06)
                        .foregroundStyle(data.colorID.titleInk)
                        .textFieldStyle(.plain)

                    VStack(spacing: 0) {
                        ForEach(data.items) { item in
                            row(item, color: data.colorID)
                        }
                    }
                    .padding(.top, 8)

                    Button {
                        store.addItem(id)
                    } label: {
                        Label("Add item", systemImage: "plus")
                            .font(.system(size: 15))
                            .foregroundStyle(data.colorID.ink.opacity(0.5))
                    }
                    .padding(.top, 4)
                }
                .padding(24)
                .padding(.top, 20)
            }
            .background(data.colorID.paper.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        } else {
            // The sticky was deleted (locally, or a remote deletion just
            // synced in) while this view was open — nothing left to show.
            Color.clear.onAppear { dismiss() }
        }
    }

    private func titleBinding(_ data: StickyData) -> Binding<String> {
        Binding(get: { data.title }, set: { store.setTitle(id, $0) })
    }

    @ViewBuilder
    private func row(_ item: TodoItem, color: StickyColor) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Button {
                store.toggleItem(id, item.id)
            } label: {
                ZStack {
                    if item.isDone {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(color.ink.opacity(0.3))
                            .frame(width: 18, height: 18)
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(color.paper)
                    } else {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .stroke(color.ink.opacity(0.3), lineWidth: 1.2)
                            .frame(width: 18, height: 18)
                    }
                }
            }
            .buttonStyle(.plain)

            TextField("", text: textBinding(item))
                .font(.system(size: 17))
                .foregroundStyle(item.isDone ? color.inkSecondary : color.ink.opacity(0.85))
                .strikethrough(item.isDone, color: color.inkSecondary)
                .textFieldStyle(.plain)
                .focused($focusedField, equals: item.id)

            Button {
                store.deleteItem(id, item.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12))
                    .foregroundStyle(color.ink.opacity(0.25))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
        Rectangle()
            .fill(color.divider)
            .frame(height: 1)
    }

    private func textBinding(_ item: TodoItem) -> Binding<String> {
        Binding(get: { item.text }, set: { store.setItemText(id, item.id, $0) })
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f
    }()
}

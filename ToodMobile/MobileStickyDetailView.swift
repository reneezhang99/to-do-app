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
    @State private var showingDeleteConfirmation = false
    @State private var showingColorPicker = false
    @State private var showingFontPicker = false

    /// The five free colors — mirrors the Mac's `colorPicker`, minus the
    /// paid Candy Pack (no purchase/entitlement flow on mobile yet).
    private var freeColors: [StickyColor] { StickyColor.allCases.filter { $0.pack == nil } }

    private var data: StickyData? { store.stickies.first { $0.id == id } }

    var body: some View {
        if let data {
            // Wrapped in its own NavigationStack because this view is
            // presented via `.fullScreenCover`, which doesn't inherit the
            // presenting view's nav bar — without this, `.toolbar` below
            // has nowhere to attach and the Done button silently vanishes,
            // leaving no way back to the stack.
            NavigationStack {
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
                                row(item, color: data.colorID, font: data.fontID)
                            }
                        }
                        .padding(.top, 8)

                        Button {
                            store.addItem(id)
                        } label: {
                            Label("Add item", systemImage: "plus")
                                .font(data.fontID.body(15))
                                .foregroundStyle(data.colorID.ink.opacity(0.5))
                        }
                        .padding(.top, 4)
                    }
                    .padding(24)
                    .padding(.top, 20)
                }
                .background(data.colorID.paper.ignoresSafeArea())
                .safeAreaInset(edge: .bottom) {
                    bottomBar(data)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .foregroundStyle(data.colorID.ink.opacity(0.6))
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .foregroundStyle(data.colorID.ink.opacity(0.6))
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { dismiss() }
                    }
                }
                .confirmationDialog(
                    "Delete this sticky?",
                    isPresented: $showingDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Delete", role: .destructive) {
                        store.deleteSticky(id)
                        dismiss()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This can't be undone.")
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

    /// Color + font controls — the mobile equivalent of the Mac's hover
    /// toolbar in `StickyRootView`, just always-visible since touch has no
    /// hover state to reveal it on.
    private func bottomBar(_ data: StickyData) -> some View {
        HStack(spacing: 18) {
            Button { showingColorPicker = true } label: {
                Image(systemName: "paintpalette")
            }
            .popover(isPresented: $showingColorPicker, arrowEdge: .bottom) {
                colorPicker(data)
                    .presentationCompactAdaptation(.popover)
            }

            Button { showingFontPicker = true } label: {
                Text("Aa").font(.custom("ABCStefanTrial-Simple", size: 15))
            }
            .popover(isPresented: $showingFontPicker, arrowEdge: .bottom) {
                fontPicker(data)
                    .presentationCompactAdaptation(.popover)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(data.colorID.ink.opacity(0.5))
        .buttonStyle(.plain)
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .background(data.colorID.paper.ignoresSafeArea(edges: .bottom))
    }

    private func colorPicker(_ data: StickyData) -> some View {
        HStack(spacing: 10) {
            ForEach(freeColors) { c in
                Button {
                    store.setColor(id, c)
                    showingColorPicker = false
                } label: {
                    Circle()
                        .fill(c.paper)
                        .frame(width: 22, height: 22)
                        .overlay(Circle().stroke(.black.opacity(0.15), lineWidth: 1))
                        .overlay(
                            Circle().stroke(data.colorID.ink, lineWidth: c == data.colorID ? 2 : 0)
                                .padding(-3)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
    }

    private func fontPicker(_ data: StickyData) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(StickyFont.allCases) { f in
                Button {
                    store.setFont(id, f)
                    showingFontPicker = false
                } label: {
                    HStack(spacing: 8) {
                        Text(f.displayName)
                        if f == data.fontID {
                            Spacer(minLength: 12)
                            Image(systemName: "checkmark")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
            }
        }
        .padding(8)
        .foregroundStyle(.primary)
    }

    @ViewBuilder
    private func row(_ item: TodoItem, color: StickyColor, font: StickyFont) -> some View {
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
                .font(font.body(17))
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

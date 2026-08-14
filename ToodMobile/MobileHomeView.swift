import SwiftUI
import TootShared

/// The phone's home screen: every sticky as a full-width card, stacked and
/// overlapped top-to-bottom like a fanned stack of index cards (or Wallet's
/// boarding passes) — the exact "overlapped like books" layout asked for.
/// Tapping a card opens it full-screen to actually read/edit.
struct MobileHomeView: View {
    @Environment(MobileStickyStore.self) private var store
    @State private var selected: UUID?
    @State private var isRefreshing = false

    /// How much of the card behind peeks out above the one in front —
    /// small enough that a full stack of stickies still fits on one
    /// screen without scrolling for a typical day's worth of notes.
    private let peekOffset: CGFloat = 64
    private let cardCornerRadius: CGFloat = 20

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ScrollView {
                    ZStack(alignment: .top) {
                        ForEach(Array(store.stickies.enumerated()), id: \.element.id) { index, sticky in
                            MobileStickyCardView(data: sticky, cornerRadius: cardCornerRadius)
                                .frame(height: max(geo.size.height * 0.68, 420))
                                .offset(y: CGFloat(index) * peekOffset)
                                .zIndex(Double(store.stickies.count - index))
                                .shadow(color: .black.opacity(0.15), radius: 10, y: 6)
                                .onTapGesture { selected = sticky.id }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    // Enough bottom padding that the last card's peek isn't
                    // clipped by the scroll view's own bounds.
                    .padding(.bottom, CGFloat(max(store.stickies.count - 1, 0)) * peekOffset + 40)
                }
                .refreshable {
                    isRefreshing = true
                    await store.refreshFromCloud()
                    isRefreshing = false
                }
            }
            .background(Color(hex: 0xFBF8F1).ignoresSafeArea())
            .navigationTitle("Tood")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { store.newSticky() } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
            .overlay {
                if store.stickies.isEmpty {
                    ContentUnavailableView(
                        "No stickies yet",
                        systemImage: "note.text",
                        description: Text("Tap + to make one, or pull down to sync from your Mac.")
                    )
                }
            }
            .fullScreenCover(item: $selected.animation()) { id in
                if let sticky = store.stickies.first(where: { $0.id == id }) {
                    MobileStickyDetailView(id: sticky.id)
                }
            }
        }
        .task { await store.refreshFromCloud() }
    }
}

extension UUID: Identifiable {
    public var id: UUID { self }
}

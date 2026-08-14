import SwiftUI
import TootShared

@main
struct ToodMobileApp: App {
    @State private var store = MobileStickyStore()

    var body: some Scene {
        WindowGroup {
            MobileHomeView()
                .environment(store)
        }
    }
}

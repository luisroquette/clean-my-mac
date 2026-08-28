import SwiftUI

@main
struct CleanMyMacApp: App {
    @StateObject private var monitor = StorageMonitor()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(monitor: monitor)
        } label: {
            Label(monitor.menuBarTitle, systemImage: monitor.menuBarSymbol)
        }
        .menuBarExtraStyle(.window)
    }
}

import SwiftUI
import AppKit

@main
struct MeetingScribeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 830, idealWidth: 830)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.main, let window = NSApp.windows.first else { return }

        let visibleFrame = screen.visibleFrame
        let width: CGFloat = 830
        let origin = CGPoint(x: visibleFrame.maxX - width, y: visibleFrame.minY)
        let frame = CGRect(origin: origin, size: CGSize(width: width, height: visibleFrame.height))

        window.setFrame(frame, display: true)
    }
}

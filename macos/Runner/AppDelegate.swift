import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    // Flutter rebuilds the menu bar whenever the app's menus change. Tell macOS which one is "Help" each time, so it
    // adds the system search field to it.
    let center = NotificationCenter.default
    for name in [NSMenu.didAddItemNotification, NSMenu.didRemoveItemNotification] {
      center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.markHelpMenu() }
    }
    DispatchQueue.main.async { self.markHelpMenu() }
  }

  private func markHelpMenu() {
    guard let main = NSApp.mainMenu else { return }
    if let help = main.items.first(where: { $0.title == "Help" })?.submenu, NSApp.helpMenu !== help {
      NSApp.helpMenu = help
    }
  }
}

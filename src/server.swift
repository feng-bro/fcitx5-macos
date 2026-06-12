import Cocoa
import FcitxBridge
import InputMethodKit
import SwiftFrontend

class NSManualApplication: NSApplication {
  private let appDelegate = AppDelegate()

  override init() {
    super.init()
    self.delegate = appDelegate
  }

  required init?(coder: NSCoder) {
    fatalError("Unreachable path")
  }
}

// Redirect stderr to /tmp/Fcitx5.log as it's not captured anyway.
private func redirectStderr() {
  let file = fopen("/tmp/Fcitx5.log", "w")
  if let file = file {
    dup2(fileno(file), STDERR_FILENO)
    fclose(file)
  }
}

private func signalHandler(signal: Int32) {
  // The signal can be raised on any thread. So we must make sure it's
  // routed back to the main thread.
  DispatchQueue.main.async {
    if signal == SIGTERM {
      restartProcess()
    }
  }
}

@main
class AppDelegate: NSObject, NSApplicationDelegate {
  static var server: IMKServer!
  static var statusItem: NSStatusItem?
  static var statusItemText: String = "F"
  static var statusItemMode: Int32 = 0

  private static let inputSourceChangedNotification = Notification.Name(
    rawValue: kTISNotifySelectedKeyboardInputSourceChanged as String)

  func applicationDidFinishLaunching(_ notification: Notification) {
    redirectStderr()

    signal(SIGTERM, signalHandler)

    DistributedNotificationCenter.default().addObserver(
      self,
      selector: #selector(inputSourceChanged),
      name: AppDelegate.inputSourceChangedNotification,
      object: nil)

    setStatusItemCallback { mode, text in
      if let mode = mode {
        AppDelegate.statusItemMode = mode
      }
      if let text = text {
        AppDelegate.statusItemText = prefixForStatusItem(text)
      }
      self.refreshStatusItemVisibility()
    }

    AppDelegate.server = IMKServer(
      name: Bundle.main.infoDictionary?["InputMethodConnectionName"] as? String,
      bundleIdentifier: Bundle.main.bundleIdentifier)

    let locale = getLocale()
    fcitx_start(locale)
  }

  func applicationWillTerminate(_ notification: Notification) {
    DistributedNotificationCenter.default().removeObserver(self)
    fcitx_stop()
  }

  private func isFcitxSelectedInputSource() -> Bool {
    guard let inputSource = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
      let property = TISGetInputSourceProperty(inputSource, kTISPropertyBundleID)
    else {
      return false
    }
    let bundleId = Unmanaged<CFString>.fromOpaque(property).takeUnretainedValue() as String
    return bundleId == Bundle.main.bundleIdentifier
  }

  private func removeStatusItem() {
    if let statusItem = AppDelegate.statusItem {
      NSStatusBar.system.removeStatusItem(statusItem)
      AppDelegate.statusItem = nil
    }
  }

  private func ensureStatusItem() -> NSStatusItem {
    if let statusItem = AppDelegate.statusItem {
      return statusItem
    }
    // NSStatusItem.variableLength causes layout shift of icons on the left when switching between en and 拼.
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    AppDelegate.statusItem = statusItem
    return statusItem
  }

  private func makeStatusItemMenu() -> NSMenu {
    let menu = NSMenu()

    let toggle = NSMenuItem(
      title: NSLocalizedString("Toggle input method", comment: ""),
      action: #selector(self.toggle), keyEquivalent: "")
    menu.addItem(toggle)

    menu.addItem(NSMenuItem.separator())

    let hide = NSMenuItem(
      title: NSLocalizedString("Hide", comment: ""),
      action: #selector(self.hide), keyEquivalent: "")
    menu.addItem(hide)

    return menu
  }

  private func refreshStatusItemVisibility() {
    guard AppDelegate.statusItemMode != 0, isFcitxSelectedInputSource() else {
      removeStatusItem()
      return
    }

    let statusItem = ensureStatusItem()
    statusItem.menu = nil

    if let button = statusItem.button {
      button.title = AppDelegate.statusItemText
      button.target = self
      button.action = nil
      if AppDelegate.statusItemMode == 1 {  // Toggle input method
        button.action = #selector(self.toggle)
      } else {  // Menu
        statusItem.menu = makeStatusItemMenu()
      }
    }
  }

  @objc private func inputSourceChanged(_ notification: Notification) {
    refreshStatusItemVisibility()
  }

  @objc func toggle() {
    toggleInputMethod()
  }

  @objc func hide() {
    AppDelegate.statusItemMode = 0
    refreshStatusItemVisibility()
  }
}

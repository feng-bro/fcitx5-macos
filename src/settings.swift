import AppKit
import FcitxBridge
import Logging

private func configString(_ raw: UnsafeMutablePointer<CChar>?) -> String {
  return bridgeString(raw)
}

private func getConfigObject(_ uri: String) -> [String: Any] {
  guard let data = configString(fcitx_config_get_config_c(uri)).data(using: .utf8),
    let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
  else {
    return ["ERROR": "Failed to get config"]
  }
  return json
}

private func setConfigObject(_ uri: String, _ value: Any) -> Bool {
  guard JSONSerialization.isValidJSONObject(value),
    let data = try? JSONSerialization.data(withJSONObject: value),
    let jsonString = String(data: data, encoding: .utf8)
  else {
    FCITX_ERROR("Failed to serialize config value for \(uri)")
    return false
  }
  return fcitx_config_set_config_c(uri, jsonString)
}

private func extractConfigValue(_ config: [String: Any], reset: Bool = false) -> Any {
  if reset, let defaultValue = config["DefaultValue"] {
    return defaultValue
  }
  if !reset, let value = config["Value"] {
    return value
  }
  if let children = config["Children"] as? [[String: Any]] {
    var value = [String: Any]()
    for child in children {
      if let option = child["Option"] as? String {
        value[option] = extractConfigValue(child, reset: reset)
      }
    }
    return value
  }
  return ""
}

private struct SettingsGroup: Codable {
  var name: String
  var layout: String
  var inputMethods: [SettingsGroupItem]
}

private struct SettingsGroupItem: Codable {
  var name: String
  var displayName: String
  var isKeyboard: Bool
  var layout: String
}

private struct SettingsInputMethod: Codable {
  var name: String
  var displayName: String
  var languageCode: String?
  var isKeyboard: Bool
}

private struct AddonCategory: Codable {
  var name: String
  var id: Int
  var addons: [AddonInfo]
}

private struct AddonInfo: Codable {
  var name: String
  var id: String
  var comment: String
}

private final class SimpleConfigEditor: NSView {
  private let uri: String
  private let config: [String: Any]
  private var valueByPath: [String: Any] = [:]
  private var structuredListByPath: [String: Bool] = [:]
  private let content = NSStackView()
  private let statusLabel = NSTextField(labelWithString: "")

  init(uri: String) {
    self.uri = uri
    self.config = getConfigObject(uri)
    super.init(frame: .zero)
    build()
  }

  required init?(coder: NSCoder) {
    fatalError("Unreachable path")
  }

  private func build() {
    translatesAutoresizingMaskIntoConstraints = false

    let outer = NSStackView()
    outer.orientation = .vertical
    outer.spacing = 10
    outer.translatesAutoresizingMaskIntoConstraints = false
    addSubview(outer)
    NSLayoutConstraint.activate([
      outer.leadingAnchor.constraint(equalTo: leadingAnchor),
      outer.trailingAnchor.constraint(equalTo: trailingAnchor),
      outer.topAnchor.constraint(equalTo: topAnchor),
      outer.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])

    content.orientation = .vertical
    content.spacing = 8
    content.alignment = .leading

    if let error = config["ERROR"] as? String {
      statusLabel.stringValue = error
      outer.addArrangedSubview(statusLabel)
      return
    }

    addChildren(config["Children"] as? [[String: Any]] ?? [], path: [], to: content, depth: 0)
    outer.addArrangedSubview(content)

    let footer = NSStackView()
    footer.orientation = .horizontal
    footer.spacing = 8
    footer.alignment = .centerY

    let saveButton = NSButton(title: NSLocalizedString("Save", comment: ""), target: self, action: #selector(save))
    saveButton.bezelStyle = .rounded
    let resetButton = NSButton(title: NSLocalizedString("Reset to default", comment: ""), target: self, action: #selector(resetToDefault))
    resetButton.bezelStyle = .rounded

    statusLabel.textColor = .secondaryLabelColor
    statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    footer.addArrangedSubview(saveButton)
    footer.addArrangedSubview(resetButton)
    footer.addArrangedSubview(statusLabel)
    outer.addArrangedSubview(footer)
  }

  private func addChildren(_ children: [[String: Any]], path: [String], to stack: NSStackView, depth: Int) {
    for child in children {
      guard let option = child["Option"] as? String else {
        continue
      }
      let currentPath = path + [option]
      let type = child["Type"] as? String ?? ""
      let description = child["Description"] as? String ?? option

      if type.isEmpty, let subChildren = child["Children"] as? [[String: Any]] {
        let label = NSTextField(labelWithString: description)
        label.font = depth == 0 ? NSFont.boldSystemFont(ofSize: 13) : NSFont.systemFont(ofSize: 13)
        stack.addArrangedSubview(label)
        let groupStack = NSStackView()
        groupStack.orientation = .vertical
        groupStack.spacing = 6
        groupStack.alignment = .leading
        groupStack.edgeInsets = NSEdgeInsets(top: 0, left: 14, bottom: 4, right: 0)
        stack.addArrangedSubview(groupStack)
        addChildren(subChildren, path: currentPath, to: groupStack, depth: depth + 1)
        continue
      }

      let value = extractConfigValue(child)
      let key = currentPath.joined(separator: ".")
      valueByPath[key] = value

      let row = NSStackView()
      row.orientation = .horizontal
      row.spacing = 10
      row.alignment = .centerY

      let label = NSTextField(labelWithString: description)
      label.frame.size.width = 230
      label.widthAnchor.constraint(equalToConstant: 230).isActive = true
      label.alignment = .right
      label.lineBreakMode = .byTruncatingTail
      if let tooltip = child["Tooltip"] as? String {
        label.toolTip = tooltip
      }

      row.addArrangedSubview(label)
      row.addArrangedSubview(control(for: child, key: key, value: value))
      stack.addArrangedSubview(row)
    }
  }

  private func control(for child: [String: Any], key: String, value: Any) -> NSView {
    let type = child["Type"] as? String ?? ""
    if type == "Boolean" {
      let button = NSButton(checkboxWithTitle: "", target: self, action: #selector(controlChanged(_:)))
      button.state = (value as? String == "True") ? .on : .off
      button.identifier = NSUserInterfaceItemIdentifier(key)
      return button
    }

    if type == "Enum" || child["IsEnum"] as? String == "True" {
      let popup = NSPopUpButton()
      let values = child["Enum"] as? [String: String] ?? [:]
      let labels = child["EnumI18n"] as? [String: String] ?? values
      let orderedKeys = values.keys.compactMap(Int.init).sorted()
      for index in orderedKeys {
        let indexKey = String(index)
        if let optionValue = values[indexKey] {
          popup.addItem(withTitle: labels[indexKey] ?? optionValue)
          popup.lastItem?.representedObject = optionValue
        }
      }
      let current = value as? String ?? ""
      if let item = popup.itemArray.first(where: { $0.representedObject as? String == current }) {
        popup.select(item)
      }
      popup.target = self
      popup.action = #selector(controlChanged(_:))
      popup.identifier = NSUserInterfaceItemIdentifier(key)
      return popup
    }

    if type.hasPrefix("List|") {
      structuredListByPath[key] = type.hasPrefix("List|Entries")
      let textView = NSTextView()
      textView.minSize = NSSize(width: 360, height: 70)
      textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
      textView.isVerticallyResizable = true
      textView.isHorizontallyResizable = false
      textView.autoresizingMask = [.width]
      textView.string = listValueToText(value)
      textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
      textView.identifier = NSUserInterfaceItemIdentifier(key)
      let scroll = NSScrollView()
      scroll.borderType = .bezelBorder
      scroll.hasVerticalScroller = true
      scroll.documentView = textView
      scroll.heightAnchor.constraint(equalToConstant: 90).isActive = true
      scroll.widthAnchor.constraint(equalToConstant: 390).isActive = true
      return scroll
    }

    let field = NSTextField(string: value as? String ?? "")
    field.target = self
    field.action = #selector(controlChanged(_:))
    field.identifier = NSUserInterfaceItemIdentifier(key)
    field.widthAnchor.constraint(equalToConstant: 260).isActive = true
    return field
  }

  private func listValueToText(_ value: Any) -> String {
    guard let dict = value as? [String: Any] else {
      return ""
    }
    return dict.keys.compactMap(Int.init).sorted().map { index in
      let item = dict[String(index)] ?? ""
      if let string = item as? String {
        return string
      }
      if JSONSerialization.isValidJSONObject(item),
        let data = try? JSONSerialization.data(withJSONObject: item),
        let json = String(data: data, encoding: .utf8)
      {
        return json
      }
      return "\(item)"
    }.joined(separator: "\n")
  }

  private func collectValues(from view: NSView) {
    for subview in view.subviews {
      if let control = subview as? NSControl,
        let key = control.identifier?.rawValue
      {
        if let popup = control as? NSPopUpButton {
          valueByPath[key] = popup.selectedItem?.representedObject as? String ?? ""
        } else if let checkbox = control as? NSButton {
          valueByPath[key] = checkbox.state == .on ? "True" : "False"
        } else if let text = control as? NSTextField {
          valueByPath[key] = text.stringValue
        }
      }
      if let textView = subview as? NSTextView,
        let key = textView.identifier?.rawValue
      {
        valueByPath[key] = textToListValue(textView.string, structured: structuredListByPath[key] ?? false)
      }
      collectValues(from: subview)
    }
  }

  private func textToListValue(_ text: String, structured: Bool) -> [String: Any] {
    var result = [String: Any]()
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    for (index, line) in lines.enumerated() {
      let string = String(line)
      if string.isEmpty {
        continue
      }
      if structured,
        let data = string.data(using: .utf8),
        let json = try? JSONSerialization.jsonObject(with: data)
      {
        result[String(index)] = json
      } else {
        result[String(index)] = string
      }
    }
    return result
  }

  private func nestedPatch() -> [String: Any] {
    collectValues(from: self)
    var root = [String: Any]()
    for (key, value) in valueByPath {
      let path = key.split(separator: ".").map(String.init)
      var current = root
      insert(value, path: path, into: &current)
      root = current
    }
    return root
  }

  private func insert(_ value: Any, path: [String], into dict: inout [String: Any]) {
    guard let first = path.first else {
      return
    }
    if path.count == 1 {
      dict[first] = value
      return
    }
    var child = dict[first] as? [String: Any] ?? [:]
    insert(value, path: Array(path.dropFirst()), into: &child)
    dict[first] = child
  }

  @objc private func controlChanged(_ sender: Any?) {
    statusLabel.stringValue = NSLocalizedString("Save", comment: "")
  }

  @objc private func save() {
    if setConfigObject(uri, nestedPatch()) {
      statusLabel.stringValue = NSLocalizedString("Saved", comment: "")
      fcitx_reload()
    } else {
      statusLabel.stringValue = NSLocalizedString("Failed to save", comment: "")
    }
  }

  @objc private func resetToDefault() {
    if setConfigObject(uri, extractConfigValue(config, reset: true)) {
      statusLabel.stringValue = NSLocalizedString("Reset to default", comment: "")
      fcitx_reload()
    } else {
      statusLabel.stringValue = NSLocalizedString("Failed to save", comment: "")
    }
  }
}

public final class CatalinaSettingsWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
  public static let shared = CatalinaSettingsWindowController()

  private enum Page: Int, CaseIterable {
    case inputMethods
    case global
    case macosFrontend
    case addons
    case about

    var title: String {
      switch self {
      case .inputMethods: return NSLocalizedString("Input Methods", comment: "")
      case .global: return NSLocalizedString("Global Config", comment: "")
      case .macosFrontend: return NSLocalizedString("macOS Frontend", comment: "")
      case .addons: return NSLocalizedString("Addon Config", comment: "")
      case .about: return NSLocalizedString("About Fcitx5 macOS", comment: "")
      }
    }
  }

  private let splitView = NSSplitView()
  private let sidebar = NSTableView()
  private let sidebarScroll = NSScrollView()
  private let detail = NSView()
  private var groups: [SettingsGroup] = []
  private var availableInputMethods: [SettingsInputMethod] = []

  private init() {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 880, height: 620),
      styleMask: [.titled, .closable, .resizable],
      backing: .buffered,
      defer: false)
    window.title = NSLocalizedString("Fcitx5 macOS", comment: "")
    super.init(window: window)
    window.delegate = self
    window.center()
    buildWindow()
  }

  required init?(coder: NSCoder) {
    fatalError("Unreachable path")
  }

  public static func open() {
    let controller = CatalinaSettingsWindowController.shared
    if NSApp.activationPolicy() != .regular {
      NSApp.setActivationPolicy(.regular)
    }
    controller.showWindow(nil)
    controller.window?.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  public func windowShouldClose(_ sender: NSWindow) -> Bool {
    sender.orderOut(nil)
    NSApp.setActivationPolicy(.prohibited)
    return false
  }

  private func buildWindow() {
    guard let contentView = window?.contentView else {
      return
    }
    splitView.isVertical = true
    splitView.dividerStyle = .thin
    splitView.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(splitView)
    NSLayoutConstraint.activate([
      splitView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      splitView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      splitView.topAnchor.constraint(equalTo: contentView.topAnchor),
      splitView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
    ])

    sidebar.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("page")))
    sidebar.headerView = nil
    sidebar.dataSource = self
    sidebar.delegate = self
    sidebar.rowHeight = 34
    sidebar.selectionHighlightStyle = .regular
    sidebarScroll.documentView = sidebar
    sidebarScroll.hasVerticalScroller = false
    sidebarScroll.translatesAutoresizingMaskIntoConstraints = false

    detail.translatesAutoresizingMaskIntoConstraints = false
    splitView.addArrangedSubview(sidebarScroll)
    splitView.addArrangedSubview(detail)
    sidebarScroll.widthAnchor.constraint(equalToConstant: 190).isActive = true
    sidebar.selectRowIndexes(IndexSet(integer: Page.inputMethods.rawValue), byExtendingSelection: false)
    show(page: .inputMethods)
  }

  public func numberOfRows(in tableView: NSTableView) -> Int {
    return Page.allCases.count
  }

  public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let cell = NSTableCellView()
    let label = NSTextField(labelWithString: Page(rawValue: row)?.title ?? "")
    label.translatesAutoresizingMaskIntoConstraints = false
    cell.addSubview(label)
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
      label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
      label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
    ])
    return cell
  }

  public func tableViewSelectionDidChange(_ notification: Notification) {
    guard let page = Page(rawValue: sidebar.selectedRow) else {
      return
    }
    show(page: page)
  }

  private func show(page: Page) {
    for subview in detail.subviews {
      subview.removeFromSuperview()
    }
    window?.title = page.title
    let view: NSView
    switch page {
    case .inputMethods:
      view = inputMethodPage()
    case .global:
      view = scrollPage(SimpleConfigEditor(uri: "fcitx://config/global"))
    case .macosFrontend:
      view = scrollPage(SimpleConfigEditor(uri: "fcitx://config/addon/macosfrontend"))
    case .addons:
      view = addonsPage()
    case .about:
      view = aboutPage()
    }
    view.translatesAutoresizingMaskIntoConstraints = false
    detail.addSubview(view)
    NSLayoutConstraint.activate([
      view.leadingAnchor.constraint(equalTo: detail.leadingAnchor),
      view.trailingAnchor.constraint(equalTo: detail.trailingAnchor),
      view.topAnchor.constraint(equalTo: detail.topAnchor),
      view.bottomAnchor.constraint(equalTo: detail.bottomAnchor),
    ])
  }

  private func scrollPage(_ content: NSView) -> NSView {
    let scroll = NSScrollView()
    scroll.hasVerticalScroller = true
    scroll.borderType = .noBorder
    let document = NSView()
    document.translatesAutoresizingMaskIntoConstraints = false
    content.translatesAutoresizingMaskIntoConstraints = false
    document.addSubview(content)
    NSLayoutConstraint.activate([
      content.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 18),
      content.trailingAnchor.constraint(lessThanOrEqualTo: document.trailingAnchor, constant: -18),
      content.topAnchor.constraint(equalTo: document.topAnchor, constant: 18),
      content.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -18),
      content.widthAnchor.constraint(lessThanOrEqualToConstant: 620),
    ])
    scroll.documentView = document
    document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor).isActive = true
    return scroll
  }

  private func inputMethodPage() -> NSView {
    loadInputMethods()

    let root = NSStackView()
    root.orientation = .vertical
    root.spacing = 12
    root.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)

    let header = NSTextField(labelWithString: NSLocalizedString("Input Methods", comment: ""))
    header.font = NSFont.boldSystemFont(ofSize: 16)
    root.addArrangedSubview(header)

    for groupIndex in groups.indices {
      root.addArrangedSubview(groupView(index: groupIndex))
    }

    let actions = NSStackView()
    actions.orientation = .horizontal
    actions.spacing = 8
    let addGroupButton = NSButton(title: NSLocalizedString("Add group", comment: ""), target: self, action: #selector(addGroup))
    let save = NSButton(title: NSLocalizedString("Save", comment: ""), target: self, action: #selector(saveGroups))
    let reload = NSButton(title: NSLocalizedString("Reload", comment: ""), target: self, action: #selector(reloadCurrentPage))
    actions.addArrangedSubview(addGroupButton)
    actions.addArrangedSubview(save)
    actions.addArrangedSubview(reload)
    root.addArrangedSubview(actions)

    return scrollPage(root)
  }

  private func groupView(index: Int) -> NSView {
    let group = groups[index]
    let box = NSBox()
    box.title = group.name
    box.translatesAutoresizingMaskIntoConstraints = false
    let stack = NSStackView()
    stack.orientation = .vertical
    stack.spacing = 6
    stack.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
    stack.translatesAutoresizingMaskIntoConstraints = false
    box.contentView?.addSubview(stack)
    if let contentView = box.contentView {
      NSLayoutConstraint.activate([
        stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
        stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        stack.topAnchor.constraint(equalTo: contentView.topAnchor),
        stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
      ])
    }

    let layoutRow = NSStackView()
    layoutRow.orientation = .horizontal
    layoutRow.spacing = 8
    layoutRow.alignment = .centerY
    layoutRow.addArrangedSubview(NSTextField(labelWithString: NSLocalizedString("Default", comment: "")))
    let layout = NSTextField(string: group.layout)
    layout.identifier = NSUserInterfaceItemIdentifier("group-layout-\(index)")
    layout.widthAnchor.constraint(equalToConstant: 120).isActive = true
    layoutRow.addArrangedSubview(layout)
    let remove = NSButton(title: NSLocalizedString("Remove", comment: ""), target: self, action: #selector(removeGroup(_:)))
    remove.tag = index
    remove.isEnabled = groups.count > 1
    layoutRow.addArrangedSubview(remove)
    stack.addArrangedSubview(layoutRow)

    for itemIndex in group.inputMethods.indices {
      let item = group.inputMethods[itemIndex]
      let row = NSStackView()
      row.orientation = .horizontal
      row.spacing = 8
      row.alignment = .centerY
      let label = NSTextField(labelWithString: item.displayName)
      label.widthAnchor.constraint(equalToConstant: 250).isActive = true
      row.addArrangedSubview(label)
      let imLayout = NSTextField(string: item.layout)
      imLayout.placeholderString = group.layout
      imLayout.identifier = NSUserInterfaceItemIdentifier("im-layout-\(index)-\(itemIndex)")
      imLayout.widthAnchor.constraint(equalToConstant: 120).isActive = true
      row.addArrangedSubview(imLayout)
      let up = NSButton(title: "Up", target: self, action: #selector(moveInputMethodUp(_:)))
      up.tag = index * 1000 + itemIndex
      up.isEnabled = itemIndex > 0
      row.addArrangedSubview(up)
      let down = NSButton(title: "Down", target: self, action: #selector(moveInputMethodDown(_:)))
      down.tag = index * 1000 + itemIndex
      down.isEnabled = itemIndex + 1 < group.inputMethods.count
      row.addArrangedSubview(down)
      let remove = NSButton(title: NSLocalizedString("Remove", comment: ""), target: self, action: #selector(removeInputMethod(_:)))
      remove.tag = index * 1000 + itemIndex
      row.addArrangedSubview(remove)
      stack.addArrangedSubview(row)
    }

    let addRow = NSStackView()
    addRow.orientation = .horizontal
    addRow.spacing = 8
    let popup = NSPopUpButton()
    popup.identifier = NSUserInterfaceItemIdentifier("add-im-\(index)")
    for im in availableInputMethods {
      popup.addItem(withTitle: im.displayName)
      popup.lastItem?.representedObject = im.name
    }
    popup.widthAnchor.constraint(equalToConstant: 260).isActive = true
    addRow.addArrangedSubview(popup)
    let add = NSButton(title: NSLocalizedString("Add", comment: ""), target: self, action: #selector(addInputMethod(_:)))
    add.tag = index
    addRow.addArrangedSubview(add)
    stack.addArrangedSubview(addRow)
    return box
  }

  private func loadInputMethods() {
    groups = decodeJSON(configString(fcitx_im_get_groups_c()), [SettingsGroup]())
    availableInputMethods = decodeJSON(configString(fcitx_im_get_available_ims_c()), [SettingsInputMethod]())
  }

  private func collectGroupLayouts(from view: NSView) {
    for subview in view.subviews {
      if let field = subview as? NSTextField,
        let identifier = field.identifier?.rawValue
      {
        let parts = identifier.split(separator: "-")
        if parts.count == 3, parts[0] == "group", parts[1] == "layout",
          let groupIndex = Int(parts[2]), groups.indices.contains(groupIndex)
        {
          groups[groupIndex].layout = field.stringValue
        } else if parts.count == 4, parts[0] == "im", parts[1] == "layout",
          let groupIndex = Int(parts[2]), let itemIndex = Int(parts[3]),
          groups.indices.contains(groupIndex),
          groups[groupIndex].inputMethods.indices.contains(itemIndex)
        {
          groups[groupIndex].inputMethods[itemIndex].layout = field.stringValue
        }
      }
      collectGroupLayouts(from: subview)
    }
  }

  @objc private func saveGroups() {
    collectGroupLayouts(from: detail)
    guard let data = try? JSONEncoder().encode(groups),
      let json = String(data: data, encoding: .utf8)
    else {
      return
    }
    fcitx_im_set_groups_c(json)
    fcitx_reload()
    reloadCurrentPage()
  }

  @objc private func reloadCurrentPage() {
    guard let page = Page(rawValue: sidebar.selectedRow) else {
      return
    }
    show(page: page)
  }

  @objc private func addGroup() {
    let alert = NSAlert()
    alert.messageText = NSLocalizedString("Add group", comment: "")
    alert.informativeText = NSLocalizedString("Group name", comment: "")
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
    alert.accessoryView = field
    alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
    alert.addButton(withTitle: NSLocalizedString("Cancel", comment: ""))
    if alert.runModal() == .alertFirstButtonReturn, !field.stringValue.isEmpty {
      groups.append(SettingsGroup(name: field.stringValue, layout: "us", inputMethods: []))
      saveGroups()
    }
  }

  @objc private func removeGroup(_ sender: NSButton) {
    if groups.indices.contains(sender.tag), groups.count > 1 {
      groups.remove(at: sender.tag)
      saveGroups()
    }
  }

  @objc private func addInputMethod(_ sender: NSButton) {
    let groupIndex = sender.tag
    guard groups.indices.contains(groupIndex),
      let popup = findPopup(identifier: "add-im-\(groupIndex)", in: detail),
      let imName = popup.selectedItem?.representedObject as? String,
      let im = availableInputMethods.first(where: { $0.name == imName })
    else {
      return
    }
    groups[groupIndex].inputMethods.append(
      SettingsGroupItem(name: im.name, displayName: im.displayName, isKeyboard: im.isKeyboard, layout: ""))
    saveGroups()
  }

  private func findPopup(identifier: String, in view: NSView) -> NSPopUpButton? {
    for subview in view.subviews {
      if let popup = subview as? NSPopUpButton, popup.identifier?.rawValue == identifier {
        return popup
      }
      if let found = findPopup(identifier: identifier, in: subview) {
        return found
      }
    }
    return nil
  }

  @objc private func removeInputMethod(_ sender: NSButton) {
    let groupIndex = sender.tag / 1000
    let itemIndex = sender.tag % 1000
    if groups.indices.contains(groupIndex), groups[groupIndex].inputMethods.indices.contains(itemIndex) {
      groups[groupIndex].inputMethods.remove(at: itemIndex)
      saveGroups()
    }
  }

  @objc private func moveInputMethodUp(_ sender: NSButton) {
    let groupIndex = sender.tag / 1000
    let itemIndex = sender.tag % 1000
    if groups.indices.contains(groupIndex), itemIndex > 0,
      groups[groupIndex].inputMethods.indices.contains(itemIndex)
    {
      groups[groupIndex].inputMethods.swapAt(itemIndex, itemIndex - 1)
      saveGroups()
    }
  }

  @objc private func moveInputMethodDown(_ sender: NSButton) {
    let groupIndex = sender.tag / 1000
    let itemIndex = sender.tag % 1000
    if groups.indices.contains(groupIndex), groups[groupIndex].inputMethods.indices.contains(itemIndex),
      groups[groupIndex].inputMethods.indices.contains(itemIndex + 1)
    {
      groups[groupIndex].inputMethods.swapAt(itemIndex, itemIndex + 1)
      saveGroups()
    }
  }

  private func addonsPage() -> NSView {
    let root = NSStackView()
    root.orientation = .vertical
    root.spacing = 10
    root.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)

    let categories = decodeJSON(configString(fcitx_get_addons_c()), [AddonCategory]())
    if categories.isEmpty {
      root.addArrangedSubview(NSTextField(labelWithString: NSLocalizedString("Unsupported config", comment: "")))
      return scrollPage(root)
    }
    for category in categories {
      let title = NSTextField(labelWithString: category.name)
      title.font = NSFont.boldSystemFont(ofSize: 13)
      root.addArrangedSubview(title)
      for addon in category.addons {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        let name = NSTextField(labelWithString: addon.name)
        name.widthAnchor.constraint(equalToConstant: 260).isActive = true
        name.toolTip = addon.comment
        row.addArrangedSubview(name)
        let button = NSButton(title: NSLocalizedString("Config", comment: ""), target: self, action: #selector(openAddonConfig(_:)))
        button.identifier = NSUserInterfaceItemIdentifier(addon.id)
        row.addArrangedSubview(button)
        root.addArrangedSubview(row)
      }
    }
    return scrollPage(root)
  }

  @objc private func openAddonConfig(_ sender: NSButton) {
    guard let addon = sender.identifier?.rawValue else {
      return
    }
    showTemporaryConfig(title: sender.title, uri: "fcitx://config/addon/\(addon)")
  }

  private func showTemporaryConfig(title: String, uri: String) {
    for subview in detail.subviews {
      subview.removeFromSuperview()
    }
    let root = NSStackView()
    root.orientation = .vertical
    root.spacing = 8
    root.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
    let back = NSButton(title: NSLocalizedString("Close", comment: ""), target: self, action: #selector(reloadCurrentPage))
    root.addArrangedSubview(back)
    root.addArrangedSubview(scrollPage(SimpleConfigEditor(uri: uri)))
    root.translatesAutoresizingMaskIntoConstraints = false
    detail.addSubview(root)
    NSLayoutConstraint.activate([
      root.leadingAnchor.constraint(equalTo: detail.leadingAnchor),
      root.trailingAnchor.constraint(equalTo: detail.trailingAnchor),
      root.topAnchor.constraint(equalTo: detail.topAnchor),
      root.bottomAnchor.constraint(equalTo: detail.bottomAnchor),
    ])
  }

  private func aboutPage() -> NSView {
    let root = NSStackView()
    root.orientation = .vertical
    root.spacing = 10
    root.alignment = .leading
    root.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
    let title = NSTextField(labelWithString: "Fcitx5 macOS")
    title.font = NSFont.boldSystemFont(ofSize: 22)
    root.addArrangedSubview(title)
    if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
      root.addArrangedSubview(NSTextField(labelWithString: "Version \(version)"))
    }
    root.addArrangedSubview(NSTextField(labelWithString: "Catalina compatibility build"))
    let restart = NSButton(title: NSLocalizedString("Restart", comment: ""), target: self, action: #selector(restartApp))
    root.addArrangedSubview(restart)
    return root
  }

  @objc private func restartApp() {
    restartProcess()
  }
}

extension FcitxInputController {
  @objc func openSettings(_: Any? = nil) {
    CatalinaSettingsWindowController.open()
  }
}

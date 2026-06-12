import AppKit
import FcitxBridge
import Logging

public func keyToUnicode(_ key: String) -> UInt32 {
  if key.isEmpty {
    return 0
  }
  let usv = key.unicodeScalars
  return usv[usv.startIndex].value
}

public func decodeJSON<T: Decodable>(_ s: String, _ defaultValue: T) -> T {
  guard let data = s.data(using: .utf8),
    let decoded = try? JSONDecoder().decode(T.self, from: data)
  else {
    return defaultValue
  }
  return decoded
}

func bridgeString(_ raw: UnsafeMutablePointer<CChar>?) -> String {
  guard let raw = raw else {
    return ""
  }
  let result = String(cString: raw)
  fcitx_free_string(raw)
  return result
}

func nsColorToString(_ color: NSColor) -> String? {
  guard let rgbColor = color.usingColorSpace(.sRGB) else {
    return nil
  }
  let red = UInt8(round(rgbColor.redComponent * 255.0))
  let green = UInt8(round(rgbColor.greenComponent * 255.0))
  let blue = UInt8(round(rgbColor.blueComponent * 255.0))
  let alpha = UInt8(round(rgbColor.alphaComponent * 255.0))
  return String(format: "#%02X%02X%02X%02X", red, green, blue, alpha)
}

private var colorMap = [String: String]()

public func getAccentColor(_ id: String) -> String {
  if let cachedColor = colorMap[id] {
    return cachedColor
  }
  if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id),
    let bundle = Bundle(url: url),
    let info = bundle.infoDictionary,
    let name = info["NSAccentColorName"] as? String,
    let color = NSColor(named: NSColor.Name(name), bundle: bundle),
    let string = nsColorToString(color)
  {
    colorMap[id] = string
    return string
  }
  colorMap[id] = ""
  return ""
}

public func restartProcess() {
  NSApp.terminate(nil)
}

public struct InputMethod: Codable, Hashable {
  let name: String
  let displayName: String
  let languageCode: String?
  let isKeyboard: Bool
}

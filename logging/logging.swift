import Darwin

public func FCITX_DEBUG(_ message: String) {
  if isDebug {
    fputs(message + "\n", stderr)
  }
}

public func FCITX_INFO(_ message: String) {
  fputs(message + "\n", stderr)
}

public func FCITX_WARN(_ message: String) {
  fputs(message + "\n", stderr)
}

public func FCITX_ERROR(_ message: String) {
  fputs(message + "\n", stderr)
}

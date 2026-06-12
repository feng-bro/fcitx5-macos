import Carbon

let arguments = CommandLine.arguments

if arguments.count < 2 {
  exit(1)
}

let im = arguments[1]

func inputSources(matching property: CFString, value: String) -> [TISInputSource] {
  let conditions = NSMutableDictionary()
  conditions.setValue(value, forKey: property as String)
  return TISCreateInputSourceList(conditions, true)?.takeRetainedValue()
    as? [TISInputSource] ?? []
}

func propertyString(_ inputSource: TISInputSource, _ property: CFString) -> String {
  guard let value = TISGetInputSourceProperty(inputSource, property) else {
    return ""
  }
  return Unmanaged<AnyObject>.fromOpaque(value).takeUnretainedValue() as? String ?? ""
}

func enable(_ inputSource: TISInputSource) -> OSStatus {
  let status = TISEnableInputSource(inputSource)
  return status == noErr ? noErr : status
}

let matches = inputSources(matching: kTISPropertyInputSourceID, value: im)
if matches.isEmpty {
  exit(2)
}

for inputSource in matches {
  let bundle = propertyString(inputSource, kTISPropertyBundleID)
  if !bundle.isEmpty {
    for parent in inputSources(matching: kTISPropertyInputSourceID, value: bundle) {
      let status = enable(parent)
      if status != noErr {
        exit(3)
      }
    }
  }

  let enableStatus = enable(inputSource)
  if enableStatus != noErr {
    exit(4)
  }

  let selectStatus = TISSelectInputSource(inputSource)
  if selectStatus == noErr {
    exit(0)
  }
}

exit(5)

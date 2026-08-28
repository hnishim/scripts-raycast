import Foundation
import AppKit

let args = CommandLine.arguments
guard args.count == 3, ["snapshot", "restore"].contains(args[1]) else { exit(2) }
let mode = args[1]
let directory = URL(fileURLWithPath: args[2], isDirectory: true)
let pasteboard = NSPasteboard.general
func fail() -> Never { exit(1) }
if mode == "snapshot" {
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let items = pasteboard.pasteboardItems ?? []
    var manifest: [[String: Any]] = []
    for (index, item) in items.enumerated() {
        var types: [String] = []
        for type in item.types {
            guard let data = item.data(forType: type) else { fail() }
            let filename = "\(index)_\(types.count).data"
            guard (try? data.write(to: directory.appendingPathComponent(filename), options: .atomic)) != nil else { fail() }
            types.append(type.rawValue)
        }
        manifest.append(["types": types])
    }
    guard let json = try? JSONSerialization.data(withJSONObject: manifest) else { fail() }
    guard (try? json.write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)) != nil else { fail() }
} else {
    guard let json = try? Data(contentsOf: directory.appendingPathComponent("manifest.json")),
          let manifest = try? JSONSerialization.jsonObject(with: json) as? [[String: Any]] else { fail() }
    pasteboard.clearContents()
    for (index, entry) in manifest.enumerated() {
        guard let types = entry["types"] as? [String] else { fail() }
        let item = NSPasteboardItem()
        for (typeIndex, rawType) in types.enumerated() {
            guard let data = try? Data(contentsOf: directory.appendingPathComponent("\(index)_\(typeIndex).data")) else { fail() }
            item.setData(data, forType: NSPasteboard.PasteboardType(rawValue: rawType))
        }
        guard pasteboard.writeObjects([item]) else { fail() }
    }
}

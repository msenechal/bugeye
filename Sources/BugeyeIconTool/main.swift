import Foundation

// Usage: BugeyeIconTool <output-folder>
// Writes <output-folder>/Bugeye.iconset/*.png (for iconutil) and MenuBarIcon.png / MenuBarIcon@2x.png.
let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: BugeyeIconTool <output-folder>\n".utf8))
    exit(2)
}
let output = URL(fileURLWithPath: arguments[1], isDirectory: true)
let iconset = output.appendingPathComponent("Bugeye.iconset", isDirectory: true)
do {
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    for (name, pixels) in IconRenderer.iconsetFiles {
        try IconRenderer.png(side: pixels, glyph: false).write(to: iconset.appendingPathComponent(name))
    }
    for (name, pixels) in IconRenderer.glyphFiles {
        try IconRenderer.png(side: pixels, glyph: true).write(to: output.appendingPathComponent(name))
    }
    print("Wrote \(iconset.path) and the menu-bar glyph")
} catch {
    FileHandle.standardError.write(Data("BugeyeIconTool: \(error)\n".utf8))
    exit(1)
}

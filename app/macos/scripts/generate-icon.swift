#!/usr/bin/env swift
// Renders the octopus emoji to all required .iconset PNG sizes.
// Usage: swift generate-icon.swift <output-iconset-dir>

import Cocoa

let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

guard CommandLine.arguments.count > 1 else {
    fputs("Usage: generate-icon.swift <output-iconset-dir>\n", stderr)
    exit(1)
}

let outDir = CommandLine.arguments[1]

for (size, name) in sizes {
    let s = CGFloat(size)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: s * 0.85)
    ]
    let str = NSAttributedString(string: "\u{1F419}", attributes: attrs)
    let strSize = str.size()
    let origin = NSPoint(x: (s - strSize.width) / 2, y: (s - strSize.height) / 2)
    str.draw(at: origin)
    img.unlockFocus()

    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        fputs("Failed to render \(name)\n", stderr)
        continue
    }
    try! png.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
}

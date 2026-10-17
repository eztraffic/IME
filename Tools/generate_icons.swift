import AppKit

func renderBopomofoBadge(pointSize: CGFloat, scale: CGFloat) -> NSImage {
    let pixelSize = pointSize * scale
    let image = NSImage(size: NSSize(width: pixelSize, height: pixelSize))
    image.lockFocus()

    let padding: CGFloat = 2.0 * scale
    let badgeRect = NSRect(
        x: padding,
        y: padding,
        width: pixelSize - padding * 2,
        height: pixelSize - padding * 2
    )

    // Rounded rectangle badge background (similar to macOS system menu badge)
    let cornerRadius = 4.0 * scale
    let path = NSBezierPath(roundedRect: badgeRect, xRadius: cornerRadius, yRadius: cornerRadius)
    NSColor(white: 0.90, alpha: 1.0).setFill()
    path.fill()

    // Draw dark border line
    NSColor(white: 0.75, alpha: 0.8).setStroke()
    path.lineWidth = 1.0 * scale
    path.stroke()

    // Draw "好" character centered
    let text = "好"
    let fontSize = (pointSize * 0.65) * scale
    let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.alignment = .center

    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(white: 0.12, alpha: 1.0),
        .paragraphStyle: paragraphStyle
    ]
    let str = NSAttributedString(string: text, attributes: attrs)
    let strSize = str.size()
    let textRect = NSRect(
        x: (pixelSize - strSize.width) / 2.0,
        y: (pixelSize - strSize.height) / 2.0 - (0.5 * scale),
        width: strSize.width,
        height: strSize.height
    )
    str.draw(in: textRect)

    image.unlockFocus()
    return image
}

func renderMenuIcon(scale: CGFloat) -> NSImage {
    let pointSize: CGFloat = 16.0
    let pixelSize = pointSize * scale
    let image = NSImage(size: NSSize(width: pixelSize, height: pixelSize))
    image.lockFocus()

    // Transparent background, draw regular-weight "好" character centered for macOS template menu bar icon
    let text = "好"
    let fontSize = 13.0 * scale
    let font = NSFont.systemFont(ofSize: fontSize, weight: .regular)
    let paragraphStyle = NSMutableParagraphStyle()
    paragraphStyle.alignment = .center

    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.black,
        .paragraphStyle: paragraphStyle
    ]
    let str = NSAttributedString(string: text, attributes: attrs)
    let strSize = str.size()
    let textRect = NSRect(
        x: (pixelSize - strSize.width) / 2.0,
        y: (pixelSize - strSize.height) / 2.0 - (0.5 * scale),
        width: strSize.width,
        height: strSize.height
    )
    str.draw(in: textRect)

    image.unlockFocus()
    image.isTemplate = true
    return image
}

func generateMenuIcons(outputDir: String) throws {
    let fileManager = FileManager.default
    try fileManager.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

    let img1x = renderMenuIcon(scale: 1.0)
    let img2x = renderMenuIcon(scale: 2.0)

    // Save TIFF multi-representation
    let finalTiff = NSImage(size: NSSize(width: 16, height: 16))
    if let rep1 = NSBitmapImageRep(data: img1x.tiffRepresentation!) {
        rep1.size = NSSize(width: 16, height: 16)
        finalTiff.addRepresentation(rep1)
    }
    if let rep2 = NSBitmapImageRep(data: img2x.tiffRepresentation!) {
        rep2.size = NSSize(width: 16, height: 16)
        finalTiff.addRepresentation(rep2)
    }
    finalTiff.isTemplate = true

    if let tiffData = finalTiff.tiffRepresentation {
        let tiffURL = URL(fileURLWithPath: outputDir).appendingPathComponent("MenuIcon.tiff")
        try tiffData.write(to: tiffURL)
        print("Generated MenuIcon.tiff at: \(tiffURL.path)")
    }

    if let rep2 = NSBitmapImageRep(data: img2x.tiffRepresentation!),
       let pngData = rep2.representation(using: .png, properties: [:]) {
        let pngURL = URL(fileURLWithPath: outputDir).appendingPathComponent("MenuIcon.png")
        try pngData.write(to: pngURL)
        print("Generated MenuIcon.png at: \(pngURL.path)")
    }
}

func generateAppIcon(outputDir: String) throws {
    let fileManager = FileManager.default
    let iconsetDir = URL(fileURLWithPath: outputDir).appendingPathComponent("AppIcon.iconset").path
    try fileManager.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

    let sizes: [(point: CGFloat, scale: CGFloat, name: String)] = [
        (16, 1, "icon_16x16.png"),
        (16, 2, "icon_16x16@2x.png"),
        (32, 1, "icon_32x32.png"),
        (32, 2, "icon_32x32@2x.png"),
        (128, 1, "icon_128x128.png"),
        (128, 2, "icon_128x128@2x.png"),
        (256, 1, "icon_256x256.png"),
        (256, 2, "icon_256x256@2x.png"),
        (512, 1, "icon_512x512.png"),
        (512, 2, "icon_512x512@2x.png")
    ]

    for item in sizes {
        let img = renderBopomofoBadge(pointSize: item.point, scale: item.scale)
        if let rep = NSBitmapImageRep(data: img.tiffRepresentation!),
           let pngData = rep.representation(using: .png, properties: [:]) {
            let fileURL = URL(fileURLWithPath: iconsetDir).appendingPathComponent(item.name)
            try pngData.write(to: fileURL)
        }
    }

    // Run iconutil to compile .icns
    let icnsOutput = URL(fileURLWithPath: outputDir).appendingPathComponent("AppIcon.icns").path
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["-c", "icns", iconsetDir, "-o", icnsOutput]
    try process.run()
    process.waitUntilExit()

    print("Generated AppIcon.icns at: \(icnsOutput)")
}

let args = CommandLine.arguments
let outputDir = args.count > 1 ? args[1] : "build/Resources"

do {
    try generateMenuIcons(outputDir: outputDir)
    try generateAppIcon(outputDir: outputDir)
    print("Icon generation completed successfully.")
} catch {
    print("Icon generation failed: \(error)")
    exit(1)
}

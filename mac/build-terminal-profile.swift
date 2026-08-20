#!/usr/bin/xcrun swift
//
// Build mac/traderspost.terminal from mac/traderspost.itermcolors using the
// NSKeyedArchiver format Terminal.app expects on modern macOS (profile v2.09).
// Palette source: omarchy/themes/traderspost/colors.toml
//
import AppKit
import Foundation

enum BuildError: Error, CustomStringConvertible {
    case unreadableScheme
    case archivingFailed(String)
    case serializationFailed
    case writeFailed

    var description: String {
        switch self {
        case .unreadableScheme:
            return "cannot read traderspost.itermcolors"
        case .archivingFailed(let key):
            return "could not archive \(key)"
        case .serializationFailed:
            return "could not serialize traderspost.terminal"
        case .writeFailed:
            return "could not write traderspost.terminal"
        }
    }
}

struct TerminalProfileBuilder {
    static let colorKeys: [String: String] = [
        "Ansi 0 Color": "ANSIBlackColor",
        "Ansi 1 Color": "ANSIRedColor",
        "Ansi 2 Color": "ANSIGreenColor",
        "Ansi 3 Color": "ANSIYellowColor",
        "Ansi 4 Color": "ANSIBlueColor",
        "Ansi 5 Color": "ANSIMagentaColor",
        "Ansi 6 Color": "ANSICyanColor",
        "Ansi 7 Color": "ANSIWhiteColor",
        "Ansi 8 Color": "ANSIBrightBlackColor",
        "Ansi 9 Color": "ANSIBrightRedColor",
        "Ansi 10 Color": "ANSIBrightGreenColor",
        "Ansi 11 Color": "ANSIBrightYellowColor",
        "Ansi 12 Color": "ANSIBrightBlueColor",
        "Ansi 13 Color": "ANSIBrightMagentaColor",
        "Ansi 14 Color": "ANSIBrightCyanColor",
        "Ansi 15 Color": "ANSIBrightWhiteColor",
        "Background Color": "BackgroundColor",
        "Foreground Color": "TextColor",
        "Selection Color": "SelectionColor",
        "Bold Color": "TextBoldColor",
        "Cursor Color": "CursorColor",
    ]

    static func build(from source: URL, to destination: URL) throws {
        guard let scheme = NSDictionary(contentsOf: source) else {
            throw BuildError.unreadableScheme
        }

        var profile: [String: Any] = [
            "name": "TradersPost",
            "type": "Window Settings",
            "ProfileCurrentVersion": 2.09,
            "columnCount": 120,
            "rowCount": 30,
            "FontAntialias": true,
            "FontHeightSpacing": 1.0,
            "FontWidthSpacing": 1,
            "DynamicANSIForegroundColors": false,
        ]

        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        guard let fontData = try? NSKeyedArchiver.archivedData(
            withRootObject: font,
            requiringSecureCoding: false
        ) else {
            throw BuildError.archivingFailed("Font")
        }
        profile["Font"] = fontData

        for (schemeKey, terminalKey) in TerminalProfileBuilder.colorKeys {
            guard let definition = scheme[schemeKey] as? NSDictionary else { continue }
            let color = try color(from: definition, named: schemeKey)
            guard let data = try? NSKeyedArchiver.archivedData(
                withRootObject: color,
                requiringSecureCoding: false
            ) else {
                throw BuildError.archivingFailed(schemeKey)
            }
            profile[terminalKey] = data
        }

        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: profile,
            format: .xml,
            options: 0
        ) else {
            throw BuildError.serializationFailed
        }

        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).tmp")
        do {
            try data.write(to: temporary, options: .atomic)
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: destination)
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw BuildError.writeFailed
        }
    }

    static func color(from definition: NSDictionary, named key: String) throws -> NSColor {
        func component(_ name: String, default fallback: Double? = nil) -> CGFloat {
            guard let number = definition[name] as? NSNumber else {
                if let fallback { return CGFloat(fallback) }
                return 0
            }
            return CGFloat(number.doubleValue)
        }

        let red = component("Red Component")
        let green = component("Green Component")
        let blue = component("Blue Component")
        let alpha = component("Alpha Component", default: 1)

        switch (definition["Color Space"] as? String) ?? "sRGB" {
        case "sRGB", "Calibrated", "P3", "Display P3":
            return NSColor(deviceRed: red, green: green, blue: blue, alpha: alpha)
        default:
            return NSColor(deviceRed: red, green: green, blue: blue, alpha: alpha)
        }
    }
}

let macDir = URL(fileURLWithPath: #file).deletingLastPathComponent()
let source = macDir.appendingPathComponent("traderspost.itermcolors")
let destination = macDir.appendingPathComponent("traderspost.terminal")

do {
    try TerminalProfileBuilder.build(from: source, to: destination)
    print("built   \(destination.path)")
} catch {
    fputs("Error: \(error)\n", stderr)
    exit(1)
}

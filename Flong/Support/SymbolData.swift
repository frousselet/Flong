//
//  SymbolData.swift
//  Flong
//
//  Created by François Rousselet on 31/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CoreGraphics
import Foundation
import OSLog

#if os(iOS)
    import UIKit
#else
    import AppKit
#endif

/// An SF Symbol as bytes, for the one place in the application that cannot ask
/// the system for one.
///
/// **A rendered article is a web page, and a web page has no symbols.** Every
/// other screen says `Image(systemName:)` and is done ; the reader draws its
/// article in a web view, so a symbol that belongs in that page has to arrive
/// as a picture. It is drawn once, black on nothing, and handed over as bytes.
///
/// **Black on nothing because it is used as a mask and not as a picture.** A
/// symbol printed in a colour is a symbol that is that colour in both
/// appearances, and half of those are unreadable. The page uses these to cut
/// the shape out of the text colour, so the glyph follows the appearance, the
/// pill's own tint and Dynamic Type without anything here knowing about any of
/// them. Only the alpha of these bytes is ever read.
nonisolated enum SymbolData {
    private static let log = Logger(subsystem: "com.rslt.Flong", category: "symbols")

    /// The symbol, ready to be written into a stylesheet, or nothing.
    ///
    /// A missing symbol is not worth a broken page : the caller draws no glyph
    /// and the words stand on their own, which is what they did before there
    /// were any.
    static func dataURI(_ name: String, points: CGFloat = 40) -> String? {
        guard let data = png(name, points: points) else {
            log.notice("No symbol named \(name, privacy: .public)")
            return nil
        }
        return "data:image/png;base64,\(data.base64EncodedString())"
    }

    /// The symbol drawn at a size a thirteen point mask will never outgrow.
    private static func png(_ name: String, points: CGFloat) -> Data? {
        #if os(iOS)
            let configuration = UIImage.SymbolConfiguration(pointSize: points, weight: .medium)
            guard let symbol = UIImage(systemName: name, withConfiguration: configuration) else { return nil }
            return symbol.withTintColor(.black, renderingMode: .alwaysOriginal).pngData()
        #else
            guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
            let configuration = NSImage.SymbolConfiguration(pointSize: points, weight: .medium)
            let drawn = symbol.withSymbolConfiguration(configuration) ?? symbol
            guard let tiff = drawn.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
            return bitmap.representation(using: .png, properties: [:])
        #endif
    }
}

//
//  FolderPath.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// The path of a folder, as a namespaced tag.
///
/// A folder is nothing but a view over a root tag, so it is written the way a
/// tag is : components separated by a slash, `veille/ios`. Feeds carry the path
/// of the folder they sit in, and a feed outside any folder carries none.
nonisolated enum FolderPath {
    static let separator: Character = "/"

    /// The stored form of a folder path, or `nil` when it holds nothing.
    ///
    /// Empty components are dropped, so `/Tech//iOS/` and `Tech / iOS` both
    /// settle on `Tech/iOS`.
    static func normalized(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let path = components(of: raw).joined(separator: String(separator))
        return path.isEmpty ? nil : path
    }

    /// The components of a path, trimmed and without the empty ones.
    static func components(of path: String) -> [String] {
        path
            .split(separator: separator)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// The name shown in a list : the last component of the path.
    static func name(of path: String) -> String {
        components(of: path).last ?? path
    }

    /// The folders a path sits in, from the outermost inwards, itself excluded.
    ///
    /// A sidebar needs them : nothing subscribes to `Tech` when the only feed
    /// sits in `Tech/iOS`, yet the tree still has to show the level above.
    static func ancestors(of path: String) -> [String] {
        let parts = components(of: path)
        guard parts.count > 1 else { return [] }
        return (1..<parts.count).map { parts.prefix($0).joined(separator: String(separator)) }
    }
}

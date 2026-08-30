//
//  ArticleVector.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// A kept article, as a direction in meaning space.
///
/// A vector is only comparable to vectors produced by **the same model at the
/// same revision**, and system models change with the operating system. Both
/// travel with every vector, and a vector whose pair does not match this
/// device's is ignored and computed again rather than compared. Mixing two
/// revisions does not fail loudly : it quietly returns nonsense, which is worse.
nonisolated struct ArticleVector: Hashable, Sendable {
    /// The model that produced it, `nl.sentence.fr`.
    let model: String
    /// That model's revision, which Apple changes between system versions.
    let revision: Int
    /// The values, already normalized to a length of one.
    let values: [Float]

    var dimensions: Int { values.count }

    init(model: String, revision: Int, values: [Float]) {
        self.model = model
        self.revision = revision
        self.values = ArticleVector.normalized(values)
    }

    /// Whether two vectors may be compared at all.
    func isComparable(to other: ArticleVector) -> Bool {
        model == other.model && revision == other.revision && dimensions == other.dimensions
    }

    /// How close two articles are, from minus one to one.
    ///
    /// Both are normalized, so the dot product is the cosine. Nothing more
    /// elaborate is needed at this scale : a few thousand vectors compared
    /// against one is a few million multiplications, which is a millisecond.
    func similarity(to other: ArticleVector) -> Float {
        guard isComparable(to: other) else { return 0 }
        return zip(values, other.values).reduce(0) { $0 + $1.0 * $1.1 }
    }

    private static func normalized(_ values: [Float]) -> [Float] {
        let length = sqrt(values.reduce(0) { $0 + $1 * $1 })
        guard length > 0 else { return values }
        return values.map { $0 / length }
    }

    // MARK: - The wire

    /// The vector as bytes, quantized to eight bits.
    ///
    /// A normalized value lies between minus one and one, so one byte holds it
    /// with a precision of about half a percent, which changes a similarity in
    /// the third decimal and nothing a reader would notice. Five hundred
    /// dimensions become five hundred bytes instead of two thousand, and the
    /// marked articles come to about a megabyte between them, which is what
    /// section 14 budgets for them in CloudKit.
    func quantized() -> Data {
        // Scaled by its own largest component first. A normalized vector of five
        // hundred dimensions has components around a twentieth, so quantizing it
        // against the range minus one to one would spend most of the two hundred
        // and fifty six available values on nothing.
        //
        // The scale is deliberately not stored : reading a vector normalizes it
        // again, and a cosine does not care how long either vector was.
        let scale = values.map(abs).max() ?? 1
        guard scale > 0 else { return Data(repeating: 128, count: values.count) }

        return Data(
            values.map { value in
                UInt8(clamping: Int((value / scale * 127).rounded()) + 128)
            })
    }

    /// Reads back what `quantized()` wrote.
    static func dequantized(_ data: Data, model: String, revision: Int) -> ArticleVector? {
        guard !data.isEmpty else { return nil }
        return ArticleVector(
            model: model,
            revision: revision,
            values: data.map { (Float(Int($0) - 128)) / 127 }
        )
    }
}

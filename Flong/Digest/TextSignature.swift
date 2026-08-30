//
//  TextSignature.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// What an article is about, as the words only it uses.
///
/// The digest groups the reprints of one story, and reprints share vocabulary :
/// `académies`, `mi-août`, `calendrier`. Two articles about different things
/// share only the words everybody uses, which is what the weighting removes.
///
/// This replaces the sentence embeddings, which were measured on a small French
/// corpus and found unusable for the purpose : two unrelated articles scored
/// 0.93 where two about the same event scored 0.92. A model that cannot tell a
/// school calendar from a history of typography is not a signal, whatever its
/// numbers look like. The vectors remain what they are good at, which is
/// searching what the reader marked by meaning.
nonisolated struct TextSignature: Hashable, Sendable, Codable {
    /// Term to weight, already normalized to a length of one.
    let weights: [String: Double]

    var isEmpty: Bool { weights.isEmpty }

    /// How much two articles have in common, from zero to one.
    func similarity(to other: TextSignature) -> Double {
        // The shorter side drives the loop : most pairs share almost nothing,
        // and walking the smaller dictionary is the difference between a digest
        // that builds in a second and one that does not.
        let (small, large) = weights.count <= other.weights.count ? (weights, other.weights) : (other.weights, weights)

        return small.reduce(0) { total, pair in
            guard let weight = large[pair.key] else { return total }
            return total + pair.value * weight
        }
    }

    /// The mean of several signatures, which is what a story's own signature is.
    static func mean(of signatures: [TextSignature]) -> TextSignature {
        guard !signatures.isEmpty else { return TextSignature(weights: [:]) }

        var total: [String: Double] = [:]
        for signature in signatures {
            for (term, weight) in signature.weights {
                total[term, default: 0] += weight
            }
        }
        return TextSignature(weights: normalized(total))
    }

    static func normalized(_ weights: [String: Double]) -> [String: Double] {
        let length = sqrt(weights.values.reduce(0) { $0 + $1 * $1 })
        guard length > 0 else { return [:] }
        return weights.mapValues { $0 / length }
    }
}

/// Turns text into terms, and terms into signatures.
nonisolated enum TextSignatures {
    /// Below this a word carries nothing : `le`, `de`, `un`.
    static let minimumLength = 3

    /// How many terms an article keeps. The tail of a long article is its
    /// vocabulary, not its subject.
    static let maximumTerms = 40

    /// The words that say nothing about a subject because every article uses
    /// them. Kept deliberately short : rarity does the rest of the work, and a
    /// long list is a long list to be wrong about.
    static let stopWords: Set<String> = [
        "les", "des", "une", "aux", "avec", "pour", "dans", "sur", "par", "que", "qui", "quoi", "dont",
        "est", "sont", "etait", "etaient", "ete", "avoir", "faire", "plus", "moins", "tout", "tous",
        "cette", "ces", "son", "sa", "ses", "leur", "leurs", "notre", "votre", "nous", "vous", "elle",
        "ils", "elles", "mais", "donc", "car", "ainsi", "alors", "apres", "avant", "entre", "chez",
        "the", "and", "for", "with", "from", "that", "this", "these", "those", "have", "has", "had",
        "was", "were", "been", "are", "will", "would", "could", "should", "about", "into", "than",
        "then", "there", "their", "them", "they", "you", "your", "our", "its", "not", "but", "who",
    ]

    /// The terms of a text : folded, split, and stripped of what says nothing.
    static func terms(of text: String) -> [String] {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en"))

        return
            folded
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count >= minimumLength && !stopWords.contains($0) }
    }

    /// The document frequency of every term across a set of texts, which is what
    /// tells a distinctive word from a common one.
    static func documentFrequencies(of documents: [[String]]) -> [String: Int] {
        documents.reduce(into: [:]) { frequencies, terms in
            for term in Set(terms) { frequencies[term, default: 0] += 1 }
        }
    }

    /// The signature of one text, weighted against how common its words are.
    ///
    /// A word used by one article in a hundred says a hundred times more about
    /// what that article is than a word used by every one of them.
    static func signature(
        of terms: [String],
        documentFrequencies: [String: Int],
        documentCount: Int
    ) -> TextSignature {
        guard !terms.isEmpty, documentCount > 0 else { return TextSignature(weights: [:]) }

        var counts: [String: Double] = [:]
        for term in terms { counts[term, default: 0] += 1 }

        var weights: [String: Double] = [:]
        for (term, count) in counts {
            let frequency = Double(documentFrequencies[term] ?? 1)
            let rarity = log(Double(documentCount + 1) / (frequency + 1)) + 1
            weights[term] = (1 + log(count)) * rarity
        }

        // Only the strongest terms are kept, so a long article is compared on
        // what it is about rather than on everything it happens to mention.
        let strongest = weights.sorted { $0.value > $1.value }.prefix(maximumTerms)
        let kept = Dictionary(uniqueKeysWithValues: strongest.map { ($0.key, $0.value) })
        return TextSignature(weights: TextSignature.normalized(kept))
    }
}

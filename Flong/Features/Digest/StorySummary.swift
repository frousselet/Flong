//
//  StorySummary.swift
//  Flong
//
//  Created by François Rousselet on 01/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// What happened, in one sentence, marked where a model is what wrote it.
///
/// **The mark stands in front of the line rather than at the end of the row.**
/// It used to be a pair of sparkles among the facts, at the far end of the
/// line that counts the rooms and says how long ago the last article came :
/// the width of the row away from the sentence it was about, in the company of
/// everything the store knows for certain. A reader who wanted to know who
/// wrote the words they were reading had to look somewhere else and then work
/// out that it referred back.
///
/// In front of the sentence it is about, it is read in the half second before
/// the sentence is, which is when it matters and the only time it does : this
/// line was written here, on this device, out of the articles underneath. The
/// glyph is a summary rather than a spark, since what it marks is a summary and
/// not a piece of magic.
///
/// **Beside the words and not inside them.** Set into the text it would flow
/// with it and end up in the middle of a wrapped line on a narrow phone. In its
/// own column the sentence keeps its own measure and the mark keeps the margin,
/// which is where a mark about a paragraph has always gone.
struct StorySummary: View {
    let summary: String
    /// Whether a model wrote the headline or this line. See `Story`.
    let isGenerated: Bool
    /// The step of the scale the line is set at : a row of the front page can
    /// spare less than a story's own page.
    var style: Font.TextStyle = .subheadline
    /// How many lines a row allows it, or none where the page gives it all it
    /// needs.
    var lines: Int?

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if isGenerated {
                Image(systemName: "text.line.3.summary")
                    // The line's own size, so the mark grows with Dynamic Type
                    // and sits on the same baseline whatever the reader has
                    // asked for, and a step quieter in colour than the words :
                    // it says who wrote them and is not one of them.
                    .font(.system(style))
                    .foregroundStyle(.tertiary)
                    .accessibilityLabel(Text("Written by the model"))
                    .help(Text("Written by the model"))
            }

            Text(verbatim: summary)
                .font(theme.standfirst(style))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .lineLimit(lines)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

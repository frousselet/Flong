//
//  ArticleReaderView.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// Builds the page an article is displayed as.
///
/// The article is served to an isolated web view as a document of its own, with
/// the appearance of the system baked in : section 10 of the specification asks
/// for rendered HTML to follow light and dark mode, which `color-scheme` and a
/// `prefers-color-scheme` block are exactly what does.
nonisolated enum ArticleDocument {
    /// Which of the two bodies a page is built from.
    ///
    /// The feed gave one and, when the feed was short, the article's own page
    /// gave another. Both are kept, and the reader may read either : an
    /// extraction is a guess about somebody else's markup, and a guess the
    /// reader cannot get out of is a guess imposed on them.
    nonisolated enum Body: Hashable, Sendable {
        case feed
        case page
    }

    /// - Parameter publisher: who published it, as the application names them
    ///   everywhere else : the group rather than the feed it arrived through.
    ///   The feed's own title stands in only where the publisher is unknown.
    /// - Parameter mark: the publisher's own mark, to set in the pill in front
    ///   of their name. One address and no second try : see ``SourceIcon/mark(for:)``.
    static func html(
        for article: Article,
        publisher: String? = nil,
        mark: URL? = nil,
        showing body: Body = .page
    ) -> String {
        let byline = byline(of: article, publisher: publisher, mark: mark)
        let chosen = (body == .page ? article.extractedHTML : nil) ?? article.bodyHTML ?? ""
        let markup = without(article.imageURL, in: chosen)

        return """
            <!doctype html>
            <html lang="\(article.language ?? "en")">
            <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
            <style>\(stylesheet)</style>
            <style>\(Self.mark(at: mark))</style>
            </head>
            <body>
            \(lead(of: article))
            <div class="column">
            <header>
            <h1>\(HTMLEntities.escape(article.title))</h1>
            <p class="byline">\(byline)</p>
            </header>
            <article>\(markup)</article>
            </div>
            </body>
            </html>
            """
    }

    /// The picture the article is headed with, running the whole width.
    ///
    /// **Above the headline and under the controls.** It is the same picture
    /// the row the reader tapped was carrying, so the page opens on what they
    /// were looking at when they decided to open it. The controls float over
    /// it, which is what the width is for : a picture inset inside the column
    /// with a bar of its own above it would be a photograph with a shelf on it.
    ///
    /// **Its own height, and no crop.** Every other picture in the application
    /// is shown at three by two, which is what makes a list of them read as a
    /// column ; a page is not a list, and it is the only place a photograph is
    /// looked at rather than glanced at. A portrait cropped to a landscape box
    /// on the one screen where there is room for it is a crop made for nothing.
    ///
    /// It also means the head takes no room until there is something to put in
    /// it : a box reserved at a ratio is a box that is empty while the picture
    /// loads and stays empty if it never arrives.
    private static func lead(of article: Article) -> String {
        guard let address = article.imageURL, HTTPURL.isFetchable(address) else { return "" }
        let source = HTMLEntities.escape(address.absoluteString)
        return "<figure class=\"lead\"><img src=\"\(source)\" alt=\"\"></figure>"
    }

    /// The body without the picture the page is already headed with.
    ///
    /// An article's picture is taken from the feed or, failing that, from the
    /// first picture in its body : in the second case the head and the first
    /// paragraph would be the same photograph twice, one above the other. What
    /// is removed is the tag and nothing around it ; an empty `figure` left
    /// behind is drawn as nothing, which the stylesheet sees to.
    static func without(_ picture: URL?, in markup: String) -> String {
        guard let address = picture?.absoluteString, !address.isEmpty else { return markup }
        guard let found = markup.range(of: address) else { return markup }

        // Back to the `<` that opens the tag holding it, and on to the `>` that
        // closes it. Anything else between them is that tag's own business.
        let before = markup.startIndex..<found.lowerBound
        let after = found.upperBound..<markup.endIndex

        guard let opening = markup.range(of: "<img", options: [.backwards, .caseInsensitive], range: before),
            let closing = markup.range(of: ">", range: after)
        else { return markup }

        return markup.replacingCharacters(in: opening.lowerBound..<closing.upperBound, with: "")
    }

    /// Who published it, on a pill, and what else is known about the article
    /// beside it.
    ///
    /// **The publisher is set apart from the rest of the line.** Everything
    /// here is the application talking about the article rather than the
    /// article talking, and one of the four is not like the other three : the
    /// author, the date and the revision describe this piece, and the publisher
    /// is the one fact that is the same for every piece they have ever run. It
    /// is also the only one that is looked up rather than read off the article,
    /// so a reader who renames a publisher renames it here too, and the mark
    /// they know it by can stand in front of the name, which is what a mark is
    /// for : it is recognized before the name is read.
    ///
    /// The pill is the same one the pictures wear their credit on, so a reader
    /// meets one shape for *this came from them* rather than one per screen.
    private static func byline(of article: Article, publisher: String?, mark: URL?) -> String {
        let source = publisher ?? article.domain ?? article.feedTitle
        var parts: [String] = []
        if let author = article.author, !author.isEmpty {
            parts.append(String(localized: "By \(author)"))
        }
        if let date = article.publishedAt {
            parts.append(date.formatted(date: .long, time: .shortened))
        }
        // Said in full here, beside the publication rather than instead of it :
        // the page has room for both, and a reader who has opened the article
        // is the one who wants to know exactly what changed when. The list has
        // room for one and shows whichever is the later.
        if let updated = article.updatedAt {
            parts.append(String(localized: "updated \(updated.formatted(date: .long, time: .shortened))"))
        }
        let rest = parts.joined(separator: " · ")

        // Nothing at all rather than an empty pill : an article whose feed has
        // gone and which never carried a domain has nobody to name.
        guard !source.isEmpty else { return HTMLEntities.escape(rest) }

        // The mark's own box is dropped when there is no mark to put in it,
        // since scripting is off and nothing in the page can notice a picture
        // that failed : a box kept for one that never arrives is a hole in
        // front of the name for the whole life of the page.
        let stamp = mark == nil ? "" : "<span class=\"mark\"></span>"
        let pill = "<span class=\"source\">\(stamp)\(HTMLEntities.escape(source))</span>"

        return rest.isEmpty ? pill : "\(pill)<span>\(HTMLEntities.escape(rest))</span>"
    }

    /// The rule that puts the publisher's mark in the pill, or none.
    ///
    /// Set here rather than on the element : it is one mark per document, and
    /// an address written into a `style` attribute is escaped twice, once for
    /// the attribute and once for the value inside it, which is two chances to
    /// get it wrong for no gain.
    ///
    /// **It is an address from a feed, so it is checked before it is written.**
    /// ``SourceIcon/mark(for:)`` has already refused anything that is not an
    /// http address and raised it to TLS ; what is left is to make sure the
    /// text of it cannot close the `url()` it sits in and start a rule of its
    /// own. Percent encoding means neither character should survive that far,
    /// and neither is written out on the strength of should.
    private static func mark(at address: URL?) -> String {
        guard let address else { return "" }

        let quoted =
            address.absoluteString
            .replacingOccurrences(of: "\\", with: "%5C")
            .replacingOccurrences(of: "\"", with: "%22")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")

        return ".source .mark { background-image: url(\"\(quoted)\"); }"
    }

    /// Deliberately small : an article is text, and the reader's own settings
    /// decide the rest once section 10 typography arrives.
    private static let stylesheet = """
        :root {
          color-scheme: light dark;
          --text: #1c1c1e; --muted: #6c6c70; --rule: #d8d8dc; --link: #0b6bcb;
          --voice: -apple-system, system-ui, sans-serif;
          --glass: rgba(120, 120, 128, 0.12);
        }
        @media (prefers-color-scheme: dark) {
          :root {
            --text: #f2f2f7; --muted: #9c9ca1; --rule: #3a3a3c; --link: #6fb2ff;
            --glass: rgba(120, 120, 128, 0.24);
          }
        }
        body {
          margin: 0; padding: 0;
          /* The shorthand carries Dynamic Type ; the family after it carries the
             voice. Serif for what was written, as everywhere else. */
          font: -apple-system-body; font-family: ui-serif, "New York", Georgia, serif;
          line-height: 1.55; color: var(--text);
          -webkit-text-size-adjust: 100%; overflow-wrap: break-word;
        }
        /* The measure lives here rather than on the body, so that the picture
           at the head can run the whole width while the words do not. */
        .column { margin: 0 auto; padding: 16px; max-width: 42em; }
        /* Edge to edge, under the controls, and at whatever height its own
           shape gives it. */
        .lead { margin: 0; }
        .lead img { display: block; width: 100%; height: auto; }
        h1 { font-size: 1.6em; line-height: 1.25; margin: 0 0 8px; }
        h2, h3, h4 { line-height: 1.3; margin: 1.4em 0 0.4em; }
        /* What the application says about the article, rather than the article. */
        .byline {
          font-family: var(--voice); color: var(--muted); font-size: 0.9em; margin: 0 0 16px;
          display: flex; flex-wrap: wrap; align-items: center; gap: 4px 10px;
        }
        /* Who published it, on the pill the picture credits already use. It
           takes the colour of what is under it, which on this page is paper
           and over a picture is the picture. */
        .source {
          display: inline-flex; align-items: center; gap: 6px;
          padding: 3px 10px; border-radius: 999px;
          color: var(--text); background: var(--glass);
          -webkit-backdrop-filter: blur(20px) saturate(180%);
          backdrop-filter: blur(20px) saturate(180%);
          box-shadow: inset 0 0 0 0.5px var(--rule);
        }
        /* Round and ringed, as the marks are everywhere else, and tucked into
           the padding so the pill sits no taller for having one. */
        .source .mark {
          width: 17px; height: 17px; margin: -1px 0 -1px -5px;
          border-radius: 50%; background: center / cover no-repeat;
          box-shadow: inset 0 0 0 0.5px var(--rule);
        }
        header { border-bottom: 1px solid var(--rule); padding-bottom: 12px; margin-bottom: 16px; }
        a { color: var(--link); }
        img, video, audio, iframe { max-width: 100%; height: auto; }
        figure { margin: 1em 0; }
        /* What is left where the head's own picture was taken out of the body. */
        figure:empty, p:empty { display: none; margin: 0; }
        figcaption { font-family: var(--voice); color: var(--muted); font-size: 0.85em; }
        blockquote {
          margin: 1em 0; padding: 0 0 0 1em;
          border-left: 3px solid var(--rule); color: var(--muted);
        }
        pre { overflow-x: auto; padding: 12px; background: color-mix(in srgb, var(--text) 8%, transparent); }
        code { font-family: ui-monospace, monospace; font-size: 0.9em; }
        table { display: block; overflow-x: auto; border-collapse: collapse; }
        td, th { border: 1px solid var(--rule); padding: 4px 8px; }
        hr { border: none; border-top: 1px solid var(--rule); }
        """
}

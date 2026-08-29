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

import SwiftUI

/// The third level : the article itself.
struct ArticleReaderView: View {
    let model: AppModel

    var body: some View {
        Group {
            if let article = model.article {
                ArticleWebView(html: ArticleDocument.html(for: article))
                    .ignoresSafeArea(edges: .bottom)
                    .toolbar { toolbar(for: article) }
                    .navigationTitle(Text(verbatim: article.feedTitle))
                    #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                    #endif
            } else {
                ContentUnavailableView {
                    Label("No article selected", systemImage: "doc.text")
                } description: {
                    Text("Pick an article from the list.")
                }
            }
        }
    }

    @ToolbarContentBuilder
    private func toolbar(for article: Article) -> some ToolbarContent {
        ToolbarItem {
            Button {
                Task { await model.toggleStarredCurrent() }
            } label: {
                Label(
                    article.isStarred ? "Remove from favourites" : "Add to favourites",
                    systemImage: article.isStarred ? "star.fill" : "star"
                )
            }
        }

        if article.origin == .stream {
            ToolbarItem {
                Button {
                    Task { await model.markCurrentUnread() }
                } label: {
                    Label("Mark as unread", systemImage: "circle")
                }
            }
        }

        if let url = article.url {
            ToolbarItem {
                ShareLink(item: url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
            ToolbarItem {
                Link(destination: url) {
                    Label("Open in browser", systemImage: "safari")
                }
            }
        }
    }
}

/// Builds the page an article is displayed as.
///
/// The article is served to an isolated web view as a document of its own, with
/// the appearance of the system baked in : section 10 of the specification asks
/// for rendered HTML to follow light and dark mode, which `color-scheme` and a
/// `prefers-color-scheme` block are exactly what does.
nonisolated enum ArticleDocument {
    static func html(for article: Article) -> String {
        let byline = byline(of: article)

        return """
            <!doctype html>
            <html lang="\(article.language ?? "en")">
            <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
            <style>\(stylesheet)</style>
            </head>
            <body>
            <header>
            <h1>\(HTMLEntities.escape(article.title))</h1>
            <p class="byline">\(HTMLEntities.escape(byline))</p>
            </header>
            <article>\(article.bodyHTML ?? "")</article>
            </body>
            </html>
            """
    }

    private static func byline(of article: Article) -> String {
        var parts = article.feedTitle.isEmpty ? [] : [article.feedTitle]
        if let author = article.author, !author.isEmpty {
            parts.append(String(localized: "By \(author)"))
        }
        if let date = article.publishedAt {
            parts.append(date.formatted(date: .long, time: .shortened))
        }
        return parts.joined(separator: " · ")
    }

    /// Deliberately small : an article is text, and the reader's own settings
    /// decide the rest once section 10 typography arrives.
    private static let stylesheet = """
        :root { color-scheme: light dark; --text: #1c1c1e; --muted: #6c6c70; --rule: #d8d8dc; --link: #0b6bcb; }
        @media (prefers-color-scheme: dark) {
          :root { --text: #f2f2f7; --muted: #9c9ca1; --rule: #3a3a3c; --link: #6fb2ff; }
        }
        body {
          margin: 0 auto; padding: 16px; max-width: 42em;
          font: -apple-system-body; line-height: 1.55; color: var(--text);
          -webkit-text-size-adjust: 100%; overflow-wrap: break-word;
        }
        h1 { font-size: 1.6em; line-height: 1.25; margin: 0 0 8px; }
        h2, h3, h4 { line-height: 1.3; margin: 1.4em 0 0.4em; }
        .byline { color: var(--muted); font-size: 0.9em; margin: 0 0 16px; }
        header { border-bottom: 1px solid var(--rule); padding-bottom: 12px; margin-bottom: 16px; }
        a { color: var(--link); }
        img, video, audio, iframe { max-width: 100%; height: auto; }
        figure { margin: 1em 0; }
        figcaption { color: var(--muted); font-size: 0.85em; }
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

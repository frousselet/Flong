//
//  ArticleExtractorTests.swift
//  FlongTests
//
//  Created by François Rousselet on 30/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing

@testable import Flong

@Suite("Pulling the article out of a page")
struct ArticleExtractorTests {
    private let source = URL(string: "https://lequotidien.example.com/2026/calendrier.html")!

    private func extract(_ name: String) throws -> String {
        let html = try String(decoding: Fixtures.data("Pages/\(name)"), as: UTF8.self)
        return try #require(ArticleExtractor.extract(html, from: source))
    }

    // MARK: - What is kept

    @Test("The article is kept whole")
    func keepsTheArticle() throws {
        let text = HTMLSanitizer.plainText(try extract("article.html"))

        // Every paragraph of the piece, first to last.
        #expect(text.contains("a confirmé mardi qu'une réforme"))
        #expect(text.contains("Les syndicats enseignants, consultés"))
        #expect(text.contains("les fédérations de parents d'élèves"))
        #expect(text.contains("aucune décision ne sera prise"))
    }

    @Test("The page around the article is left behind")
    func dropsTheFurniture() throws {
        let text = HTMLSanitizer.plainText(try extract("article.html"))

        // The masthead and its menu.
        #expect(!text.contains("Politique"))
        #expect(!text.contains("Économie"))
        // The share bars, above the article and below it.
        #expect(!text.contains("Partager"))
        #expect(!text.contains("Facebook"))
        // The sidebar of related headlines, and the newsletter form.
        #expect(!text.contains("À lire aussi"))
        #expect(!text.contains("Recevez chaque matin"))
        // The comments, and the footer.
        #expect(!text.contains("préparent leurs cours en août"))
        #expect(!text.contains("Tous droits réservés"))
    }

    @Test("The article's own pictures and captions come with it")
    func keepsTheIllustration() throws {
        let extracted = try extract("article.html")

        #expect(extracted.contains("<figure>"))
        #expect(extracted.contains("Une salle de classe dans une académie pilote."))
        // Resolved against the article, since a page states its images relatively.
        #expect(extracted.contains("https://lequotidien.example.com/images/2026/ecole.jpg"))
    }

    @Test("A page that says nothing about where its article is still gives it up")
    func plainPage() throws {
        let text = HTMLSanitizer.plainText(try extract("plain.html"))

        #expect(text.contains("Le sentier part de Florac"))
        #expect(text.contains("mille ans de moutons"))
        #expect(!text.contains("Mentions légales"))
        #expect(!text.contains("Archives"))
    }

    // MARK: - What is refused

    @Test("A wall is not an article")
    func paywall() throws {
        let html = try String(decoding: Fixtures.data("Pages/wall.html"), as: UTF8.self)

        // Two sentences and a subscribe button : the feed's own summary is
        // better than that, and is what the reader keeps.
        #expect(ArticleExtractor.extract(html, from: source) == nil)
    }

    @Test("A page with no article gives nothing")
    func nothingThere() {
        #expect(
            ArticleExtractor.extract("<html><body><nav><a href=/>Accueil</a></nav></body></html>", from: source) == nil)
        #expect(ArticleExtractor.extract("", from: source) == nil)
    }

    @Test("Nothing from the page is trusted")
    func sanitized() throws {
        let html = """
            <html><body><article>
            <p>Une phrase assez longue pour compter comme de la prose, avec ce qu'il faut de mots pour passer le seuil, et une deuxième proposition pour faire bonne mesure dans le compte.</p>
            <script>alert(1)</script>
            <p onclick="steal()">Un paragraphe qui porte un gestionnaire, lequel n'a rien à faire dans un article et doit disparaître avec le reste du bruit de la page.</p>
            <img src="javascript:alert(1)">
            <p>Une troisième phrase, pour que le bloc soit bien au-dessus du seuil de caractères exigé par l'extracteur avant qu'il accepte de rendre quoi que ce soit.</p>
            </article></body></html>
            """
        let extracted = try #require(ArticleExtractor.extract(html, from: source))

        #expect(!extracted.contains("script"))
        #expect(!extracted.contains("onclick"))
        #expect(!extracted.contains("javascript:"))
        #expect(extracted.contains("Une phrase assez longue"))
    }

    // MARK: - The judgements underneath

    @Test("A block of links is a menu, whatever it is called")
    func linkDensity() {
        let menu = HTMLDocument("<ul><li><a href=/a>Un</a></li><li><a href=/b>Deux</a></li></ul>")
        let prose = HTMLDocument(
            "<p>Une phrase avec <a href=/a>un lien</a> dedans, et beaucoup de texte autour de lui.</p>")

        let list = menu.firstElement(named: "ul")!
        let paragraph = prose.firstElement(named: "p")!

        #expect(ArticleExtractor.linkDensity(of: list) > ArticleExtractor.maximumLinkDensity)
        #expect(ArticleExtractor.linkDensity(of: paragraph) < ArticleExtractor.maximumLinkDensity)
    }

    @Test("What a publisher calls a thing is taken at its word, in whole words")
    func noise() {
        func element(_ html: String) -> HTMLElement {
            HTMLDocument(html).root.elements.first!
        }

        #expect(ArticleExtractor.isNoise(element("<div class='share-bar'></div>")))
        #expect(ArticleExtractor.isNoise(element("<div id='comments'></div>")))
        #expect(ArticleExtractor.isNoise(element("<nav></nav>")))
        // `share` must not take `shareholders`, which is what an article about
        // a company is full of.
        #expect(!ArticleExtractor.isNoise(element("<div class='shareholders'></div>")))
        #expect(!ArticleExtractor.isNoise(element("<div class='article-body'></div>")))
    }
}

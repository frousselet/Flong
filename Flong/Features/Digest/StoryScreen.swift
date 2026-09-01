//
//  StoryScreen.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// One story, as a page of its own.
///
/// It answers three questions in order : what happened, who says so, and what
/// each of them wrote. The first two are the whole reason a digest exists ; the
/// third is the reading, and it is last.
struct StoryScreen: View {
    let model: AppModel
    let storyID: UUID
    let zoom: Namespace.ID
    let open: (UUID) -> Void

    @Environment(\.theme) private var theme
    @State private var isExplaining = false

    private var story: DigestStory? {
        (model.digest.live + model.digest.stories).first { $0.id == storyID }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let story {
                    header(story)
                }

                ForEach(model.storyArticles[storyID] ?? []) { article in
                    // The picture at the top of the page came from one of these
                    // articles, and showing it again two hundred points below is
                    // saying the same thing twice.
                    ArticleRow(
                        article: article,
                        showsImage: article.imageURL != story?.imageURL,
                        zoom: zoom
                    ) {
                        open(article.id)
                    }
                }
            }
            .editorialColumn()
            .padding(.horizontal, 22)
            .padding(.bottom, 90)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .navigationTitle(Text("Story"))
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await model.openStoryPage(storyID) }
    }

    private func header(_ story: DigestStory) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // The same picture the row carried, and the same credit in the
            // corner of it : a name the front page shows and the page it opens
            // onto drops would be a courtesy that lasts as long as a glance.
            if story.imageURL != nil {
                RemoteImage(url: story.imageURL, credit: story.imageCredit, corner: 10)
                    .padding(.bottom, 2)
            }

            if !story.topics.isEmpty {
                Text(verbatim: story.topics.joined(separator: " · "))
                    .font(.system(.caption, weight: .semibold))
                    .textCase(.uppercase)
                    .kerning(0.6)
                    .foregroundStyle(.tertiary)
            }

            Text(verbatim: story.title)
                .font(theme.headline(.largeTitle))
                .fixedSize(horizontal: false, vertical: true)

            if let summary = story.summary, !summary.isEmpty {
                Text(verbatim: summary)
                    // The standfirst at the size a whole page gives it, rather
                    // than at the size a row on the front page can spare.
                    .font(theme.standfirst(.body))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if story.isGenerated {
                explanation
            }

            facts(story)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
        .padding(.bottom, Editorial.rhythm)
    }

    /// What the model did, said plainly, with the way back.
    ///
    /// The trend the research names is an assistant that is present, optional
    /// and explainable rather than an oracle. A reader who does not want a
    /// written headline gets the article's own, in one tap, and the application
    /// does not argue.
    private var explanation: some View {
        Button {
            isExplaining = true
        } label: {
            Label("Written by the model", systemImage: "sparkles")
                .font(theme.metadata)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isExplaining, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                Text(
                    "The headline and the line above were written on this device, from the articles below. Nothing was sent anywhere."
                )
                .font(.callout)

                Button("Use the article's own headline") {
                    isExplaining = false
                    Task { await model.dropGeneratedBrief(of: storyID) }
                }
            }
            .padding(16)
            .frame(maxWidth: 320)
            .presentationCompactAdaptation(.popover)
        }
    }

    private func facts(_ story: DigestStory) -> some View {
        HStack(spacing: 10) {
            if story.isLive {
                LiveDot()
            }

            // The same marks the row carried, so the page a reader tapped
            // into opens on what they tapped.
            HStack(spacing: 3) {
                ForEach(story.feedMarks) { mark in
                    SourceStamp(domain: mark.room, side: 15, showsName: false)
                }
                if story.feedCount > story.feedMarks.count {
                    Text(verbatim: "+\(story.feedCount - story.feedMarks.count)")
                        .padding(.leading, 1)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(Text("\(story.feedCount) rooms"))

            Text("\(story.articleCount) articles")

            Sparkline(values: story.arrivals)
                .frame(width: 44, height: 10)

            Spacer(minLength: 4)
            Text(story.lastAt, format: .relative(presentation: .numeric))
        }
        .font(theme.metadata)
        .foregroundStyle(.tertiary)
    }
}

/// One article, read.
struct ArticleScreen: View {
    let model: AppModel
    let articleID: UUID

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    @State private var isNamingCollection = false
    @State private var collectionName = ""

    /// Which body is being read.
    ///
    /// Whatever the reader last chose, which is carried between their devices.
    /// A reader who asked for the whole article once was not making a remark
    /// about that article.
    @State private var showing = ArticleDocument.Body.feed
    /// Whether the page was asked for and had nothing to give, which is when
    /// signing in to the site is worth offering.
    @State private var pageGaveNothing = false
    @State private var signingIn = false

    /// Who published it, as every list that led here already said.
    ///
    /// The publisher rather than the feed : `Le Monde` and not
    /// `Le Monde - Sport`. The address stands in while the subscriptions are
    /// being read, and the feed's own title only for an article whose feed has
    /// gone from under it.
    /// Whether the article this is about has a picture to run across its head.
    ///
    /// Read from the model rather than from the article in hand, so the answer
    /// exists before the article does and the bar is laid out once.
    private var hasHeadPicture: Bool {
        model.article?.id == articleID && model.article?.imageURL != nil
    }

    /// The group the article came from, which is what names it and what wears
    /// the mark. Nil where the reader is not subscribed to it any more.
    private func publisher(of article: Article) -> SourceIdentity? {
        model.publisher(of: article.domain)
    }

    /// The publisher's mark and the colour it averages to.
    ///
    /// **The colour is looked for at every address the mark might have come
    /// from, and the page is given one.** A view asks for the three candidates
    /// in turn and stops at the first that answers, so the address that
    /// actually produced the mark in the list is not always the one a page
    /// with no second try is handed. Asking each of them for a colour finds
    /// whichever it was.
    ///
    /// Nothing is fetched here. What has been decoded has a colour, and what
    /// has not leaves the pill its neutral grey rather than making an article
    /// wait on a favicon.
    private func mark(of identity: SourceIdentity?) -> ArticleDocument.Picture? {
        guard let address = SourceIcon.mark(for: identity) else { return nil }
        let tint = SourceIcon.candidates(for: identity)
            .lazy
            .compactMap { ImageStore.shared.tint(at: $0) }
            .first
        return ArticleDocument.Picture(address: address, tint: tint)
    }

    var body: some View {
        // **A view of its own, over the page it was opened from.** It was
        // pushed onto the stack of whichever section the reader was in, which
        // put an article under the tab bar : a row of places to go, drawn over
        // the one thing in the application that asks to be read without
        // anything else in the way. It is presented now, so the bar is behind
        // it and the page it came from is still there underneath.
        //
        // A navigation stack of its own inside it, for the bar the controls
        // hang off. It leads nowhere : what is on the stack is the article, and
        // the way out is the cross rather than a way back to a screen the
        // reader is already looking at behind this one.
        NavigationStack {
            Group {
                if let article = model.article, article.id == articleID {
                    ArticleWebView(
                        html: ArticleDocument.html(
                            for: article,
                            publisher: publisher(of: article)?.name ?? article.domain ?? article.feedTitle,
                            mark: mark(of: publisher(of: article)),
                            showing: showing,
                            theme: theme
                        ),
                        runsUnderTheBar: hasHeadPicture
                    )
                    .toolbar { toolbar(for: article) }
                    .overlay(alignment: .bottom) {
                        if model.isFetchingFullText {
                            fetching
                        }
                    }
                    .sheet(isPresented: $signingIn) {
                        if let host = article.url.flatMap(FeedURL.room(of:)) {
                            SiteLoginView(host: host) { cookies in
                                await model.saveSession(for: host, cookies: cookies)
                                // Signed in : ask the page again, as them.
                                await showFullArticle()
                            }
                        }
                    }
                } else {
                    ProgressView()
                }
            }
            // **The bar is settled before the article arrives, not after.**
            // These were inside the branch that draws the article, which is
            // the branch that appears once it has been read out of the store :
            // a navigation bar told what to look like after it has already
            // laid itself out keeps the look it had, which is a band of paper
            // across the top and the page beginning underneath it. Out here
            // they are what the bar is from the first frame.
            //
            // **The picture at the head runs under the controls**, so the page
            // starts at the top of the screen. An article with none has
            // nothing to run under it and its words start where they always
            // did, below the bar.
            .ignoresSafeArea(edges: hasHeadPicture ? [.top, .bottom] : .bottom)
            // **And the theme's colour stops at the edge of that picture.**
            // Glass decides what to draw from what is behind it, which is the
            // whole reason these controls may float over a photograph nobody
            // chose. A tint is an instruction and it overrides that : the
            // cross over a dark red photograph came out warm brown on dark
            // red, which is a way out the reader cannot find.
            //
            // So the accent reaches this bar only where the bar has the
            // application's own paper behind it. Where there is a lead, the
            // controls are the system's, exactly as the note above says they
            // are, and the theme says nothing about them.
            .tint(hasHeadPicture ? nil : theme.accent(in: scheme))
            // **No bar behind them, and no title in it.** The controls are
            // already on glass of the system's own, which is what keeps them
            // legible over a photograph ; a band of paper behind them would be
            // a shelf bolted across the picture. A title cannot be there :
            // plain type over somebody's photograph is unreadable on half the
            // photographs there are, and the publisher is named in the byline
            // under the headline anyway, where the page says it in its own
            // voice.
            #if os(iOS)
                .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
            #endif
        }
        .task {
            pageGaveNothing = false
            showing = model.articleBody == .page ? .page : .feed
            await model.open(article: articleID)

            // A reader who reads whole articles is not making a request each
            // time : fetching on opening is what they asked for, and only for
            // them.
            if model.articleBody == .page { await showFullArticle() }
            await model.loadCollections()
            await model.loadArticleCollections()
        }
        .alert(Text("New collection"), isPresented: $isNamingCollection) {
            TextField("Name", text: $collectionName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                let name = collectionName
                collectionName = ""
                Task {
                    await model.makeCollection(named: name)
                    await model.fileArticle(in: name)
                }
            }
        }
    }

    /// Said while the page is being fetched, and only then.
    ///
    /// The feed's version is on screen the whole time, so this is not a wait :
    /// it is the reason the text is about to get longer, which a reader would
    /// otherwise watch happen without explanation.
    /// Asks the page for the whole article, and shows it.
    ///
    /// On demand rather than on opening : the feed's version is what the reader
    /// sees by default, so fetching a page nobody has asked to see would be a
    /// request made to a publisher for something that is not going to be looked
    /// at. `docs/technical/extraction.md` is built on not doing that.
    private func showFullArticle() async {
        if model.article?.hasFullText != true {
            await model.fetchFullText()
        }

        if model.article?.hasFullText == true {
            showing = .page
            pageGaveNothing = false
        } else {
            pageGaveNothing = true
        }
    }

    private var fetching: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Fetching the full article")
        }
        .font(theme.metadata)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
        .padding(.bottom, 24)
    }

    /// Three controls : the star, the folder, and everything else.
    ///
    /// The star and the folder stand side by side because they are the two
    /// things a reader does to an article they want to keep, and they are not
    /// the same thing : one is a judgement, the other is a place. Side by side
    /// and differently marked is what says so ; one inside the other said the
    /// opposite.
    ///
    /// Every item put here separately is an item iOS may decide to fold into an
    /// overflow of its own, and an action inside an overflow inside a menu is an
    /// action nobody finds. That is not a hypothetical : signing in to a site
    /// was in one, and the reader who asked for the feature could not find it.
    /// Three is what this bar holds ; a fourth would want checking before it
    /// went in.
    @ToolbarContentBuilder
    private func toolbar(for article: Article) -> some ToolbarContent {
        // **A cross and not a way back.** The reader is not returning to a
        // screen they left : the page they came from never went anywhere, and
        // an arrow pointing at something already behind the article would be
        // describing a journey nobody made. A cross says what this is, which is
        // a thing put down.
        ToolbarItem(placement: .cancellationAction) {
            Button {
                dismiss()
            } label: {
                Label("Close", systemImage: "xmark")
            }
        }

        ToolbarItem {
            Button {
                Task { await model.toggleStarredCurrent() }
            } label: {
                // The same act as the first row of the collections menu, kept
                // as a button because it is the one a reader performs most and
                // one tap is what it is worth.
                Label(
                    article.isStarred ? "Remove from favourites" : "Add to favourites",
                    systemImage: article.isStarred ? "star.fill" : "star"
                )
            }
        }

        ToolbarItem {
            filing
        }

        ToolbarItem {
            Menu {
                if article.url != nil {
                    reading(article)
                    Divider()
                }

                Button {
                    Task { await model.markCurrentUnread() }
                } label: {
                    Label("Mark as unread", systemImage: "circle")
                }

                if let url = article.url {
                    ShareLink(item: url) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    Link(destination: url) {
                        Label("Open in browser", systemImage: "safari")
                    }
                }
            } label: {
                Label("Actions", systemImage: "ellipsis")
            }
        }
    }

    /// Which of the reader's own collections this article is in.
    ///
    /// **Two marks, two meanings, and they do not overlap.** The star is
    /// favourites and nothing else ; the folder is the collections the reader
    /// made and nothing else. Favourites was put in this menu once, on the
    /// theory that one list was simpler, and it was not : it made the star and
    /// the folder two ways of doing one thing, where they are two things. The
    /// star is a judgement about an article, the folder is a place to put it,
    /// and a reader who stars everything they file has said something they did
    /// not mean.
    ///
    /// Notes and the months are not here either, for a different reason. An
    /// article joins notes by being written on and joins a month by being
    /// kept : both are consequences, and a consequence is not a thing to
    /// choose from a menu. They are shown on the collections page and nowhere
    /// else.
    ///
    /// A submenu rather than a screen : filing something is a decision made in
    /// passing, and a page that had to be opened and dismissed for it would
    /// cost more than the decision is worth. Each row is a toggle, so taking an
    /// article out of one is where putting it in was.
    ///
    /// Filing keeps the article. An article has to be kept before it can be
    /// filed, and asking the reader to star it first would be asking them to
    /// say something they did not mean.
    @ViewBuilder
    private var filing: some View {
        Menu {
            ForEach(model.collectionNames, id: \.self) { name in
                let isIn = model.articleCollections.contains(name)
                Button {
                    Task {
                        if isIn {
                            await model.unfileArticle(from: name)
                        } else {
                            await model.fileArticle(in: name)
                        }
                    }
                } label: {
                    Label(name, systemImage: isIn ? "checkmark" : "folder")
                }
            }

            if !model.collectionNames.isEmpty { Divider() }

            Button {
                isNamingCollection = true
            } label: {
                Label("New collection", systemImage: "plus")
            }
        } label: {
            // The same words as the band it files into, so that the folder in
            // the toolbar and the shelf on the collections page are plainly one
            // thing, and neither of them is the star.
            Label("My collections", systemImage: "folder")
        }
    }

    /// What there is to read, and how to get the rest of it.
    @ViewBuilder
    private func reading(_ article: Article) -> some View {
        // Choosing is also saying so for next time : a reader who asks for the
        // whole article is not making a remark about this one article.
        if showing == .page {
            Button {
                showing = .feed
                model.articleBody = .feed
            } label: {
                Label("Show what the feed sent", systemImage: "doc.plaintext")
            }
        } else {
            Button {
                model.articleBody = .page
                Task { await showFullArticle() }
            } label: {
                Label("Show the full article", systemImage: "doc.richtext")
            }
            .disabled(model.isFetchingFullText)
        }

        // Always offered, never behind a failure the reader has to trigger
        // first. A site whose articles are behind a wall is one a reader knows
        // they subscribe to long before Flong finds out.
        Button {
            signingIn = true
        } label: {
            Label(
                model.hasSession(for: article.url) ? "Sign in again" : "Sign in to this site",
                systemImage: "key"
            )
        }
    }
}

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

    /// How far the page has been scrolled, which the wash behind it follows.
    ///
    /// An object rather than a number, so that a scroll moves the wash without
    /// rebuilding the page it is behind. See ``PageOffset``.
    @State private var offset = PageOffset()

    /// The story this page is about, found among the ones the front page holds.
    ///
    /// **The two halves are searched, and never joined.** Joining them is a
    /// third array of every story on the page, built to be looked through once
    /// and thrown away, and the body asked for it once for the picture and once
    /// more for every article under it.
    private var story: DigestStory? {
        model.digest.live.first { $0.id == storyID }
            ?? model.digest.stories.first { $0.id == storyID }
    }

    var body: some View {
        // Read once for the whole page. It was a computed property called from
        // the picture, from the head of the page and from every row under it,
        // which is one search of the front page per article per pass of the
        // body.
        let story = self.story

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
        // The same light as the front page, from this story's own picture,
        // which is the one the row that was tapped was carrying : the page
        // opens in the colour the reader pressed rather than in white. Behind
        // the scroll view for the reason set out in ``DigestScreen``.
        .background(alignment: .top) {
            PageWash(url: story?.imageURL, offset: offset)
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, position in
            offset.scrolled = position
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
                standfirst(summary, story: story)
            }

            facts(story)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
        .padding(.bottom, Editorial.rhythm)
    }

    /// What happened, at the size a whole page gives it rather than the size
    /// a row on the front page can spare, and the way back where a model
    /// wrote it.
    ///
    /// **The line is the control.** There was a row under it reading `written
    /// by the model`, which was the application talking about itself over the
    /// top of the news : a caption on every written summary, saying in words
    /// what the mark in front of the line already says. The words are gone and
    /// the mark stays, so what is left to press is the line the mark is about.
    /// A reader asking who wrote this presses this, which is where they were
    /// already looking.
    @ViewBuilder
    private func standfirst(_ summary: String, story: DigestStory) -> some View {
        let line = StorySummary(
            summary: summary,
            isGenerated: story.isGenerated,
            isTranslated: story.isTranslated,
            style: .body
        )

        if story.isGenerated {
            Button {
                isExplaining = true
            } label: {
                line.contentShape(.rect)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isExplaining, arrowEdge: .bottom) {
                explanation(carriedAcross: story.isTranslated)
            }
        } else {
            line
        }
    }

    /// What the model did, said plainly, with the way back.
    ///
    /// The trend the research names is an assistant that is present, optional
    /// and explainable rather than an oracle. A reader who does not want a
    /// written headline gets the article's own, in one tap, and the application
    /// does not argue. It is said here, where it was asked for, rather than
    /// printed on the page whether anybody wondered or not.
    private func explanation(carriedAcross: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Two marks, two answers : a line written here out of the articles
            // below is not the same claim as an editor's own line said in
            // another language, and a reader pressing the mark is asking which
            // of the two this is.
            Text(
                carriedAcross
                    ? "The headline and the line above are the publisher's own, translated on this device. Nothing was sent anywhere."
                    : "The headline and the line above were written on this device, from the articles below. Nothing was sent anywhere."
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

    private func facts(_ story: DigestStory) -> some View {
        HStack(spacing: 10) {
            if story.isLive {
                LiveDot()
            }

            // **The same marks the row carried, and now the same drawing.**
            // The sentence above was true of the intention and false of the
            // code : this page set them out by hand, at its own size and its
            // own spacing, so the row learnt to lap them and to keep its count
            // on one line and this did neither. See ``RoomMarks``.
            RoomMarks(marks: story.feedMarks, count: story.feedCount, side: 15)

            Text("\(story.articleCount) articles")

            Sparkline(values: story.arrivals)
                .frame(width: 44, height: 10)

            Spacer(minLength: 4)
            StoryMoment(date: story.lastAt)
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
    /// `Le Monde - Sport`. It is what the bar is titled with and what wears the
    /// mark in the byline. Nil where the reader is not subscribed to the group
    /// any more, and the address or the feed's own title stands in then.
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
                    ArticlePage(
                        html: ArticleDocument.html(
                            for: article,
                            publisher: publisher(of: article)?.name ?? article.domain ?? article.feedTitle,
                            mark: mark(of: publisher(of: article)),
                            showing: showing,
                            theme: theme
                        )
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
            // The page begins below the bar and runs to the bottom of the
            // screen : the words are the whole of what is on it, and there is
            // nothing above them for the controls to float over.
            .ignoresSafeArea(edges: .bottom)
            .tint(theme.accent(in: scheme))
            // **Nothing in the bar and nothing behind it.** A band of paper
            // with a name written across it is the top of a browser, and the
            // name in it was the publisher's, which the byline says two lines
            // lower in the page's own voice. What is left is the paper the
            // article is printed on, running to the top of the screen, and the
            // controls floating on the glass the system gives them.
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
            WaitingRing(side: 15)
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

                // Singling out whoever wrote it, from where the opinion is
                // actually formed : the reader has just finished the piece.
                // Inside this menu and not beside the star, since the star is a
                // judgement about the article and this is one about the person,
                // and since the bar holds three items and a fourth was not
                // worth the overflow it would earn.
                if let author = article.author, !author.isEmpty {
                    Button {
                        Task { await model.toggleFavouriteAuthorOfOpenedArticle() }
                    } label: {
                        Label(
                            model.articleAuthorIsFavourite
                                ? "Remove from favourite authors" : "Add to favourite authors",
                            systemImage: model.articleAuthorIsFavourite ? "star.slash" : "signature"
                        )
                    }
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
                let isMine = model.articleCollections.contains(name)
                // **Somebody else's filing counts too.** A collection the
                // reader shared holds what everybody in it put there, so a
                // piece a participant filed is in it whether or not this
                // device ever tagged it, and a row offering to file it again
                // would be offering to say a thing already said. Taking it
                // down is the owner's, which is what this reader is.
                let byOthers = model.articleCollectionsFiledByOthers[name] != nil
                Button {
                    Task {
                        if isMine {
                            await model.unfileArticle(from: name)
                        } else if byOthers {
                            await model.takeDownFromCollection(named: name)
                        } else {
                            await model.fileArticle(in: name)
                        }
                    }
                } label: {
                    Label(name, systemImage: isMine || byOthers ? "checkmark" : "folder")
                }
            }

            // The collections somebody else shared, under a heading of their
            // own. Filing into one sends the excerpt this feed published to
            // everybody in it, which is a different act from filing into a
            // shelf of the reader's own, and the menu should not pretend the
            // two are one row apart by accident.
            if !model.invitedCollections.isEmpty {
                Section("Shared with me") {
                    ForEach(model.invitedCollections) { shared in
                        let isIn = model.articleSharedCollections.contains(shared.zoneName)
                        let isMine = model.articleSharedFilings[shared.zoneName] != nil
                        Button {
                            Task {
                                if isMine {
                                    await model.unfileArticle(fromShared: shared.zoneName)
                                } else {
                                    await model.fileArticle(inShared: shared.zoneName)
                                }
                            }
                        } label: {
                            Label(
                                shared.title,
                                systemImage: isIn ? "checkmark" : "folder.badge.person.crop"
                            )
                        }
                        // **Ticked and not pressable**, for a piece somebody
                        // else filed into a collection the reader was only
                        // invited to. It is in there, which is what the tick
                        // says ; taking it out is the owner's and this reader
                        // is not the owner, so the row says so by not
                        // pretending otherwise.
                        .disabled(isIn && !isMine)
                    }
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

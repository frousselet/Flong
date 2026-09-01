//
//  AppModel.swift
//  Flong
//
//  Created by François Rousselet on 29/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CoreGraphics
import Foundation
import OSLog
import UserNotifications

/// An entry of the sidebar.
nonisolated struct SidebarItem: Identifiable, Hashable, Sendable {
    /// What an entry stands for. It is also the selection, so it holds nothing
    /// that changes when a feed is renamed.
    enum Kind: Hashable {
        case digest
        case unread, today, starred, all
        /// Every source of one publisher, keyed by the address they share.
        case group(String)
        case feed(UUID)
    }

    let kind: Kind
    /// The name of a group or a feed. Smart lists are named by the interface,
    /// in the reader's language.
    let title: String?
    /// How many articles it holds : every one of them, for a source or a
    /// publisher, and nothing at all for the views above them.
    ///
    /// It was what is unread, which is a number that only ever grows and that
    /// nobody owes their feeds. What the views above want said about them is
    /// their own name : a count beside `Tous les articles` is the size of the
    /// whole corpus, which answers nothing a reader was asking.
    let articleCount: Int
    /// Whether the reader singled this source out, when it is a source.
    var isFavourite = false
    var children: [SidebarItem] = []

    var id: Kind { kind }

    var filter: ArticleFilter {
        switch kind {
        case .unread: .unread
        case .today: .today
        case .starred: .starred
        // The digest reads the stories, not a view of the stream.
        case .digest, .all: .all
        // A group is its sources and nothing else. It is worked out from their
        // addresses rather than written on a row, so what it holds is asked of
        // the entry that carries them and never of the store.
        case .group: .feeds(children.compactMap { if case .feed(let id) = $0.kind { id } else { nil } })
        case .feed(let id): .feed(id)
        }
    }
}

/// Why something the reader asked for did not happen.
nonisolated enum AppFailure: Hashable, Identifiable, Sendable {
    case unreadableFile
    case notOPML
    case notSaved
    case invalidAddress
    case unreachableFeed
    case noFeedFound
    case notSignedIn
    case notDeleted
    case notRemoved

    var id: Self { self }

    var message: LocalizedStringResource {
        switch self {
        case .unreadableFile: "This file could not be opened."
        case .notOPML: "This file could not be read as OPML."
        case .notSaved: "The subscriptions could not be saved."
        case .invalidAddress: "This address is not one Flong can follow."
        case .unreachableFeed: "This address could not be reached."
        case .noFeedFound: "No feed was found at this address."
        case .notSignedIn: "This site left no session. Sign in on its page, then say so."
        case .notDeleted: "Not everything could be deleted. Try again in a moment."
        case .notRemoved: "This source could not be removed. Try again in a moment."
        }
    }
}

/// What set a catch-up going.
///
/// The triggers differ in four ways and in no others : whether every feed is
/// asked or only the ones politeness says are due, whether the data plan may be
/// spent, whether the model may be run, and whether the page is replaced before
/// the catch-up returns. Naming them here keeps those four answers in one place
/// instead of at six call sites that drift.
nonisolated enum CatchUp: Hashable, Sendable {
    /// The window opened.
    case launch
    /// The reader came back to it.
    case foreground
    /// The clock, while a window sits open.
    case clock
    /// The few seconds the system gave in the background.
    case background
    /// The reader asked, in so many words.
    case reader
    /// The reader pulled the front page down.
    case pull

    /// Whether every feed is asked, or only those that are due.
    ///
    /// Only when the reader asked, by the command or by the gesture. Everything
    /// automatic goes through the politeness of section 8, which is what keeps
    /// a reader's devices from becoming a burden on three hundred publishers.
    var asksEveryFeed: Bool { self == .reader || self == .pull }

    /// Whether a reader made a deliberate movement and is watching for it.
    ///
    /// One of these waits its turn rather than standing aside : a refusal
    /// nobody can see is, from where they are sitting, an application that did
    /// nothing when they asked.
    var isAskedFor: Bool { self == .reader || self == .pull }

    /// Whether nobody is waiting, and the reader's data plan is therefore not
    /// to be spent.
    var sparingly: Bool { self == .background }

    /// Whether the page is replaced before the catch-up returns.
    ///
    /// **Not under a pull, and not because the pull wants the page less.**
    /// SwiftUI holds the refresh control out until the gesture's work returns,
    /// so replacing the page's content as the last thing before returning has
    /// the scroll view begin its retraction against content it has never laid
    /// out. It was left to the watcher that follows the store, which reads back
    /// only when a change reaches it : a gesture that asked for the page and
    /// got it only if something happened to be written is not the command in
    /// the menu by another name. `DigestScreen` asks for the same read-back
    /// itself, a beat after the control has gone.
    var readsBackAtOnce: Bool { self != .pull }

    /// Whether this is a moment to run the on-device model.
    ///
    /// **Not in the twenty-five seconds of a background refresh.** The system
    /// rate-limits a backgrounded application's sessions hard, and a handful of
    /// refusals there used to silence the model for the whole of the process
    /// that followed. The model's work belongs to the full pass, at rest and on
    /// the mains, and to a window somebody is looking at.
    var mayRunTheModel: Bool { self != .background }
}

/// What the window shows, and what the reader can do to it.
///
/// One object for one window : the three levels of section 16 of the
/// specification move together, and splitting them would mean keeping three
/// copies of the same selection in step.
@Observable
final class AppModel {
    private let database: AppDatabase
    private let subscriptions: SubscriptionStore
    private let articles: ArticleStore
    private let collectionStore: CollectionStore
    private let authorStore: AuthorStore
    private let marks: MarkStore
    private let spotlight: SpotlightIndex
    private let digestService: DigestService
    private var cloud: CloudSync?
    private let refresher: FeedRefresh
    private let retention: Retention
    private let finder: FeedFinder
    private let opml: OPMLImport
    private let credentials: CredentialStoring
    private let sessions: SessionStoring
    private let preferences: Preferences
    private let announcer: Announcing
    private let locator: Locating
    private let sharing: CollectionSharing
    private let sharedCollections: SharedCollectionStore

    /// The whole stream, as files in the reader's own iCloud.
    ///
    /// Built once and held : finding the container asks the file coordinator,
    /// which is not a question to ask on every refresh.
    private var archive: StreamArchive?

    private(set) var sidebar: [SidebarItem] = []
    /// What each publisher is called and the mark it wears, by domain.
    private(set) var publishers: [String: SourceIdentity] = [:]
    private(set) var summaries: [ArticleSummary] = []

    /// How many articles arrived in each hour of the view being shown, keyed by
    /// the local hour. What the chart above the stream is drawn from.
    private(set) var hourlyCounts: [Date: Int] = [:]

    /// The squares on the collections page.
    private(set) var collections: [ArticleCollection] = []

    /// What is in the collection the reader has opened.
    ///
    /// Held here rather than in the screen alone so that a row tapped in a
    /// collection is one the window can place when it opens it.
    private(set) var collectionArticles: [ArticleSummary] = []

    /// Everybody who has signed something, for the authors page.
    private(set) var authors: [Author] = []
    /// The writer whose page is open, and what they signed.
    ///
    /// Read from the store rather than picked out of ``authors`` : the page can
    /// be opened on a favourite nothing is signed by yet, and it has to be able
    /// to say so and to undo the favourite.
    private(set) var openedAuthor: Author?
    private(set) var authorArticles: [ArticleSummary] = []

    private(set) var article: Article?
    /// Whether the page an article lives at is being fetched, so the reader is
    /// told rather than left wondering why the text is short.
    private(set) var isFetchingFullText = false
    /// Which feeds have a credential. The identifiers, never the secrets.
    private(set) var authenticatedFeeds: Set<UUID> = []
    /// The sites the reader has signed in to, for the screen that manages them.
    private(set) var subscribedSites: [SiteSession] = []

    /// Which body an article opens on, as the reader last chose.
    ///
    /// Kept in the iCloud key-value store, so a choice made on the phone is
    /// what the iPad opens on. Not CloudKit : a preference has no business in
    /// a record budget spent on articles.
    var articleBody = Preferences.ArticleBody.feed {
        didSet {
            guard articleBody != oldValue else { return }
            preferences.articleBody = articleBody
        }
    }

    /// How the application is set : the faces and the colours the reader chose.
    ///
    /// Kept beside the body an article opens on, in the same store and for the
    /// same reason : it is a decision about themselves rather than about a
    /// device, and it follows them to the next one.
    var theme = Theme.standard {
        didSet {
            guard theme != oldValue else { return }
            preferences.theme = theme
        }
    }
    // MARK: - What the reader is told

    /// Whether the reader wants to hear when a story opens.
    ///
    /// Set through ``setWantsNewStoryNotices(_:)`` rather than written to,
    /// since turning it on has to ask the system first and may be refused.
    private(set) var wantsNewStoryNotices = false

    /// What the system last said about this device, for the screen to explain
    /// a switch that will not stay on.
    private(set) var notificationStatus = UNAuthorizationStatus.notDetermined

    /// What is following the store, and the periodic refresh, for as long as
    /// there is a window.
    private var watching: Task<Void, Never>?
    private var ticking: Task<Void, Never>?
    /// The model's own work, which no gesture waits for.
    private var enriching: Task<Void, Never>?

    /// Whether the reader is looking at Flong right now.
    ///
    /// Nothing is announced while they are : a story appears on the page they
    /// are already reading, and a notice about something they watched happen
    /// is a notice to dismiss for nothing.
    var isReading = true

    // MARK: - Who is reading

    /// The reader's own name, which belongs to nobody else.
    ///
    /// There is no account and nothing to send it to : it is here so that a
    /// device the reader picks up looks like theirs, and it travels between
    /// their devices through their own iCloud like every other preference.
    var firstName = "" {
        didSet {
            guard firstName != oldValue else { return }
            preferences.firstName = firstName
        }
    }

    var lastName = "" {
        didSet {
            guard lastName != oldValue else { return }
            preferences.lastName = lastName
        }
    }

    /// The reader's own face, ready to draw.
    ///
    /// Decoded once and held, rather than decoded at each draw : it is on
    /// screen in the toolbar of every section, which is as often as anything
    /// gets drawn.
    private(set) var picture: CGImage?

    /// What stands in for a face when there is none.
    var initials: String? {
        ProfilePicture.initials(first: firstName, last: lastName)
    }

    /// The reader's name as one line, when they have given one.
    var name: String? {
        let whole = [firstName, lastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return whole.isEmpty ? nil : whole
    }

    /// Takes what the reader picked, scales it, and keeps the small version.
    ///
    /// Anything that is not an image is refused rather than stored : a file
    /// picked by mistake would otherwise become a face that never draws.
    @discardableResult
    func setPicture(_ data: Data?) -> Bool {
        guard let data else {
            preferences.picture = nil
            picture = nil
            return true
        }
        guard let scaled = ProfilePicture.scaled(data) else {
            Log.store.error("What was picked as a profile picture is not an image.")
            return false
        }
        preferences.picture = scaled
        picture = ProfilePicture.image(scaled)
        return true
    }

    /// Where the reader reads from, when they have chosen to say.
    ///
    /// A town and a country, and nothing finer : ``Place`` says why. It is
    /// nothing at all until the reader answers, which is the honest state and
    /// is never nagged at, exactly as an empty name is.
    ///
    /// Set through ``setPlace(_:)`` rather than written to, since choosing one
    /// and taking one back are the same operation on three keys in the store.
    private(set) var place: Place?

    /// Whether the device is being asked where it is.
    ///
    /// A fix from cold takes seconds, and a button that sat there saying
    /// nothing would be pressed again.
    private(set) var isLocating = false

    /// Keeps where the reader says they are, or takes it back.
    func setPlace(_ place: Place?) {
        self.place = place
        preferences.place = place
    }

    /// Asks the device where it is, and keeps the town it stands in.
    ///
    /// **What went wrong is handed back rather than posted to ``failure``.**
    /// The shell's alert is attached behind two sheets by the time this is
    /// called, and an alert presented from under a sheet is an alert nobody
    /// sees. The screen that asked is the screen that says so, and the reader
    /// stays where they were, in front of a search that needs no permission.
    ///
    /// **A refusal changes nothing else.** Whatever the reader had chosen
    /// before stays chosen : an answer they gave by hand is not undone by the
    /// system declining to give another one.
    func locate() async -> PlaceFailure? {
        guard !isLocating else { return nil }
        isLocating = true
        defer { isLocating = false }

        do {
            setPlace(try await locator.here())
            return nil
        } catch let refusal as PlaceFailure {
            Log.place.notice("The device did not say where it is : \(String(describing: refusal), privacy: .public)")
            return refusal
        } catch {
            Log.place.error("The device could not say where it is : \(error, privacy: .public)")
            return .unavailable
        }
    }

    /// Reads the name and the face back from what has been kept.
    private func loadProfile() {
        firstName = preferences.firstName
        lastName = preferences.lastName
        picture = preferences.picture.flatMap(ProfilePicture.image)
        place = preferences.place
    }

    private(set) var isRefreshing = false
    private(set) var feedCount = 0

    /// Runs one piece of work that asks the publishers, and only ever one.
    ///
    /// **One gate over every path that fetches.** There were three ways in and
    /// two of them shared a flag : a clock tick took ``isRefreshing``, the full
    /// pass took nothing at all, and the long jobs took a flag of their own. So
    /// the nightly pass and the five-minute clock could ask three hundred
    /// publishers the same question at the same second, each unaware of the
    /// other, and the reader's own command could land in the middle of both.
    /// The scheduler already refuses to start two of its own passes at once ;
    /// this is the same rule where the two halves actually meet, which is here.
    ///
    /// The gate is taken by the outermost entry point only. What runs inside a
    /// pass, the first fetch and the vectors and the model's own work, is that
    /// pass's business and asks nobody.
    ///
    /// Being observable, it is also what greys the reader's own `Refresh` while
    /// anything is running, so the command cannot start a second one either.
    /// How long something the reader asked for waits its turn.
    ///
    /// **A gesture is not refused in silence.** Standing aside is right for a
    /// clock tick, which nobody watched and which comes round again in five
    /// minutes. It is wrong for a pull : the reader made a deliberate movement,
    /// the control comes straight back out, and as far as they can tell nothing
    /// happened at all. So a refresh they asked for waits for the one already
    /// running and then takes its turn, and the control stays out for as long
    /// as there is work, which is what they were watching for.
    static let patienceOfAGesture = Duration.seconds(30)

    @discardableResult
    private func exclusively(_ name: StaticString, waiting: Bool = false, _ work: () async -> Void) async -> Bool {
        if isRefreshing, waiting {
            let until = ContinuousClock.now + AppModel.patienceOfAGesture
            while isRefreshing, ContinuousClock.now < until, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(150))
            }
        }

        guard !isRefreshing else {
            Log.fetch.info("\(name, privacy: .public) stood aside for a refresh already running")
            return false
        }
        isRefreshing = true
        defer { isRefreshing = false }

        await work()
        return true
    }

    // MARK: - What the machinery is doing

    /// The pass as the page shows it, held back and held on by the two floors.
    private(set) var work: WorkPlan?

    /// The pass as it actually stands, whether or not it is on screen yet.
    private var plan: WorkPlan?

    /// What the page shows, which folds in the work iCloud does on its own.
    ///
    /// `CKSyncEngine` decides for itself when to send and when to fetch, so an
    /// exchange nothing here asked for still moves ``syncStatus`` and is still
    /// worth saying : a reader watching their page change wants to know it is
    /// their iPad talking and not a publisher.
    var currentWork: WorkPlan? {
        if let work { return work }
        if case .working = syncStatus { return WorkPlan([.synchronizing]) }
        return nil
    }

    /// Nothing shorter than this is seen at all.
    ///
    /// A catch-up that finds nothing due returns in a few milliseconds, and a
    /// line that appeared and left inside one frame is a flicker rather than
    /// information.
    static let workAppearsAfter = Duration.milliseconds(250)

    /// Anything that is seen at all is seen for at least this long.
    ///
    /// The same fault the other way : a line that appeared for good reason and
    /// left before it could be read told the reader nothing and made the page
    /// twitch.
    static let workStaysFor = Duration.milliseconds(700)

    private var workShownAt: ContinuousClock.Instant?
    private var showingWork: Task<Void, Never>?
    private var clearingWork: Task<Void, Never>?

    /// Begins a pass, having asked the store what it is likely to be made of.
    ///
    /// **The whole pass, declared before it starts.** Every stage used to bring
    /// its own bar, so one pass ran from nothing to full five times over, and a
    /// reader doing one thing and waiting for one answer watched an application
    /// that kept starting over. One bar crosses the lot now, and the words
    /// above it change.
    ///
    /// The counts are three cheap questions the store already answers. They are
    /// asked before the feeds are fetched, so what arrives during the pass is
    /// not in them ; each stage corrects its own share as it learns better, and
    /// the bar is held to the furthest it has been.
    /// - Parameter atOnce: whether the line is shown without the quarter second
    ///   that keeps an automatic pass from flickering. A reader who pulled or
    ///   pressed is watching for an answer, and a beat of nothing between the
    ///   gesture and the line is the line arriving from nowhere.
    func beginWork(_ stages: [WorkPhase], atOnce: Bool = false) async {
        // A pass already under way has already declared what it is made of, and
        // the inner steps of one are not passes of their own : the repair
        // declares the whole of itself and the ordinary pass inside it adds
        // nothing.
        guard plan == nil else { return }

        // Nothing is guessed for the feeds : `FeedRefresh` says how many it is
        // about to ask for before it asks for any of them, which lands well
        // inside the quarter second before the line appears at all.
        let onThePage = (try? await DigestStore(database).storyCount()) ?? 0
        show(WorkPlan(stages, costing: await costsOfTheModelsWork(stages, floor: onThePage)), atOnce: atOnce)
    }

    /// What the model's own work is likely to cost, asked of the store, which
    /// already answers all of it.
    ///
    /// - Parameter floor: what to fall back on where a queue answers nought.
    ///   Before a pass has fetched anything, nothing is waiting for a headline
    ///   and both of the model's stages are worth nothing : the fetching then
    ///   owns the whole bar, and finishing it leaves the rule full with two
    ///   stages still to go. The stories already on the page are the right
    ///   order of magnitude for the ones about to be, and once grouping is over
    ///   the real counts replace them.
    private func costsOfTheModelsWork(_ stages: [WorkPhase], floor: Int = 0) async -> [WorkPhase: Int] {
        var costs: [WorkPhase: Int] = [:]
        if stages.contains(.writing) {
            costs[.writing] = max((try? await BriefStoriesJob(database).remaining()) ?? 0, floor)
        }
        if stages.contains(.filing) {
            costs[.filing] = max((try? await FileStoriesJob(database).remaining()) ?? 0, floor)
        }
        if stages.contains(.indexing) {
            costs[.indexing] = (try? await VectorStore(database).outstandingCount()) ?? 0
        }
        return costs
    }

    /// Moves the pass to a stage, which changes the words and not the bar.
    func moveWork(to phase: WorkPhase) {
        guard plan != nil else { return }
        plan?.begin(phase)
        mirror()
    }

    /// Says the pass is over, once it has been on screen long enough to read.
    func endWork() {
        plan = nil
        showingWork?.cancel()
        showingWork = nil

        guard work != nil, let shownAt = workShownAt else {
            work = nil
            return
        }

        let left = AppModel.workStaysFor - shownAt.duration(to: .now)
        guard left > .zero else {
            work = nil
            workShownAt = nil
            return
        }

        clearingWork?.cancel()
        clearingWork = Task { [weak self] in
            try? await Task.sleep(for: left)
            guard !Task.isCancelled else { return }
            self?.work = nil
            self?.workShownAt = nil
        }
    }

    /// Puts a pass up, after the floor that stops it flickering.
    private func show(_ plan: WorkPlan, atOnce: Bool = false) {
        clearingWork?.cancel()
        clearingWork = nil
        self.plan = plan

        guard work == nil else {
            work = plan
            return
        }

        // **What the reader asked for is answered on the beat.** The quarter
        // second below is there so a pass that finds nothing due does not
        // flicker a line onto a page nobody was watching. A pull or a press is
        // watched : the finger is still on the glass, and a beat of nothing
        // between the gesture and the line is the line arriving from nowhere.
        if atOnce {
            showingWork?.cancel()
            showingWork = nil
            workShownAt = .now
            work = plan
            return
        }

        guard showingWork == nil else { return }

        // The plan is read when the line appears rather than when it was asked
        // for, so a burst that passes through three stages inside the quarter
        // second shows the one it has reached.
        showingWork = Task { [weak self] in
            try? await Task.sleep(for: AppModel.workAppearsAfter)
            guard !Task.isCancelled, let self, let plan = self.plan else { return }
            workShownAt = .now
            work = plan
            showingWork = nil
        }
    }

    private func mirror() {
        guard work != nil else { return }
        work = plan
    }

    /// Moves the stage running along, and says nothing when the pass has moved
    /// on without it.
    private func advance(_ phase: WorkPhase, done: Int, total: Int) {
        guard plan?.phase == phase else { return }
        plan?.advance(done: done, total: total)
        mirror()
    }

    /// A progress callback for the jobs, which are all `nonisolated`.
    private func progress(of phase: WorkPhase) -> @Sendable (Int, Int) -> Void {
        { [weak self] done, total in
            Task { @MainActor [weak self] in self?.advance(phase, done: done, total: total) }
        }
    }

    /// What synchronization is doing, in terms the sidebar can show.
    private(set) var syncStatus = SyncStatus.idle(lastSynchronized: nil)

    /// What is left of the long work : feeds never fetched, articles with no
    /// vector. Both are questions the store answers, which is what makes the
    /// work resumable without a checkpoint to keep in step.
    private(set) var outstandingFeeds = 0
    private(set) var outstandingVectors = 0
    private(set) var isWorking = false

    var hasOutstandingWork: Bool { outstandingFeeds + outstandingVectors > 0 }

    /// Whether the list is showing the answer to a query rather than a view.
    var isShowingResults: Bool { query != nil }

    var selection: SidebarItem.Kind? = .all
    var selectedArticle: UUID?

    /// The summary of the last import, until the reader dismisses it.
    var report: OPMLImportReport?
    var failure: AppFailure?

    /// What is in the search field.
    ///
    /// Results follow it as it is typed, after a pause short enough not to be
    /// felt and long enough that a word is not searched for four times while it
    /// is being written.
    var searchText = "" {
        didSet {
            guard searchText != oldValue else { return }
            search?.cancel()
            search = Task {
                try? await Task.sleep(for: .milliseconds(150))
                guard !Task.isCancelled else { return }
                await loadArticles()
            }
        }
    }

    private var search: Task<Void, Never>?

    /// The query as it is understood, or `nil` when the field is empty.
    var query: QueryNode? {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let node = QueryParser.parse(trimmed)
        return node == .all ? nil : node
    }

    /// What to offer while a query is being typed.
    ///
    /// Section 12 asks for completion of feed and tag names, which are the two
    /// things nobody remembers the exact spelling of.
    var searchSuggestions: [String] {
        guard let last = searchText.split(separator: " ").last.map(String.init) else { return [] }

        let names: [String]
        let prefix = searchText.dropLast(last.count)

        if last.lowercased().hasPrefix("feed:") {
            names = completions(for: String(last.dropFirst(5)), in: feedTitles)
        } else if last.lowercased().hasPrefix("tag:") {
            names = completions(for: String(last.dropFirst(4)), in: tagPaths)
        } else {
            return []
        }

        let field = last.prefix(while: { $0 != ":" })
        return names.map { name in
            let value = name.contains(" ") ? "\"\(name)\"" : name
            return prefix + field + ":" + value
        }
    }

    private func completions(for text: String, in names: [String]) -> [String] {
        let text = text.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        guard !names.isEmpty else { return [] }
        guard !text.isEmpty else { return Array(names.prefix(6)) }

        return names.filter { $0.localizedCaseInsensitiveContains(text) }.prefix(6).map { $0 }
    }

    private var feedTitles: [String] {
        sidebar.flatMap { [$0] + $0.children }.compactMap { item in
            if case .feed = item.kind { item.title } else { nil }
        }
    }

    /// The tags there are to complete, which are the collections the reader
    /// filled article by article.
    ///
    /// It used to be the folder paths as well, since a folder was a view over a
    /// root tag. The folders are gone, and a source belongs to its publisher
    /// rather than to a filing : `feed:` and `site:` are what narrow a search to
    /// where an article came from.
    private var tagPaths: [String] {
        collections.compactMap { collection in
            if case .made(let name) = collection.kind { CollectionStore.path(of: name) } else { nil }
        }
    }

    init(
        database: AppDatabase,
        fetcher: FeedFetcher = FeedFetcher(),
        credentials: CredentialStoring = KeychainCredentials(),
        sessions: SessionStoring = KeychainSessions(),
        preferences: Preferences = Preferences(),
        announcer: Announcing = Notifier(),
        locator: Locating = DeviceLocator()
    ) {
        self.database = database
        self.credentials = credentials
        self.sessions = sessions
        self.preferences = preferences
        self.announcer = announcer
        self.locator = locator
        self.articleBody = preferences.articleBody
        self.theme = preferences.theme
        self.wantsNewStoryNotices = preferences.wantsNewStoryNotices
        self.firstName = preferences.firstName
        self.lastName = preferences.lastName
        self.picture = preferences.picture.flatMap(ProfilePicture.image)
        self.place = preferences.place
        let subscriptions = SubscriptionStore(database)
        self.subscriptions = subscriptions
        let articles = ArticleStore(database)
        self.articles = articles
        self.collectionStore = CollectionStore(database)
        self.sharing = CollectionSharing(database: database)
        self.sharedCollections = SharedCollectionStore(database)
        self.authorStore = AuthorStore(database)
        self.marks = MarkStore(database)
        self.spotlight = SpotlightIndex(articles, subscriptions)
        self.digestService = DigestService(database)
        self.refresher = FeedRefresh(database: database, fetcher: fetcher, credentials: credentials)
        self.retention = Retention(database)
        self.finder = FeedFinder(fetcher: fetcher)
        self.opml = OPMLImport(subscriptions)
    }

    /// The fixed views, which every reader has whatever they follow.
    var smartLists: [SidebarItem] {
        sidebar.filter { item in
            switch item.kind {
            case .digest, .unread, .today, .starred, .all: true
            default: false
            }
        }
    }

    /// The publishers followed, each holding the sources it serves.
    var sourceGroups: [SidebarItem] {
        sidebar.filter { item in
            if case .group = item.kind { true } else { false }
        }
    }

    var filter: ArticleFilter {
        sidebar.flatMap { [$0] + $0.children }.first { $0.kind == selection }?.filter ?? .unread
    }

    /// Whether Flong follows anything at all, which is what the first launch
    /// of section 16 turns on.
    var isEmpty: Bool { feedCount == 0 }

    // MARK: - Loading

    // MARK: - Keeping up on its own

    /// Follows the store and the clock, so the reader never has to pull.
    ///
    /// Two different things, and both are needed. Following the store is what
    /// shows a change that arrived from somewhere else : another device through
    /// iCloud, a background refresh, an archive read in. The clock is what asks
    /// the publishers, which nothing else does while a window sits open.
    func keepUp() {
        guard watching == nil else { return }

        watching = Task { [weak self] in
            guard let database = self?.database else { return }

            for await _ in StoreChanges.ticks(in: database) {
                // Let a burst settle. Everything that arrives during the wait
                // and during the reload collapses into one further tick.
                try? await Task.sleep(for: StoreChanges.settling)

                // A refresh the reader asked for writes throughout, and
                // SwiftUI holds its control out until the gesture's work
                // returns. Nothing may move under it : the page is read back
                // once the gesture is over and the control has had time to
                // retract, which is also the reload that gesture needs.
                var waited = false
                while await self?.isRefreshing == true {
                    waited = true
                    try? await Task.sleep(for: StoreChanges.settling)
                }
                if waited { try? await Task.sleep(for: StoreChanges.settling) }

                await self?.reloadWhatIsShown()
            }

            // The stream ended, which means the observation could not be
            // started at all. Letting go of the task is what allows another
            // call to try again : the guard above reads `watching`, so leaving
            // a finished task in it left the window deaf for the rest of the
            // process with nothing but a log line to show for it. Coming back
            // to the foreground calls this again.
            await self?.stopWatching()
        }

        startTheClock(.launch)
    }

    private func stopWatching() {
        guard watching != nil else { return }
        watching = nil
        Log.store.notice("The window stopped following the store, and will try again")
    }

    /// The clock that asks the publishers while a window sits open.
    ///
    /// **It acts first and sleeps after.** It slept first, so a window that had
    /// just come back to the front waited a whole interval before anything was
    /// asked ; and a tick that fell while the window was away was spent on
    /// nothing and cost another whole interval after that.
    ///
    /// Restarted rather than left running when the reader comes back, so
    /// returning to the application is itself a tick and the next one is
    /// counted from then.
    func startTheClock(_ reason: CatchUp = .foreground) {
        ticking?.cancel()
        ticking = Task { [weak self] in
            var reason = reason
            while !Task.isCancelled {
                if let self, isReading { await catchUp(reason) }
                reason = .clock
                try? await Task.sleep(for: .seconds(AppModel.foregroundInterval))
            }
        }
    }

    /// Stops following, when the window that was following is gone.
    deinit {
        watching?.cancel()
        ticking?.cancel()
        enriching?.cancel()
        showingWork?.cancel()
        clearingWork?.cancel()
    }

    /// How often an open window asks the publishers.
    ///
    /// A window open all day asked nobody anything : the only foreground
    /// refresh was returning to the front, and a Mac window that never leaves
    /// the front never returns to it.
    ///
    /// **Five minutes, and it costs the publishers nothing.** What a publisher
    /// sees is decided per feed by ``RefreshSchedule/isDue(_:now:stagger:)``,
    /// whose floor is fifteen minutes ; a tick is a question put to the store,
    /// and most ticks find nothing due and send no request at all. What
    /// halving the tick buys is the wait between a feed becoming due and being
    /// asked, which is the only part of the delay the application controls.
    static let foregroundInterval: TimeInterval = 5 * 60

    /// Reads back what the window is showing, after something changed it.
    ///
    /// **Not while an article is open.** Opening one marks it read, and a list
    /// that reloaded under it would drop the article out of the unread view the
    /// reader is about to come back to. The list is read again the moment they
    /// are looking at it.
    private func reloadWhatIsShown() async {
        await loadSidebar()
        await loadDigest()
        await loadCollections()
        if selectedArticle == nil { await loadArticles() }
    }

    func load() async {
        await loadSidebar()
        await loadArticles()
        // The front page is part of what the window shows, and this is the
        // read-back every path that writes ends with. Leaving it out is how a
        // pass could fetch, group and announce a page of new stories and leave
        // the reader looking at yesterday's.
        await loadDigest()
        await loadCredentials()
        // The search field completes tag names off them, so they are part of
        // what a window holds and not only of what the collections page shows.
        await loadCollections()
        // Another device may have changed them while this one was away.
        preferences.synchronize()
        articleBody = preferences.articleBody
        theme = preferences.theme
        loadProfile()
        await countOutstandingWork()
    }

    // MARK: - The digest

    /// Which subject the front page is narrowed to, if any.
    var digestTopic = DigestTopic.frontPage {
        didSet {
            guard digestTopic != oldValue else { return }
            Task { await loadDigest() }
        }
    }

    private(set) var digest = Digest()
    /// The articles of the story the reader opened, and of that one only : a
    /// digest that loaded every article of every story would be the list it
    /// exists to replace.
    private(set) var storyArticles: [UUID: [ArticleSummary]] = [:]
    var openStory: UUID?

    func loadDigest() async {
        do {
            var fetched = try await digestService.digest(digestTopic)

            // A subject the page no longer has is a page narrowed to nothing,
            // which happens when the last story under it ages out. Falling back
            // to the front page beats an empty page with no way off it.
            if let name = digestTopic.name, !fetched.topics.contains(name) {
                fetched = try await digestService.digest(.frontPage)
                digestTopic = .frontPage
            }
            // Only when it differs. `@Observable` notifies on the assignment
            // and not on the value, so writing back an identical page rebuilds
            // the list under a reader who is scrolled into it, and a pinned
            // header rebuilt mid-gesture is a page that does not settle back
            // where it was.
            if fetched != digest { digest = fetched }

            // **The front page, and only the front page.** What Spotlight holds
            // is what a reader would find on the digest, no more and no less,
            // and narrowing to one subject is a question about the window they
            // are looking at rather than about what the system search should be
            // able to find.
            if digestTopic == .frontPage { await handToSpotlight(fetched.all) }
        } catch {
            Log.enrich.error("The digest could not be read : \(error, privacy: .public)")
        }
    }

    /// What Spotlight was last told the front page holds.
    ///
    /// `nil` is `nobody has told it anything yet`, which is not the same as an
    /// empty page : a launch that finds no stories still has to empty out the
    /// ones the last one left behind.
    private var indexedStories: [DigestStory]?

    /// Hands the front page to Spotlight, unless it is already holding it.
    ///
    /// The digest is read back on every change the store notices, and almost
    /// none of those changes are the page : an article marked read is a reason
    /// to read the digest again and no reason at all to write sixty items to
    /// the system index.
    private func handToSpotlight(_ stories: [DigestStory]) async {
        guard stories != indexedStories else { return }

        do {
            try await spotlight.index(stories: stories)
            indexedStories = stories
        } catch {
            Log.index.error("The stories could not be handed to Spotlight : \(error, privacy: .public)")
        }
    }

    /// Groups what has arrived, names the new stories, and shows the result.
    /// Groups what has arrived and shows it, then writes the headlines behind.
    ///
    /// The page appears as soon as the grouping is done. Naming is a call to a
    /// model per story, and a page that waited for it would be a page that
    /// arrives a second late to say what it already knew.
    func rebuildDigest() async {
        moveWork(to: .grouping)
        await digestService.buildStories()
        await loadDigest()

        // The headlines and the subjects, turn about and under a bound. They
        // ran one after the other and unbounded, which is how a page could
        // arrive fully written and filed under nothing at all.
        enrich()
    }

    // MARK: - Telling the reader

    /// Says whether the reader wants the notices, asking the system when they
    /// do.
    ///
    /// The switch is the request. A reader who has refused Flong at the system
    /// level cannot be talked round from here : the switch goes back where it
    /// was and the screen says where the answer lives, which is the only thing
    /// an application may honestly do about a refusal.
    func setWantsNewStoryNotices(_ wanted: Bool) async {
        guard wanted else {
            preferences.wantsNewStoryNotices = false
            wantsNewStoryNotices = false
            return
        }

        let allowed = await announcer.authorize()
        notificationStatus = await announcer.status()
        guard allowed else {
            wantsNewStoryNotices = false
            return
        }

        // From now, and not from the beginning of time : the stories already on
        // the page are not news to a reader who has been reading them.
        preferences.storiesAnnouncedAt = Date()
        preferences.wantsNewStoryNotices = true
        wantsNewStoryNotices = true
    }

    func refreshNotificationStatus() async {
        notificationStatus = await announcer.status()
    }

    /// Tells the reader about the stories that have just opened.
    ///
    /// **The watermark moves whether anything was said or not.** A story the
    /// reader watched arrive, on a page they had open, is a story they know
    /// about ; keeping it for later would mean telling them tomorrow about
    /// something they saw today. What the watermark records is that the story
    /// reached them, not that a notification was posted.
    func announceNewStories() async {
        guard wantsNewStoryNotices, let since = preferences.storiesAnnouncedAt else { return }

        let opened = (try? await DigestStore(database).opened(since: since)) ?? []
        preferences.storiesAnnouncedAt = Date()

        guard !isReading, let announcement = Announcement.newStories(opened) else { return }
        await announcer.post(announcement)
    }

    /// Every subject there is, for the screen that manages them.
    private(set) var knownTopics: [TopicPreferences.Known] = []

    /// Writes down the sections every reader has, once, at the first launch
    /// that finds them missing.
    ///
    /// Not in a migration : the names are in the reader's language, and a
    /// migration runs before anything has asked what that is.
    func seedStandardTopics() async {
        try? await TopicPreferences(database).seedStandards()
    }

    func loadKnownTopics() async {
        knownTopics = (try? await TopicPreferences(database).known()) ?? []
    }

    /// Sets a subject to a direction rather than to a number : down, nothing,
    /// or up. The pill is where a reader nudges ; this is where they decide.
    func setPreference(of topic: String, to direction: Int) async {
        let preferences = TopicPreferences(database)
        try? await preferences.clear(topic)
        if direction != 0 {
            try? await preferences.adjust(topic, by: direction)
        }

        await loadKnownTopics()
        await loadDigest()
    }

    /// Adds a subject of the reader's own, which the model then files under.
    func addTopic(_ name: String) async {
        try? await TopicPreferences(database).add(name)
        await loadKnownTopics()
    }

    /// Removes a subject the reader wrote, and everything hanging off it.
    func removeTopic(_ name: String) async {
        try? await TopicPreferences(database).remove(name)
        await loadKnownTopics()
        await loadDigest()
    }

    /// Takes back everything the reader has said about every subject.
    func forgetEveryPreference() async {
        try? await TopicPreferences(database).clearAll()
        await loadKnownTopics()
        await loadDigest()
    }

    /// Says the reader wants more of a subject, or less of it.
    ///
    /// The page is read again straight away : a preference nobody can see the
    /// effect of is a preference nobody trusts.
    func prefer(_ topic: String, by delta: Int) async {
        try? await TopicPreferences(database).adjust(topic, by: delta)
        await loadDigest()
        await loadKnownTopics()
    }

    /// Takes back what was said about a subject.
    func forgetPreference(of topic: String) async {
        try? await TopicPreferences(database).clear(topic)
        await loadDigest()
        await loadKnownTopics()
    }

    /// Loads a story's articles for its own page.
    func openStoryPage(_ storyID: UUID) async {
        guard storyArticles[storyID] == nil else { return }
        storyArticles[storyID] = (try? await digestService.articles(of: storyID)) ?? []
    }

    /// Gives a story back the headline of its own article.
    ///
    /// The assistant is optional : a reader who does not want a written headline
    /// says so once and gets the article's, and the application does not argue.
    func dropGeneratedBrief(of storyID: UUID) async {
        await digestService.dropBrief(of: storyID)
        await loadDigest()
    }

    /// Opens a story, or closes the one that was open.
    func toggle(_ story: DigestStory) async {
        guard openStory != story.id else {
            openStory = nil
            return
        }
        openStory = story.id

        guard storyArticles[story.id] == nil else { return }
        storyArticles[story.id] = (try? await digestService.articles(of: story.id)) ?? []
    }

    // MARK: - The long work

    /// Counts what is left to do, so the reader is told rather than left
    /// wondering why an import looks half done.
    func countOutstandingWork() async {
        outstandingFeeds = (try? await FirstFetchJob(database).remaining()) ?? 0
        outstandingVectors = (try? await VectorStore(database).outstandingCount()) ?? 0
    }

    /// Fetches the feeds that have never been fetched, then vectorizes what has
    /// been kept, for as long as it is given.
    ///
    /// Every batch stands alone. Stopping between two of them loses nothing, and
    /// the next run picks up exactly where this one left off, which is what
    /// section 15 means by resumable.
    func doOutstandingWork(until deadline: Date? = nil) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        await beginWork([.fetching, .indexing])
        moveWork(to: .fetching)
        await JobRunner(FirstFetchJob(database))
            .run(until: deadline, onProgress: progress(of: .fetching))

        let vectorize = VectorizeJob(database) { [weak self] items in
            // A vector computed here spares every other device the same work.
            await self?.enqueueVectors(for: items)
        }
        moveWork(to: .indexing)
        await JobRunner(vectorize).run(until: deadline, onProgress: progress(of: .indexing))

        await countOutstandingWork()
        await load()
    }

    /// Starts the long work with the system watching over it.
    ///
    /// On iOS the system is asked to see it through and shows its own progress.
    /// A refusal is not a failure : the work carries on here instead, and again
    /// at the next launch, since it was written to be resumable anyway.
    func finishSetup() async {
        let accepted = BackgroundScheduler.requestContinuedProcessing(
            title: String(localized: "Finishing the setup"),
            subtitle: String(localized: "Fetching your feeds")
        )
        guard !accepted else { return }

        await exclusively("Finishing the setup") { await self.doOutstandingWork() }
        endWork()
    }

    private func enqueueVectors(for entries: [Entry]) async {
        await enqueueMarks(for: entries.map(\.id))
    }

    /// What a background refresh does with the half minute it is given.
    ///
    /// Sparingly : nobody is waiting for it, so it is not worth a megabyte of
    /// the reader's data plan. The feeds come back in the order of how overdue
    /// each is against its own rhythm, so the budget goes to what is most
    /// likely to have something and nothing is left permanently at the back.
    ///
    /// **It groups what it fetched.** It used to fetch and stop there, so a
    /// phone in a pocket collected articles all day and the front page gained
    /// nothing from any of it until the next full pass or the next cold launch.
    /// Grouping is plain SQL and costs a fraction of what the fetching just
    /// cost.
    ///
    /// The read states go out first. They are a few bytes, the other devices
    /// are waiting for them, and a pass whose budget runs out during the
    /// fetching must not be a pass that swallowed them.
    func backgroundRefresh() async {
        let deadline = Date().addingTimeInterval(BackgroundScheduler.refreshBudget)
        await cloud?.enqueueReadStates()

        await catchUp(.background, until: deadline)
        await JobRunner(FirstFetchJob(database)).run(until: deadline)
    }

    /// The whole of the work, at rest and on the mains.
    ///
    /// **Every feed, not the ones that are due.** The half-hourly refresh asks
    /// only what the politeness of section 8 says may be asked, which is right
    /// for a phone in a pocket and leaves a quiet feed unasked for days. This
    /// runs when nobody is waiting for anything, which is the moment to catch
    /// the rest.
    ///
    /// It did not refresh at all before : it enriched, purged, indexed and
    /// exchanged what was already here, and the reader who asked for a full
    /// refresh on charge was asking for the one thing this did not do.
    ///
    /// The order is what makes it one pass rather than several. The feeds come
    /// first, so the digest, the vectors and the index all work on what has
    /// just arrived rather than on what was here this morning ; iCloud comes
    /// last, so what goes out is the whole of it.
    func backgroundProcessing() async {
        // Whatever made the model fail hours ago is worth trying again now :
        // the assets may have finished downloading, the reader may have
        // switched Apple Intelligence on, a rate limit has certainly lifted.
        OnDeviceModel.reconsider()
        await exclusively("The full pass") { await self.fullPass() }
    }

    /// Every feed, then everything that is derived from what they brought, then
    /// iCloud. Named step by step, since this is the pass a reader watches.
    private func fullPass() async {
        await beginWork([
            .fetching, .indexing, .grouping, .writing, .filing, .tidying, .synchronizing, .exchanging,
        ])
        moveWork(to: .fetching)
        let summary = await refresher.refreshAll(onProgress: progress(of: .fetching))
        Log.fetch.notice("Full pass : \(summary.newArticles) new articles from \(summary.refreshed) feeds")

        await doOutstandingWork()

        moveWork(to: .grouping)
        await digestService.buildStories()

        // Generous, and bounded all the same. The pass has minutes rather than
        // seconds, and the model's two halves share whatever it turns out to
        // have : unbounded, the headlines took the lot and the subjects were
        // never asked for.
        await digestService.enrich(
            until: Date().addingTimeInterval(BackgroundScheduler.fullPassBudget),
            onWriting: progress(of: .writing),
            onFiling: progress(of: .filing),
            onPhase: { [weak self] phase in
                Task { @MainActor [weak self] in self?.moveWork(to: phase) }
            }
        )
        await announceNewStories()

        moveWork(to: .tidying)
        _ = try? await Retention(database).purge()
        try? await SearchIndex(database).optimize()

        moveWork(to: .synchronizing)
        await cloud?.enqueueReadStates()
        await cloud?.enqueueCatchUp()

        moveWork(to: .exchanging)
        await exchangeArchives()

        // The whole of what the window shows, and not only part of it. The
        // pass ends by reading back the page it has just built, so the page a
        // reader opens in the morning is that one rather than last night's.
        await reloadWhatIsShown()
        await countOutstandingWork()
        endWork()
    }

    /// Starts synchronizing with the reader's own iCloud.
    ///
    /// No account is not an error : Flong is fully usable on one device without
    /// one, and the sidebar says nothing rather than complaining.
    func startSync() async {
        guard cloud == nil else { return }

        let cloud = CloudSync(database: database) { [weak self] status in
            Task { @MainActor [weak self] in self?.syncStatus = status }
        }
        self.cloud = cloud
        await cloud.start()
    }

    /// Queues everything and exchanges it, whatever iCloud already has.
    ///
    /// **A development command, and only there.** The engine decides for itself
    /// when to send and when to fetch, and it is right far more often than a
    /// button would be : what this is for is watching an exchange happen on
    /// demand while something is being built, not for a reader who thinks
    /// their iPad is behind.
    ///
    /// It starts from nothing rather than from where the last exchange left
    /// off, which is the repair path and is expensive : a few thousand records
    /// against a budget of three thousand. That is the point of it and the
    /// reason it does not ship.
    ///
    /// **Everything, and in both directions.** Queueing every local record only
    /// ever sent : the engine still held its change tokens, so it asked the
    /// server what had changed since them and was told, correctly, that nothing
    /// had. A device whose copy had drifted learned nothing from that, which is
    /// the one thing this command exists to fix. The tokens, the tags the server
    /// gave each record, and the ledger of archives already read are all
    /// forgotten first, so the whole of the zone comes back down as well as up.
    /// **Everything, and every step of it said out loud.** It was the sending
    /// half alone, so the one thing a reader watching it wanted to see, the
    /// whole of the work happening again, was the one thing it did not do : two
    /// phases went by, `Synchronizing with iCloud` and then nothing.
    func forceSynchronization() async {
        guard let cloud else { return }

        await exclusively("A forced synchronization") { await self.resynchronizing(cloud) }
    }

    private func resynchronizing(_ cloud: CloudSync) async {
        // The model is asked again too : a repair that left it silenced by
        // three failures from an hour ago would rebuild the page and leave it
        // with no headlines and no subjects, which is most of what a reader
        // asking for a repair is looking at.
        OnDeviceModel.reconsider()

        await beginWork([
            .synchronizing, .fetching, .indexing, .grouping, .writing, .filing, .tidying, .exchanging,
        ])
        moveWork(to: .synchronizing)
        await cloud.resetFromScratch()
        await cloud.enqueueEverything()
        await cloud.enqueueReadStates()
        await cloud.enqueueCatchUp()
        await cloud.synchronize()

        // Opened again from nothing, since the ledger of what has been read has
        // just been thrown away.
        archive = nil

        // **And what the model wrote goes with it.** Forgetting the change
        // tokens repairs what came from iCloud and nothing else : every story
        // still had its headline, its summary and its subjects, so the two jobs
        // that write them found nothing to do and returned in milliseconds. A
        // repair that leaves the whole of the enrichment untouched is not a
        // repair from nothing, and it is the half a reader watching it most
        // wants to see happen.
        //
        // A headline the reader settled themselves is left alone, subject
        // included : that is theirs, and it is not what has gone wrong.
        await digestService.discardWhatTheModelWrote()

        // And then the whole of the ordinary pass, which is what makes this a
        // repair rather than an exchange : every feed asked again, the stories
        // built again, the headlines and the subjects written again, the index
        // and the purge, and iCloud once more at the end with everything that
        // has just arrived.
        await fullPass()
    }

    /// Sends and fetches now, and folds in whatever arrived.
    func synchronize() async {
        guard let cloud else { return }

        await cloud.enqueueReadStates()
        await cloud.synchronize()
        await load()
    }

    /// Opens the shared archive, if this device has one to open.
    ///
    /// Absent until the container is there, which is a question of an
    /// entitlement and of an iCloud account rather than of anything the
    /// application decides. Everything that uses it does nothing when it is
    /// absent, so a reader with no iCloud loses only the sharing.
    private func openArchive() async {
        guard archive == nil else { return }
        let device = preferences.device
        let root = await Task.detached(priority: .utility) { StreamArchive.ubiquityRoot() }.value
        guard let root else { return }

        archive = StreamArchive(database, root: root, device: device)
        Log.sync.notice("The shared archive is open")
    }

    /// Writes this device's days out, and takes in what the others wrote.
    ///
    /// Both directions in one place, since neither is worth waking up for on
    /// its own : it runs after a refresh and with the background work.
    func exchangeArchives() async {
        await openArchive()
        guard let archive else { return }

        do {
            let read = try await ReadStateStore(database).fingerprints()
            _ = try await archive.ingest(read: read)
            try await archive.write()
        } catch {
            Log.sync.error("The shared archive could not be exchanged : \(error, privacy: .public)")
        }
    }

    /// Frees what the stream is holding, which is what a full iCloud calls for.
    ///
    /// Explicitly bounded, since nothing is thrown away on its own any more :
    /// asking for space back is the one time a reader means it.
    func purge() async {
        do {
            let summary = try await retention.purge(.bounded)
            Log.store.notice("Purged \(summary.removed) articles on request")
            await load()
        } catch {
            Log.store.error("The purge failed : \(error, privacy: .public)")
        }
    }

    // MARK: - Starting over

    /// Deletes everything Flong holds, on this device and in the reader's iCloud.
    ///
    /// **The whole of it, or the reset would undo itself.** Six places hold
    /// something : the database, the keychain, the key-value store, Spotlight,
    /// the record zone and the archive in iCloud Drive. Leaving any of the last
    /// three would have the first three fill back up at the next exchange,
    /// which is not a reset but a pause.
    ///
    /// The order is what makes it safe. Nothing that writes may be running when
    /// the tables go, so the enrichment is stopped and the window stops
    /// following the store ; iCloud is told first, while the tokens that
    /// address the zone are still in the database that is about to be erased ;
    /// and the reader's own choices go last, since the window reads its name
    /// and its face back from them.
    ///
    /// **What it cannot promise.** Another device that still holds the
    /// subscriptions will find the zone gone, recreate it and put its own copy
    /// back, exactly as it would after any loss. There is no server to tell it
    /// otherwise, which is the design and not an oversight, and the panel says
    /// so before the reader confirms.
    func deleteEverything() async {
        let ran = await exclusively("Deleting everything", waiting: true) {
            await self.deletingEverything()
        }
        if !ran { failure = .notDeleted }
    }

    private func deletingEverything() async {
        // Nothing may be writing while the tables go. The enrichment is the one
        // long task that runs without the gate, and the window's own watcher
        // would only watch its tables be dropped.
        enriching?.cancel()
        await enriching?.value
        search?.cancel()
        watching?.cancel()
        await watching?.value
        watching = nil

        // iCloud first, while what addresses it is still here.
        await cloud?.eraseEverything()
        await eraseArchives()

        var failed = false
        do {
            try await database.eraseEverything()
        } catch {
            failed = true
            Log.store.error("The store could not be erased : \(error, privacy: .public)")
        }

        do {
            try credentials.removeEverything()
            try sessions.removeEverything()
        } catch {
            failed = true
            Log.store.error("The keychain could not be emptied : \(error, privacy: .public)")
        }

        // The store it is written from is empty now, so this deletes the lot
        // and tells Spotlight that nothing is what it should be holding.
        do {
            try await spotlight.rebuild()
        } catch {
            Log.index.error("Spotlight could not be emptied : \(error, privacy: .public)")
        }

        await announcer.withdrawEverything()
        ImageStore.shared.forgetEverything()

        // The reader's own choices, last and in this order : each of these
        // writes what it is set to back to the store, so they are emptied
        // before the keys are removed rather than after.
        firstName = ""
        lastName = ""
        setPicture(nil)
        setPlace(nil)
        articleBody = .feed
        theme = .standard
        wantsNewStoryNotices = false
        preferences.forgetEverything()

        forgetWhatIsShown()

        await load()
        await loadSubscribedSites()

        // And the window goes back to work : an application that had to be
        // relaunched after a reset would be saying the reset broke it.
        keepUp()
        await cloud?.start()

        if failed {
            failure = .notDeleted
        } else {
            Log.store.notice("Everything was deleted, on this device and in iCloud")
        }
    }

    /// Deletes the shared archive from iCloud Drive.
    ///
    /// Opened first where it never was : a reader who has not synchronized on
    /// this device since launching it still has days of the stream sitting in
    /// their iCloud from another one.
    private func eraseArchives() async {
        await openArchive()
        guard let archive else { return }

        do {
            try await Task.detached(priority: .utility) { try archive.erase() }.value
        } catch {
            Log.sync.error("The shared archive could not be deleted : \(error, privacy: .public)")
        }

        // Opened again when it is next needed, under the name this device is
        // about to give itself.
        self.archive = nil
    }

    /// Puts the window back where a first launch finds it.
    ///
    /// What is read from the store is reloaded rather than cleared, since the
    /// store is empty and reading it back is what proves it. What is not, the
    /// selection, the query and the article being read, has nothing to be read
    /// from and is put down here.
    private func forgetWhatIsShown() {
        selection = .all
        selectedArticle = nil
        article = nil
        openStory = nil
        storyArticles = [:]
        collectionArticles = []
        authors = []
        openedAuthor = nil
        authorArticles = []
        digestTopic = .frontPage
        indexedStories = nil
        searchText = ""
        report = nil
        failure = nil
    }

    /// Writes the chosen articles to Spotlight when the two have drifted apart.
    ///
    /// Spotlight keeps the record of what it holds, so an index it has lost is
    /// an index Flong writes again, without being told.
    ///
    /// A rebuild empties the whole index, the stories with it, so the page is
    /// handed straight back. Read afresh rather than taken from the window :
    /// the reader may have narrowed the digest to one subject, and the system
    /// index is about neither this window nor that subject.
    func synchronizeSpotlight() async {
        do {
            guard try await spotlight.rebuildIfNeeded() else { return }

            let page = try await digestService.digest(.frontPage)
            indexedStories = nil
            await handToSpotlight(page.all)
        } catch {
            Log.index.error("What the reader chose could not reach Spotlight : \(error, privacy: .public)")
        }
    }

    /// Tells Spotlight and the other devices that the reader marked something.
    ///
    /// An article the reader has just unmarked entirely is the interesting
    /// case : it has nothing left to send, and that is exactly when the other
    /// devices most need to hear from it. So the record is deleted rather than
    /// left standing, and the deletion is what carries the `no`.
    private func apply(marks ids: [UUID]) async {
        guard !ids.isEmpty else { return }

        do {
            let chosen = try await articles.chosen(ids)
            try await spotlight.index(chosen)

            let stillChosen = Set(chosen.map(\.id))
            try await spotlight.remove(ids.filter { !stillChosen.contains($0) })
        } catch {
            Log.index.error("Spotlight could not be told about a mark : \(error, privacy: .public)")
        }

        await enqueueMarks(for: ids)
    }

    private func enqueueMarks(for ids: [UUID]) async {
        guard let identities = try? await marks.identities(of: ids), !identities.isEmpty else { return }
        let standing = Set((try? await marks.marks(of: ids))?.filter { !$0.isEmpty }.map(\.guid) ?? [])

        var saved: [String] = []
        var deleted: [String] = []
        for identity in identities {
            let name = SyncRecords.name(forMarkWithGUID: identity.guid, feedURL: identity.feedURL)
            if standing.contains(identity.guid) { saved.append(name) } else { deleted.append(name) }
        }

        // The other devices hear about it on the next exchange, which the
        // engine schedules for itself.
        await cloud?.enqueue(recordNames: saved)
        await cloud?.enqueue(deletions: deleted)
    }

    func loadSidebar() async {
        do {
            let feeds = try await subscriptions.feeds()
            let counts = try await articles.counts()

            var items: [SidebarItem] = [
                SidebarItem(kind: .digest, title: nil, articleCount: 0),
                SidebarItem(kind: .unread, title: nil, articleCount: 0),
                SidebarItem(kind: .today, title: nil, articleCount: 0),
                SidebarItem(kind: .starred, title: nil, articleCount: 0),
                SidebarItem(kind: .all, title: nil, articleCount: 0),
            ]

            // Every source sits under the publisher serving it, so there is no
            // loose row and no reader wondering where one went : a feed's group
            // is its own address, and it is right the moment the feed lands.
            let groups = SubscriptionStore.groups(of: feeds, named: try await subscriptions.names())

            for group in groups {
                let children = group.feeds.map { item(for: $0, counts: counts) }
                items.append(
                    SidebarItem(
                        kind: .group(group.domain),
                        title: group.title,
                        articleCount: children.reduce(0) { $0 + $1.articleCount },
                        children: children
                    )
                )
            }

            sidebar = items
            // What every list in the window shows about where an article came
            // from, worked out once here rather than read off each row : the
            // name and the mark belong to the publisher, and five hundred rows
            // of one paper are one name and one favicon.
            publishers = Dictionary(
                groups.map { ($0.domain, $0.identity) },
                uniquingKeysWith: { first, _ in first }
            )
            feedCount = feeds.count
        } catch {
            Log.store.error("The sidebar could not be built : \(error, privacy: .public)")
        }
    }

    private func item(for feed: Feed, counts: [UUID: Int]) -> SidebarItem {
        SidebarItem(
            kind: .feed(feed.id),
            title: feed.title,
            articleCount: counts[feed.id] ?? 0,
            isFavourite: feed.isFavourite
        )
    }

    /// What the publisher an article came from is called and wears.
    ///
    /// `nil` only while the subscriptions are still being read, or for an
    /// article whose feed has gone : a page shows the address itself then,
    /// which is a name and not a hole.
    func publisher(of domain: String?) -> SourceIdentity? {
        guard let domain else { return nil }
        return publishers[domain]
    }

    /// The name of a feed or a group, for a screen that only has its identity.
    func title(of kind: SidebarItem.Kind) -> String? {
        sidebar.flatMap { [$0] + $0.children }.first { $0.kind == kind }?.title
    }

    func loadArticles() async {
        do {
            summaries = try await articles.summaries(filter, matching: query)
            hourlyCounts = try await articles.hourlyCounts(filter, matching: query)
            if let selectedArticle, !summaries.contains(where: { $0.id == selectedArticle }) {
                self.selectedArticle = nil
            }
        } catch {
            Log.store.error("The articles could not be read : \(error, privacy: .public)")
        }
    }

    // MARK: - Collections

    func loadCollections() async {
        do {
            collections = try await collectionStore.all()
            sharedCollectionNames = try await sharedCollections.ownedNames()
        } catch {
            Log.store.error("The collections could not be read : \(error, privacy: .public)")
        }
    }

    /// Which of the reader's own collections they have shared.
    ///
    /// Local to this device and read from the store rather than from CloudKit :
    /// the page says it against a square, and a square should not wait on the
    /// network to know what to draw.
    private(set) var sharedCollectionNames: Set<String> = []

    /// Reads back which collections are shared, without the rest of the page.
    ///
    /// An open collection asks for this on its own : the share is made inside
    /// the system's sheet, so this device only learns that one exists after the
    /// reader has come back from it.
    func loadSharedCollections() async {
        sharedCollectionNames = (try? await sharedCollections.ownedNames()) ?? []
    }

    /// What the share sheet is handed when the reader invites somebody.
    ///
    /// Nothing is created here : the zone and the share are made inside the
    /// sheet's own preparation handler, once the reader has actually picked
    /// somebody, so a sheet opened and dismissed leaves nothing behind.
    nonisolated func invitation(toCollectionNamed name: String) -> SharedCollectionItem {
        SharedCollectionItem(name: name, sharing: sharing)
    }

    /// Makes a collection and shows it, empty, where the reader will look.
    func makeCollection(named name: String) async {
        _ = try? await collectionStore.create(name)
        await loadCollections()
    }

    /// Makes a collection out of a description, which then fills itself.
    func makeDynamicCollection(named name: String, matching query: String) async {
        _ = try? await collectionStore.createDynamic(name, matching: query)
        await loadCollections()
    }

    func renameCollection(_ name: String, to renamed: String) async {
        guard let renamed = try? await collectionStore.rename(name, to: renamed) else { return }
        // The local index follows, so a collection that was shared is still
        // known to be. The share's own title does not : what the participants
        // were invited to is what they were invited to, and a name changing
        // under them would read as a different collection.
        try? await sharedCollections.rename(name, to: renamed)
        await loadCollections()
    }

    func deleteCollection(_ collection: ArticleCollection.Kind) async {
        switch collection {
        case .made(let name):
            // The share goes with it. A zone left behind would go on showing
            // the participants a collection its owner believes is gone, and
            // nothing would ever take it down.
            await sharing.stopSharing(collectionNamed: name)
            try? await collectionStore.delete(name)
        case .dynamic(let name): try? await collectionStore.deleteDynamic(name)
        // Not a thing that was made, so there is nothing there to unmake.
        case .builtIn: return
        }
        await loadCollections()
    }

    /// Every collection the reader has made, by name, in the order the page
    /// shows them.
    var collectionNames: [String] {
        collections.compactMap { if case .made(let name) = $0.kind { name } else { nil } }
    }

    /// Which collections the article being read is in.
    private(set) var articleCollections: [String] = []

    /// Whether whoever signed the article being read is one of the reader's.
    ///
    /// Held rather than asked of ``authors`` : that list is loaded by the
    /// authors page, and an article can be opened from anywhere.
    private(set) var articleAuthorIsFavourite = false

    func loadArticleCollections() async {
        guard let id = article?.id else {
            articleCollections = []
            articleAuthorIsFavourite = false
            return
        }
        articleCollections = (try? await collectionStore.collections(of: id)) ?? []

        guard let author = article?.author else {
            articleAuthorIsFavourite = false
            return
        }
        articleAuthorIsFavourite = (try? await authorStore.isFavourite(author)) ?? false
    }

    /// Singles out whoever signed the article being read, or stops.
    ///
    /// The same act as the star on their row in the authors list, reached from
    /// where a reader actually forms the opinion : having just read the piece.
    func toggleFavouriteAuthorOfOpenedArticle() async {
        guard let author = article?.author else { return }

        await setFavouriteAuthor(author, !articleAuthorIsFavourite)
        articleAuthorIsFavourite = !articleAuthorIsFavourite
    }

    /// Puts the article being read into a collection.
    ///
    /// There is nothing to promote or copy first : the article is the article,
    /// wherever it is shown, and filing it is one row saying so.
    func fileArticle(in name: String) async {
        guard let opened = article else { return }

        do {
            try await collectionStore.add([opened.id], to: name)
            await loadArticleCollections()
            await loadCollections()
            await apply(marks: [opened.id])
        } catch {
            Log.store.error("The article could not be filed : \(error, privacy: .public)")
        }
    }

    func unfileArticle(from name: String) async {
        guard let opened = article else { return }

        try? await collectionStore.remove([opened.id], from: name)
        await loadArticleCollections()
        await loadCollections()
        await apply(marks: [opened.id])
    }

    // MARK: - Authors

    /// Everybody who has signed something on this device.
    ///
    /// Asked of the articles rather than of a table of people : there is no row
    /// for a writer and there could not be one, since what a feed hands over is
    /// a byline. See ``AuthorStore``.
    func loadAuthors() async {
        do {
            authors = try await authorStore.all()
        } catch {
            Log.store.error("The authors could not be read : \(error, privacy: .public)")
        }
    }

    /// Singles a writer out, or stops.
    ///
    /// It stars nothing and it changes nothing about the articles : a favourite
    /// author is a judgement about who wrote a piece, exactly as a favourite
    /// source is one about who published it, and section 13 keeps the star a
    /// judgement about the article itself.
    ///
    /// **The `no` travels.** The favourite is one record named after the writer,
    /// so two devices singling out the same person write one record between
    /// them, and taking the favourite back deletes it rather than leaving a
    /// decision the reader undid to be handed back by iCloud.
    func setFavouriteAuthor(_ name: String, _ isFavourite: Bool) async {
        do {
            try await authorStore.setFavourite(name, isFavourite)

            let record = SyncRecords.name(forFavouriteAuthor: name)
            if isFavourite {
                await cloud?.enqueue(recordNames: [record])
            } else {
                await cloud?.enqueue(deletions: [record])
            }

            // The list the reader is looking at, and the square that counts
            // what the favourites hold, which has just changed under them.
            //
            // Only when there is a list to put right : this is reached from an
            // article's own menu too, and grouping every byline in the store to
            // update a page nobody has opened is a scan of the whole corpus for
            // nothing.
            if !authors.isEmpty { await loadAuthors() }
            if openedAuthor?.name == name { openedAuthor?.isFavourite = isFavourite }
            await loadCollections()
            // Everything this writer signed, as a favourite source does for
            // everything a publisher served.
            await synchronizeSpotlight()
        } catch {
            failure = .notSaved
            Log.store.error("The author could not be marked : \(error, privacy: .public)")
        }
    }

    /// Opens one writer's page : who they are, and what they signed.
    func loadAuthor(_ name: String) async {
        do {
            openedAuthor = try await authorStore.author(named: name)
            authorArticles = try await articles.summaries(.author(name))
        } catch {
            Log.store.error("An author could not be read : \(error, privacy: .public)")
        }
    }

    func loadCollection(_ kind: ArticleCollection.Kind) async {
        do {
            // A dynamic one is a description, so it is answered by the same
            // query path any other search goes through. The other two are
            // memberships, which the articles carry themselves.
            if case .dynamic(let name) = kind {
                let query = try await collectionStore.query(of: name) ?? ""
                collectionArticles = try await articles.summaries(.all, matching: QueryParser.parse(query))
            } else {
                collectionArticles = try await articles.summaries(in: kind)
            }
        } catch {
            Log.store.error("A collection could not be read : \(error, privacy: .public)")
        }
    }

    /// Opens an article, wherever it was tapped.
    func open(article id: UUID) async {
        selectedArticle = id
        await openSelectedArticle()
    }

    private func openSelectedArticle() async {
        guard let selectedArticle else {
            article = nil
            return
        }

        do {
            article = try await articles.article(id: selectedArticle)
            // Opening an article is what marks it read. Nothing waits on
            // anything : the row changes now.
            try await articles.setRead([selectedArticle], to: true)
            await refreshCounts(markingRead: selectedArticle)
        } catch {
            Log.store.error("The article could not be opened : \(error, privacy: .public)")
        }
    }

    /// Goes to the page for an article whose feed gave a summary.
    ///
    /// Only for the article being read, and only once for its life : see
    /// ``FullText``. The reader has the feed's version on screen the whole
    /// time, so a page that never answers costs them nothing but the wait they
    /// were not made to sit through.
    private func fetchFullText(of id: UUID) async {
        guard let opened = article, opened.id == id, !opened.hasFullText,
            FullText.isWorthFetching(url: opened.url, feedHTML: opened.bodyHTML, extractedHTML: nil)
        else { return }

        isFetchingFullText = true
        defer { isFetchingFullText = false }

        guard await FullText(database).extract(id) != nil else { return }

        // The reader may have moved on while the page was being fetched, and
        // an article arriving under a different one is worse than none.
        guard selectedArticle == id else { return }
        article = try? await articles.article(id: id)
    }

    /// Fetches the page for an article the reader asked for by hand.
    func fetchFullText() async {
        guard let id = selectedArticle else { return }
        await fetchFullText(of: id)
    }

    /// Updates what is on screen after a read state changed, without refetching
    /// the whole list.
    private func refreshCounts(markingRead id: UUID?) async {
        guard let id else { return }

        if let index = summaries.firstIndex(where: { $0.id == id }) { summaries[index].isRead = true }
        for (story, articles) in storyArticles {
            guard let index = articles.firstIndex(where: { $0.id == id }) else { continue }
            storyArticles[story]?[index].isRead = true
        }

        await loadSidebar()
    }

    // MARK: - Reading

    func toggleRead(_ summary: ArticleSummary) async {
        do {
            try await articles.setRead([summary.id], to: !summary.isRead)
            if let index = summaries.firstIndex(where: { $0.id == summary.id }) {
                summaries[index].isRead = !summary.isRead
            }
            await loadSidebar()
        } catch {
            Log.store.error("The read state could not be changed : \(error, privacy: .public)")
        }
    }

    /// Puts an article in the favourites, or takes it back out.
    func toggleStarred(_ summary: ArticleSummary) async {
        do {
            try await articles.setStarred([summary.id], to: !summary.isStarred)

            if let index = summaries.firstIndex(where: { $0.id == summary.id }) {
                summaries[index].isStarred = !summary.isStarred
            }
            if let index = collectionArticles.firstIndex(where: { $0.id == summary.id }) {
                collectionArticles[index].isStarred = !summary.isStarred
            }

            await apply(marks: [summary.id])
            await loadSidebar()
        } catch {
            Log.store.error("The starred state could not be changed : \(error, privacy: .public)")
        }
    }

    /// Stars or unstars the article being read.
    func toggleStarredCurrent() async {
        guard let article else { return }

        do {
            let isStarred = !article.isStarred
            try await articles.setStarred([article.id], to: isStarred)

            self.article?.isStarred = isStarred
            if let index = summaries.firstIndex(where: { $0.id == article.id }) {
                summaries[index].isStarred = isStarred
            }
            if let index = collectionArticles.firstIndex(where: { $0.id == article.id }) {
                collectionArticles[index].isStarred = isStarred
            }

            await apply(marks: [article.id])
            await loadSidebar()
        } catch {
            Log.store.error("The starred state could not be changed : \(error, privacy: .public)")
        }
    }

    /// Puts the article being read back in the unread pile, and closes it.
    ///
    /// Reading an article marks it read, so the only way this is ever asked for
    /// is deliberately, to come back to it later.
    func markCurrentUnread() async {
        guard let article else { return }

        do {
            try await articles.setRead([article.id], to: false)
            if let index = summaries.firstIndex(where: { $0.id == article.id }) {
                summaries[index].isRead = false
            }
            selectedArticle = nil
            await loadSidebar()
        } catch {
            Log.store.error("The read state could not be changed : \(error, privacy: .public)")
        }
    }

    func markAllRead() async {
        do {
            _ = try await articles.markRead(filter)
            await load()
        } catch {
            Log.store.error("The view could not be marked read : \(error, privacy: .public)")
        }
    }

    // MARK: - Refreshing

    /// Asks the publishers, groups what arrived, and shows it.
    ///
    /// **One entry point, and every automatic trigger goes through it.**
    /// Fetching and showing used to be wired to different things. The clock,
    /// the background refresh and the return to the foreground all fetched ;
    /// only a cold launch, the menu command and the nightly pass ever grouped
    /// what had arrived into stories. So a window left open all day watched its
    /// sidebar counts move and `The rest` grow while the front page itself sat
    /// unchanged, and a reader whose reader plainly worked had to ask it by
    /// hand for the one thing they opened it for.
    ///
    /// The three steps are deliberately of different weights :
    ///
    /// - **fetching** is bounded by the network and by section 8, which decides
    ///   per feed what may be asked at all ;
    /// - **grouping** is plain SQL over what has just arrived, cheap next to the
    ///   fetching, so it happens on every pass that brought anything ;
    /// - **the model's own work** is the expensive half, so it runs behind this
    ///   rather than inside it, under a deadline, and only where it is welcome.
    ///
    /// The page is read back whether or not this pass found anything : something
    /// may have arrived from another device, from an archive, or from a pass
    /// that ran while the window was away, and the reader is looking at the page
    /// now.
    func catchUp(_ reason: CatchUp, until deadline: Date? = nil) async {
        await exclusively("A catch-up", waiting: reason.isAskedFor) {
            await self.catchingUp(reason, until: deadline)
        }
    }

    private func catchingUp(_ reason: CatchUp, until deadline: Date?) async {
        await beginWork([.fetching, .grouping, .writing, .filing], atOnce: reason.isAskedFor)
        moveWork(to: .fetching)
        let fetching = progress(of: .fetching)
        let summary =
            reason.asksEveryFeed
            ? await refresher.refreshAll(until: deadline, onProgress: fetching)
            : await refresher.refreshDue(sparingly: reason.sparingly, until: deadline, onProgress: fetching)

        if summary.newArticles > 0 {
            Log.fetch.info("\(summary.newArticles) new articles from \(summary.refreshed) feeds")
        }

        // Always, and not only when this pass brought something itself. What is
        // waiting to be grouped may have come from iCloud, from a shared
        // archive, or from a pass that ran while the window was away, and
        // grouping is a single query when there is nothing to group.
        moveWork(to: .grouping)
        await digestService.buildStories()
        if reason.readsBackAtOnce { await load() }

        // An article from a favourite source or a favourite writer is chosen
        // the moment it lands, without the reader touching it, so a pass that
        // brought something is where the system index hears about it. Nothing
        // arrived means nothing to tell it, and the check costs a pass over the
        // identifiers rather than over the texts.
        if summary.newArticles > 0 { await synchronizeSpotlight() }

        guard reason.mayRunTheModel else {
            endWork()
            return
        }
        enrich(until: deadline)
    }

    /// What a pull on the front page asks for.
    ///
    /// Every feed, because they asked, and the grouping with it : what a reader
    /// means by pulling a page down is `show me what there is now`, and a page
    /// that fetched without grouping would answer with a longer tail and the
    /// same stories.
    ///
    /// It ends when the fetching and the grouping end, which is what the
    /// gesture holds its control out for. The model's work carries on behind
    /// it : a headline written and a subject filed for every story that has
    /// just arrived is one call to the model apiece and seconds each, and a
    /// gesture that waited for those would be a spinner held out for minutes.
    func pullToRefresh() async {
        await catchUp(.pull)
    }

    /// Refreshes every feed, which is what an import ends with.
    ///
    /// **A refresh, and not the spring clean it had become.** It used to purge,
    /// compact, enqueue read states, enqueue a catch-up and exchange the
    /// archives as well : the whole of the nightly pass, in the foreground, on
    /// a command a reader willingly repeats. All of that belongs to
    /// ``backgroundProcessing()``, which runs at rest on the mains and still
    /// does every bit of it.
    ///
    /// Every feed and not only those that are due, because they asked ; the
    /// token bucket per host is what keeps that polite to the publishers.
    ///
    /// **It ends when the fetching and the grouping end.** It used to wait for
    /// `rebuild`, which runs the model over the whole backlog with no deadline :
    /// a headline written and a subject filed for every story that has just
    /// arrived, one call to the model apiece, seconds each. On a device with
    /// Apple Intelligence and a page of new stories that is minutes of waiting
    /// for a command that had, as far as the reader could tell, already done
    /// its work. The model's work carries on behind it : those are resumable
    /// jobs, the window follows the store, and each headline appears as it is
    /// written.
    func refreshAll() async {
        await catchUp(.reader)
    }

    /// Writes the headlines and files the subjects, behind whatever asked.
    ///
    /// One at a time : a second command while the first is still being written
    /// would have two runs of the model competing for it, and the jobs pick up
    /// where they were left anyway.
    ///
    /// **The two halves share the time rather than the first taking all of
    /// it.** Writing a headline and filing a subject are one model call each,
    /// and the briefs ran first with no deadline at all : a night that brought
    /// sixty stories spent a hundred and eighty calls on headlines before the
    /// first subject was ever asked for, and the reader woke to a page of
    /// written headlines under no subjects at all. Half the time each, and the
    /// subjects get their half whatever the headlines did with theirs.
    private func enrich(until deadline: Date? = nil) {
        guard enriching?.isCancelled ?? true else { return }

        enriching = Task { [weak self] in
            guard let self else { return }
            await digestService.enrich(
                until: deadline,
                onWriting: progress(of: .writing),
                onFiling: progress(of: .filing),
                onPhase: { [weak self] phase in
                    Task { @MainActor [weak self] in self?.moveWork(to: phase) }
                }
            )
            await loadDigest()
            await announceNewStories()
            endWork()
            enriching = nil
        }
    }

    // MARK: - Subscribing

    /// Follows a feed whose address is itself the secret.
    ///
    /// The address is spent once, here, to find out what the feed is called and
    /// where its site is. What the database keeps is a masked form : the origin
    /// the reader recognizes, and a digest in place of the part that must never
    /// be written down. The real address goes to the keychain, and every
    /// refresh asks for it back.
    func addPrivateFeed(at address: String) async {
        do {
            let url = try FeedURL.canonical(address)
            guard let masked = MaskedURL.mask(url) else {
                failure = .invalidAddress
                return
            }

            let found = try await finder.find(at: url.absoluteString)
            let subscription = try Subscription(
                url: masked,
                title: found.title ?? "",
                siteURL: found.siteURL,
                iconURL: found.iconURL
            )

            let result = try await subscriptions.subscribe(to: subscription)
            try credentials.setCredential(.secretURL(url), for: result.feed.id)

            await cloud?.enqueue(recordNames: [SyncRecords.name(forFeed: result.feed.url)])
            _ = await refresher.refresh(result.feed)
            selection = .feed(result.feed.id)
            await load()
        } catch let error as FeedFinderError {
            switch error {
            case .invalidAddress: failure = .invalidAddress
            case .unreachable: failure = .unreachableFeed
            case .noFeedFound: failure = .noFeedFound
            }
        } catch {
            // Never the address : an error message is one of the places section 9
            // says a secret must not appear.
            failure = .notSaved
        }
    }

    // MARK: - Sites the reader pays for

    /// The site an address belongs to, however the reader spelled it.
    static func site(of address: String) -> String? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        return URL(string: withScheme).flatMap(FeedURL.room(of:))
    }

    /// Whether the reader has signed in to the site an address belongs to.
    func hasSession(for url: URL?) -> Bool {
        guard let url else { return false }
        return FullText.session(for: url, in: sessions) != nil
    }

    func loadSubscribedSites() async {
        let hosts = (try? sessions.hosts()) ?? []
        subscribedSites = hosts.compactMap { try? sessions.session(for: $0) }
    }

    /// Keeps the session a site left after the reader signed in.
    ///
    /// Only that site's own cookies : a login page loads a dozen third parties,
    /// and what they left has nothing to do with the reader being a subscriber.
    func saveSession(for host: String, cookies: [HTTPCookie]) async {
        let kept = cookies.compactMap(SessionCookie.init).filter { cookie in
            let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
            return domain == host || domain.hasSuffix("." + host)
        }

        guard !kept.isEmpty else {
            failure = .notSignedIn
            return
        }

        // Kept under the site the cookies claim rather than the address the
        // reader happened to sign in at, so one sign-in covers every feed and
        // article of the site.
        let site = SiteSession.site(of: kept, signedInAt: host)
        let existing = try? sessions.session(for: site)
        let session = SiteSession(
            host: site,
            cookies: kept,
            signedInAt: Date(),
            // A fresh sign-in has not proved anything yet, and saying it worked
            // a moment ago would be saying something nobody has checked.
            lastWorkedAt: existing?.lastWorkedAt
        )

        try? sessions.setSession(session, for: site)
        // A session that used to sit under a subdomain is replaced by the one
        // that covers the site, rather than left behind to shadow it.
        if site != host { try? sessions.setSession(nil, for: host) }
        await loadSubscribedSites()
    }

    func signOut(of host: String) async {
        try? sessions.setSession(nil, for: host)
        await loadSubscribedSites()
    }

    /// Keeps what a feed needs to prove the reader is entitled to it.
    ///
    /// Which feeds are authenticated is read back rather than assumed : it is
    /// what says a source has a secret without holding one, and a window that
    /// did not read it back would go on saying no until something else reloaded.
    func setCredential(_ credential: FeedCredential?, for feedID: UUID) async {
        do {
            try credentials.setCredential(credential, for: feedID)
            await loadCredentials()
            await loadSidebar()
        } catch {
            failure = .notSaved
        }
    }

    /// Whether a feed has a credential, which is not the same as holding it.
    func hasCredential(_ feedID: UUID) -> Bool {
        authenticatedFeeds.contains(feedID)
    }

    func loadCredentials() async {
        authenticatedFeeds = (try? credentials.identifiers()) ?? []
    }

    func addFeed(at address: String) async {
        do {
            let found = try await finder.find(at: address)
            let subscription = try Subscription(
                url: found.url,
                title: found.title ?? "",
                siteURL: found.siteURL,
                iconURL: found.iconURL
            )
            let result = try await subscriptions.subscribe(to: subscription)
            await cloud?.enqueue(recordNames: [SyncRecords.name(forFeed: result.feed.url)])

            _ = await refresher.refresh(result.feed)
            selection = .feed(result.feed.id)
            await load()
        } catch let error as FeedFinderError {
            switch error {
            case .invalidAddress: failure = .invalidAddress
            case .unreachable: failure = .unreachableFeed
            case .noFeedFound: failure = .noFeedFound
            }
        } catch {
            failure = .notSaved
        }
    }

    /// Singles a source out, or stops.
    ///
    /// It stars nothing. A favourite source is a judgement about the publisher,
    /// and the articles underneath keep whatever the reader said about them,
    /// which for almost all of them is nothing.
    func setFavourite(_ id: UUID, _ isFavourite: Bool) async {
        do {
            try await subscriptions.setFavourite(id, isFavourite)
            if let url = try await subscriptions.feed(id: id)?.url {
                await cloud?.enqueue(recordNames: [SyncRecords.name(forFeed: url)])
            }
            await loadSidebar()
            await loadCollections()
            // Everything this publisher has served has just become something
            // the reader chose, or stopped being it. The system index is where
            // one decision about a source turns into thousands of articles
            // found or no longer found.
            await synchronizeSpotlight()
        } catch {
            failure = .notSaved
            Log.store.error("The source could not be marked : \(error, privacy: .public)")
        }
    }

    /// Calls a publisher something else, or calls it by its address again.
    ///
    /// Nothing moves : the group is the address its sources share, and this
    /// writes only the name over it. Clearing the name is what puts the address
    /// back, which is why an empty one is not refused.
    func renameGroup(_ domain: String, to name: String?) async {
        do {
            let kept = try await subscriptions.rename(domain: domain, to: name)
            let record = SyncRecords.name(forSourceNamedDomain: domain)

            if kept == nil {
                await cloud?.enqueue(deletions: [record])
            } else {
                await cloud?.enqueue(recordNames: [record])
            }
            await loadSidebar()
        } catch {
            failure = .notSaved
            Log.store.error("The publisher could not be renamed : \(error, privacy: .public)")
        }
    }

    /// Stops following a source, and takes everything it brought with it.
    ///
    /// **It is the one thing in the sources panel that cannot be undone**, and
    /// the panel says so before it is asked for. What goes is everything that
    /// was only here because of this source : its articles whatever the reader
    /// did to them, the collections they were filed into losing those rows, the
    /// secret it was fetched with, what Spotlight held of it, and its records in
    /// the reader's iCloud, which is what carries the removal to their other
    /// devices.
    func unsubscribe(_ id: UUID) async {
        do {
            let gone = try await subscriptions.unsubscribe(id)
            await forget([gone])
        } catch {
            failure = .notRemoved
            Log.store.error("The source could not be removed : \(error, privacy: .public)")
        }
    }

    /// Stops following every source of one publisher.
    ///
    /// The heading is the only place a group is acted on, and this is the
    /// second thing it does. A group is the address its sources share rather
    /// than a row, so there is nothing of it left over : it goes because the
    /// last thing under it did.
    func unsubscribe(fromPublisher domain: String) async {
        do {
            let gone = try await subscriptions.unsubscribe(fromPublisher: domain)
            await forget(gone)
        } catch {
            failure = .notRemoved
            Log.store.error("The publisher could not be removed : \(error, privacy: .public)")
        }
    }

    /// Takes away what sources that have gone left outside the store, and puts
    /// the window back where it can stand.
    ///
    /// **The secret first.** A credential is keyed by a row that no longer
    /// exists, so a moment from now nothing in the application would be able to
    /// name it : it would sit in the keychain, unreachable, until the reader
    /// deleted everything. Section 20 of the specification is careful about
    /// exactly this.
    private func forget(_ gone: [Unsubscription]) async {
        for one in gone {
            do {
                try credentials.setCredential(nil, for: one.feed.id)
            } catch {
                // Never the address, and never the credential : an error
                // message is one of the places section 9 says a secret may not
                // appear.
                Log.store.error("A secret of a source that has gone stayed in the keychain")
            }

            do {
                try await spotlight.remove(one.marked.map(\.id))
            } catch {
                Log.index.error("Spotlight kept articles of a removed source : \(error, privacy: .public)")
            }

            await cloud?.enqueueRemoval(
                ofFeed: one.feed.url,
                marks: one.marked.map { SyncRecords.name(forMarkWithGUID: $0.guid, feedURL: one.feed.url) },
                sourceName: one.forgotName ? SyncRecords.name(forSourceNamedDomain: one.feed.domain) : nil
            )
        }

        // What the window was pointed at may have been one of them. The whole
        // stream is where a reader lands then, which is where a first launch
        // puts them, rather than on a heading with nothing under it.
        let removed = Set(gone.map(\.feed.id))
        let domains = Set(gone.map(\.feed.domain))
        switch selection {
        case .feed(let selected) where removed.contains(selected): selection = .all
        case .group(let selected) where domains.contains(selected): selection = .all
        default: break
        }

        await load()

        // The marks were taken out of Spotlight one by one above, since they
        // are known by identifier. What a favourite source or a favourite
        // writer had chosen is not : it was never a mark, and it left with the
        // rows rather than through a decision anybody made. The index and the
        // store disagree now, which is exactly the question this asks.
        await synchronizeSpotlight()

        // An article of a source that has gone is not an article any more, and
        // a page still holding it would be a page reading from nothing.
        if let open = article, ((try? await articles.article(id: open.id)) ?? nil) == nil {
            selectedArticle = nil
            article = nil
        }
    }

    func importOPML(from url: URL) async {
        do {
            report = try await opml(contentsOf: url)
            await cloud?.enqueueEverything()
            await load()
            await refreshAll()
        } catch let error as OPMLError {
            failure = .notOPML
            Log.store.error("The file is not an OPML document : \(String(describing: error), privacy: .public)")
        } catch let error as CocoaError {
            failure = .unreadableFile
            Log.store.error("The file could not be read : \(error, privacy: .public)")
        } catch {
            failure = .notSaved
            Log.store.error("The import could not be saved : \(error, privacy: .public)")
        }
    }
}

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
    /// Whether the reader asked to be told about every article it publishes,
    /// when it is a source.
    var notifies = false
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

/// One pass of the machinery, named.
///
/// It carries nothing : what it is for is being different from every other
/// pass, so that the thing which began one is the only thing that can end it.
/// See ``AppModel/current``.
nonisolated struct Work: Hashable, Sendable {
    fileprivate let id: Int
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
    case addressAlreadyFollowed
    case noAddress

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
        case .addressAlreadyFollowed: "Another source is already followed at this address."
        case .noAddress: "Type the address this source is served at."
        }
    }
}

/// Where a source is served, as the editor of one states it.
///
/// **The address is the one field whose answer cannot be a plain string**,
/// because whether it is a secret is a fact about the address rather than a
/// setting beside it. A secret one is masked in the database and lives in the
/// keychain ; an open one is the row itself. Moving between the two is moving
/// the source, and it is the same move either way.
nonisolated enum SourceAddress: Hashable, Sendable {
    /// Served in the open, at this address. Empty leaves it where it is, and
    /// takes a source that was a secret back into the open at the address the
    /// keychain holds.
    case open(String)
    /// Served at an address that is itself the secret. Empty keeps the secret
    /// already in the keychain, which is what a reader who changed something
    /// else on the screen sends.
    case secret(String)
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
    /// The second engine, on the shared database : see ``SharedSync``.
    private var sharedCloud: SharedSync?
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
    private let sharedEntries: SharedEntryStore

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

    /// What is in the shared collection the reader has opened.
    ///
    /// Separate from ``collectionArticles`` because it is a different thing :
    /// an excerpt somebody else sent, from a feed this reader does not follow,
    /// with no body to open and no read state of theirs. Putting the two in one
    /// list would mean a row that has to keep asking which it is.
    private(set) var sharedArticles: [SharedEntry] = []

    /// Who filed each of them, by the article's identity, where there is a name.
    ///
    /// Empty for the reader's own filings, deliberately : a collection several
    /// people fill has to say who put a thing in it, and saying so against the
    /// reader's own is telling them what they already know.
    private(set) var filedBy: [String: String] = [:]

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

    /// Which pass that is.
    ///
    /// **The ring used to be ended by whoever happened to call ``endWork()``**,
    /// and a pass is not always ended by the thing that began it : the steps
    /// inside a bigger one declare passes of their own, the enrichment ends the
    /// catch-up that started it from a task of its own, and the setup ended one
    /// from outside the call that opened it. Any of those ending somebody
    /// else's pass leaves that pass with nothing left to close it, and the ring
    /// turns until the application is restarted, which is what a reader sees as
    /// it being stuck.
    ///
    /// A pass is named now, and only its own name closes it. An inner step is
    /// handed nothing, so it cannot end the pass it is a part of ; a hand-off
    /// carries the name with it ; and an end that arrives late, for a pass that
    /// is already over, does nothing to the one running in its place.
    private var current: Work?
    /// How many passes there have been, which is where a name comes from.
    private var passes = 0

    /// What the page shows, which folds in the work iCloud does on its own.
    ///
    /// `CKSyncEngine` decides for itself when to send and when to fetch, so an
    /// exchange nothing here asked for still moves ``syncStatus`` and is still
    /// worth saying : a reader watching their page change wants to know it is
    /// their iPad talking and not a publisher.
    ///
    /// **This is the other half of the ring, and it used to have no way back.**
    /// An exchange begins on `willSendChanges` and is over on `didSendChanges`,
    /// and the second of those is not guaranteed to arrive : an engine
    /// interrupted, a process suspended between the two, a batch that comes to
    /// nothing. Nothing here ever ended it, so a status left at `working` was a
    /// ring that turned until the application was restarted. It is bounded now,
    /// by ``exchangeStandsFor``.
    var currentWork: WorkPlan? {
        if let work { return work }
        if case .working = syncStatus { return WorkPlan([.synchronizing]) }
        return nil
    }

    /// How long an exchange may say nothing before it stops standing for work.
    ///
    /// Long enough for a real one : a zone of three thousand records is sent in
    /// batches and a slow network makes a minute of it. Short enough that a
    /// reader is not left watching a ring for an exchange that ended without
    /// saying so.
    ///
    /// It ends what the ring shows and never what iCloud is doing. The engine
    /// carries on exactly as it was ; what stops is the claim, on the reader's
    /// page, that something is happening.
    static let exchangeStandsFor = Duration.seconds(60)

    /// The bound this window actually uses, so a test does not have to wait a
    /// minute to watch a ring give up.
    private let exchangeStandsFor: Duration

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
    /// - Returns: the name of the pass this began, which is what ends it, or
    ///   `nil` where a pass was already running and this is one of its steps.
    ///   Passing that `nil` back to ``endWork(_:)`` is what keeps a step from
    ///   ending the pass it belongs to.
    @discardableResult
    func beginWork(_ stages: [WorkPhase], atOnce: Bool = false) async -> Work? {
        // A pass already under way has already declared what it is made of, and
        // the inner steps of one are not passes of their own : the repair
        // declares the whole of itself and the ordinary pass inside it adds
        // nothing.
        guard plan == nil else { return nil }

        // Nothing is guessed for the feeds : `FeedRefresh` says how many it is
        // about to ask for before it asks for any of them, which lands well
        // inside the quarter second before the line appears at all.
        let onThePage = (try? await DigestStore(database).storyCount()) ?? 0

        // Asked again, since the questions above are awaited and a pass may
        // have begun while they were being answered.
        guard plan == nil else { return nil }

        passes += 1
        let pass = Work(id: passes)
        current = pass
        show(WorkPlan(stages, costing: await costsOfTheModelsWork(stages, floor: onThePage)), atOnce: atOnce)
        return pass
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

    /// Says a pass is over, once it has been on screen long enough to read.
    ///
    /// Only the pass named by ``beginWork(_:atOnce:)`` is ended. Anything else,
    /// `nil` included, is a step of a bigger pass or an end arriving after its
    /// own pass is over, and neither may close the one that is running.
    func endWork(_ pass: Work?) {
        guard let pass, pass == current else { return }
        current = nil
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

    /// When iCloud last said it had finished, kept so that an exchange which
    /// stops saying anything can fall back on something true rather than on
    /// nothing.
    private var lastSynchronized: Date?
    private var settlingExchange: Task<Void, Never>?

    /// Takes what the engine says, and refuses to let `working` stand for ever.
    ///
    /// Every other status is an end : idle, waiting, refused, unavailable. Only
    /// `working` is a beginning, and only `working` needs somebody to notice
    /// that its end never came.
    func report(_ status: SyncStatus) {
        syncStatus = status
        settlingExchange?.cancel()
        settlingExchange = nil

        if case .idle(let moment) = status, let moment { lastSynchronized = moment }
        guard case .working = status else { return }

        settlingExchange = Task { [weak self] in
            try? await Task.sleep(for: self?.exchangeStandsFor ?? AppModel.exchangeStandsFor)
            guard !Task.isCancelled, let self, case .working = syncStatus else { return }

            // Not a failure, and not said as one : the exchange stopped
            // reporting, which the reader can do nothing about and does not
            // need telling. What it stops being is a reason to show a ring.
            Log.sync.notice("An exchange said nothing for a minute : the ring stops standing for it")
            syncStatus = .idle(lastSynchronized: lastSynchronized)
            settlingExchange = nil
        }
    }

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

                // **The words first, the sentence after.** Reading a sentence
                // takes the model a second or so, and a search field that
                // showed nothing for a second would be a search field that
                // felt broken. The words answer immediately, which is what
                // every search field has always done, and the reading narrows
                // them when it arrives.
                reading = nil
                readingOf = nil
                await loadArticles()

                guard !Task.isCancelled else { return }
                await understand(searchText)
            }
        }
    }

    private var search: Task<Void, Never>?

    /// What the model made of the sentence, when it made anything.
    private(set) var reading: QuestionReading?
    /// The sentence it was made of, so a reading is never used for another one.
    private var readingOf: String?

    /// What the sentence was understood to ask for, in the reader's own words.
    ///
    /// Empty where nothing was understood beyond the words themselves, which is
    /// most searches and every search on a device with no model.
    /// What the sentence was understood to ask for, in the reader's own words.
    ///
    /// The model's reading where there is one, and otherwise whatever the
    /// sentence named that this device can look up on its own : a publication
    /// the reader follows is recognized with no model at all.
    var understood: [String] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let reading, readingOf == trimmed { return reading.understood }

        return QuestionReader.plainly(trimmed, in: vocabulary)?.understood ?? []
    }

    /// Reads what was typed as the sentence it is.
    ///
    /// **Nothing is narrowed by a name the reader does not follow.** The model
    /// is handed the sources, the feeds and the bylines this device actually
    /// holds, and a publication it invents matches none of them and goes back
    /// into the words. See ``QuestionReader``.
    private func understand(_ sentence: String) async {
        let sentence = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty else { return }

        guard let read = await QuestionReader().read(sentence, in: vocabulary) else { return }
        // The reader has typed on while the model was thinking, and an answer
        // about a sentence that is no longer in the field is an answer to
        // nothing.
        guard !Task.isCancelled, searchText.trimmingCharacters(in: .whitespacesAndNewlines) == sentence else { return }

        reading = read
        readingOf = sentence
        await loadArticles()
    }

    /// What there is to name, so that a name in a sentence can be matched to it.
    private var vocabulary: QuestionReader.Vocabulary {
        QuestionReader.Vocabulary(
            sources: sourceGroups.compactMap { item in
                guard case .group(let host) = item.kind else { return nil }
                return QuestionReader.Vocabulary.Source(name: item.title ?? host, host: host)
            },
            feeds: sidebar.flatMap { [$0] + $0.children }
                .compactMap { if case .feed = $0.kind { $0.title } else { nil } },
            authors: authors.map(\.name)
        )
    }

    /// What the reader has looked for before, newest first.
    ///
    /// **Kept because a query is worth keeping.** A word typed into a box is
    /// not worth a list ; a sentence with a field, a state and a date in it is
    /// something the reader worked out, and a search screen that opened on
    /// nothing would make them work it out again. Written through
    /// ``Preferences``, so it is the same list on their other devices.
    private(set) var recentSearches: [String] = []

    /// Keeps what the reader just searched for.
    ///
    /// Newest first, and without repeats : a query run again moves to the top
    /// rather than appearing twice. Matched without regard to case or to the
    /// spaces around it, since `is:unread` and `IS:UNREAD ` are one search and
    /// the reader would rightly call two rows a bug.
    ///
    /// A query that says nothing is not one : an empty field, or a field
    /// holding only whitespace, is not a search that was made.
    func remember(_ query: String) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        var kept = recentSearches.filter { $0.compare(query, options: .caseInsensitive) != .orderedSame }
        kept.insert(query, at: 0)
        recentSearches = Array(kept.prefix(Preferences.recentSearchLimit))
        preferences.recentSearches = recentSearches
    }

    /// Drops one search from the list, because the reader said so.
    func forget(search query: String) {
        recentSearches.removeAll { $0 == query }
        preferences.recentSearches = recentSearches
    }

    /// Drops the lot, which is the one control a list of past searches owes
    /// the person whose searches they were.
    func forgetSearches() {
        guard !recentSearches.isEmpty else { return }
        recentSearches = []
        preferences.recentSearches = []
    }

    /// The query as it is understood, or `nil` when the field is empty.
    ///
    /// The model's reading of the sentence where there is one for this exact
    /// sentence, and the words themselves otherwise : the parser still answers
    /// for everybody, which is what section 15 means by the path without a
    /// model always being there.
    var query: QueryNode? {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let reading, readingOf == trimmed { return reading.query }
        if let plain = QuestionReader.plainly(trimmed, in: vocabulary) { return plain.query }

        let node = QueryParser.parse(trimmed)
        return node == .all ? nil : node
    }

    /// What is worth searching for, from what the feeds are full of.
    ///
    /// A queue rather than the three that are shown : a subject the reader
    /// searches for joins the searches above it and stops being offered, and
    /// the next one steps into the place it left.
    ///
    /// Read once, when the digest is, rather than worked out every time the
    /// page draws itself : naming the people and places in twenty headlines is
    /// a pass over twenty headlines, and a computed property would do it again
    /// at every keystroke.
    private(set) var searchSubjects: [String] = []

    /// What the field offers above the keyboard.
    ///
    /// **Subjects, not syntax.** A field that offered `is:unread` and `tag:`
    /// was teaching its own grammar to somebody who came to look something up.
    /// What is offered is what is happening : the subjects of the stories on
    /// the page, and, once the reader has started typing, whichever of them
    /// they are heading towards.
    ///
    /// What the reader has already searched for is left out of the empty-field
    /// offer : it is on the page two rows above, and a suggestion that repeats
    /// a row wastes its line.
    var searchSuggestions: [String] {
        SearchSubjects.offered(from: searchSubjects, excluding: recentSearches, matching: searchText)
    }

    init(
        database: AppDatabase,
        fetcher: FeedFetcher = FeedFetcher(),
        credentials: CredentialStoring = KeychainCredentials(),
        sessions: SessionStoring = KeychainSessions(),
        preferences: Preferences = Preferences(),
        announcer: Announcing = Notifier(),
        locator: Locating = DeviceLocator(),
        exchangeStandsFor: Duration = AppModel.exchangeStandsFor
    ) {
        self.exchangeStandsFor = exchangeStandsFor
        self.database = database
        self.credentials = credentials
        self.sessions = sessions
        self.preferences = preferences
        self.announcer = announcer
        self.locator = locator
        self.articleBody = preferences.articleBody
        self.theme = preferences.theme
        self.wantsNewStoryNotices = preferences.wantsNewStoryNotices
        self.wantsCollaborationNotices = preferences.wantsCollaborationNotices
        self.mutedSharedCollections = preferences.mutedSharedCollections
        self.firstName = preferences.firstName
        self.lastName = preferences.lastName
        self.picture = preferences.picture.flatMap(ProfilePicture.image)
        self.place = preferences.place
        self.recentSearches = preferences.recentSearches
        let subscriptions = SubscriptionStore(database)
        self.subscriptions = subscriptions
        let articles = ArticleStore(database)
        self.articles = articles
        self.collectionStore = CollectionStore(database)
        self.sharing = CollectionSharing(database: database)
        self.sharedCollections = SharedCollectionStore(database)
        self.sharedEntries = SharedEntryStore(database)
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
        recentSearches = preferences.recentSearches
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

            // What is worth searching for is what the page is full of, so it
            // is worked out where the page is read and nowhere else.
            searchSubjects = SearchSubjects.subjects(in: fetched.all.map(\.title))

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

    /// Asks the system whether this device may interrupt the reader, and
    /// records what it answered.
    ///
    /// Every switch that can lead to a notification goes through this, wherever
    /// it is drawn : the panel's own, and the one on each source. A refusal is
    /// final until the reader goes to the system settings, and asking again
    /// after one does not prompt, it returns the refusal.
    @discardableResult
    func authorizeNotifications() async -> Bool {
        let allowed = await announcer.authorize()
        notificationStatus = await announcer.status()
        return allowed
    }

    // MARK: - When one source publishes

    /// The sources the reader asked to be told about, in the order a list shows
    /// them.
    ///
    /// Read off the sidebar's own pass over the feeds rather than asked for
    /// separately : the sources are read there already, and this is a handful
    /// of them.
    private(set) var announcingSources: [Feed] = []

    /// Asks to be told about every article one source publishes, or stops
    /// asking.
    ///
    /// **The switch is the request, exactly as it is in the panel.** Turning it
    /// on is what asks the system, and a reader who has refused Flong at that
    /// level cannot be talked round from here : nothing is written and the
    /// screen says where the answer lives.
    ///
    /// The watermark is stamped now, so that what the source published before
    /// the reader asked about it is not announced as though it had just
    /// arrived.
    func setNotifications(_ wanted: Bool, forSource id: UUID) async {
        if wanted {
            guard await authorizeNotifications() else { return }
            preferences.articlesAnnouncedAt = Date()
        }

        do {
            try await subscriptions.setNotifies(id, wanted)
            // It is a decision about a publisher and it belongs on every device
            // the reader owns, like the favourite beside it.
            if let url = try await subscriptions.feed(id: id)?.url {
                await cloud?.enqueue(recordNames: [SyncRecords.name(forFeed: url)])
            }
            await loadSidebar()
        } catch {
            failure = .notSaved
            Log.store.error("The source could not be set to announce : \(error, privacy: .public)")
        }
    }

    /// The writers the reader asked to be told about, in the order a list shows
    /// them.
    private(set) var notifiedAuthors: [String] = []

    func loadNotifiedAuthors() async {
        notifiedAuthors = (try? await authorStore.notified()) ?? []
    }

    /// Asks to be told when a writer publishes, or stops asking.
    ///
    /// **The same switch as the one on a source, asked of a person.** A reader
    /// who follows somebody follows them wherever they write, which is the
    /// whole point of asking of the person rather than of the paper : the
    /// article turns up whichever feed carried it.
    ///
    /// It singles nobody out : the favourite beside it gathers a page, and this
    /// interrupts. A reader may well want one without the other.
    ///
    /// **The `no` travels**, like the favourite's : one record named after the
    /// writer, deleted when they stop asking, so a decision they undid is not
    /// handed back to them by iCloud.
    func setNotifications(_ wanted: Bool, forAuthor name: String) async {
        if wanted {
            guard await authorizeNotifications() else { return }
            preferences.articlesAnnouncedAt = Date()
        }

        do {
            try await authorStore.setNotifies(name, wanted)

            let record = SyncRecords.name(forNotifiedAuthor: name)
            if wanted {
                await cloud?.enqueue(recordNames: [record])
            } else {
                await cloud?.enqueue(deletions: [record])
            }

            // Only where there is a list to put right : this is reached from a
            // person's own page as well, and grouping every byline in the store
            // for a page nobody has opened is a scan of the corpus for nothing.
            if !authors.isEmpty { await loadAuthors() }
            if openedAuthor?.name == name { openedAuthor?.notifies = wanted }
            await loadNotifiedAuthors()
        } catch {
            failure = .notSaved
            Log.store.error("The writer could not be set to announce : \(error, privacy: .public)")
        }
    }

    /// Tells the reader what the sources and the writers they asked about have
    /// just published.
    ///
    /// **The watermark moves whether anything was said or not**, exactly as it
    /// does for the stories and for the collaborations : what it records is
    /// that the articles reached this device, not that a notification was
    /// posted.
    ///
    /// A reader who has asked about no source at all has no watermark either,
    /// so that asking about their first one starts from that moment rather than
    /// from whatever a silent pass had stamped.
    func announceNewArticles() async {
        let sources = (try? await subscriptions.announcing()) ?? []
        let writers = (try? await authorStore.notified()) ?? []
        guard !sources.isEmpty || !writers.isEmpty else { return }

        guard let since = preferences.articlesAnnouncedAt else {
            // A source or a writer asked about on another device, whose
            // decision has just arrived here. What they published before this
            // device heard about it is not news, so the clock starts now and
            // this pass says nothing.
            preferences.articlesAnnouncedAt = Date()
            return
        }

        let arrived = (try? await articles.arrived(since: since)) ?? []
        preferences.articlesAnnouncedAt = Date()

        guard !isReading, let announcement = Announcement.newArticles(arrived) else { return }
        await announcer.post(announcement)
    }

    // MARK: - When somebody adds to a shared collection

    private(set) var wantsCollaborationNotices = false
    /// The shared collections the reader has asked to hear nothing about.
    private(set) var mutedSharedCollections: Set<String> = []

    /// Whether this reader is in any shared collection at all.
    ///
    /// What the notifications panel asks before offering a switch about them :
    /// a question about something the reader has never seen is a question they
    /// cannot answer.
    var hasSharedCollections: Bool {
        !sharedCollectionNames.isEmpty || !invitedCollections.isEmpty
    }

    /// Says whether the reader wants to hear about collaborations, asking the
    /// system when they do.
    ///
    /// The same shape as the story switch, and for the same reasons : the
    /// switch is the request, a refusal at the system level cannot be talked
    /// round from here, and the watermark is stamped now so that what is
    /// already in their collections is not announced as though it had just
    /// arrived.
    func setWantsCollaborationNotices(_ wanted: Bool) async {
        guard wanted else {
            preferences.wantsCollaborationNotices = false
            wantsCollaborationNotices = false
            return
        }

        let allowed = await announcer.authorize()
        notificationStatus = await announcer.status()
        guard allowed else {
            wantsCollaborationNotices = false
            return
        }

        preferences.collaborationsAnnouncedAt = Date()
        preferences.wantsCollaborationNotices = true
        wantsCollaborationNotices = true
    }

    /// Turns one collection quiet, or lets it speak again.
    ///
    /// Per collection rather than per person : a reader who is in four shared
    /// collections is usually loud about one of them, and muting a person would
    /// mute them everywhere including where they are wanted.
    func setNotices(_ wanted: Bool, forSharedCollection zone: String) {
        if wanted {
            mutedSharedCollections.remove(zone)
        } else {
            mutedSharedCollections.insert(zone)
        }
        preferences.mutedSharedCollections = mutedSharedCollections
    }

    /// Tells the reader what other people have just put in their collections.
    ///
    /// **The watermark moves whether anything was said or not**, exactly as it
    /// does for the stories : what it records is that the filing reached this
    /// device, not that a notification was posted. A reader who had the page
    /// open watched it arrive.
    ///
    /// Nothing about the reader's own filings, and nothing about a collection
    /// they have asked to be quiet.
    func announceCollaborations() async {
        guard wantsCollaborationNotices, let since = preferences.collaborationsAnnouncedAt else { return }

        let mine = await sharedCloud?.myListKey()
        let arrived =
            (try? await sharedEntries.arrived(
                since: since, excluding: mine, muted: mutedSharedCollections
            )) ?? []
        preferences.collaborationsAnnouncedAt = Date()

        guard !isReading, !arrived.isEmpty else { return }

        // The collection each was filed into, and whoever filed it. Both come
        // from the zone rather than from the row, which holds an identifier
        // that means nothing to a reader.
        let titles = ((try? await sharedCollections.all()) ?? [])
            .reduce(into: [String: String]()) { found, shared in found[shared.zoneName] = shared.title }

        var names: [String: [String: String]] = [:]
        for zone in Set(arrived.map(\.zone)) where names[zone] == nil {
            let owner = (try? await sharedCollections.all())?.first { $0.zoneName == zone }
            names[zone] = await sharing.attribution(
                inZone: zone, ownedBy: (owner?.isOwned ?? false) ? nil : owner?.ownerName
            )
        }

        let filings = arrived.map { filed in
            (
                collection: titles[filed.zone] ?? String(localized: "Shared collection"),
                by: names[filed.zone]?[filed.entry.guid],
                title: filed.entry.title
            )
        }

        guard let announcement = Announcement.filings(filings) else { return }
        await announcer.post(announcement)
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

        // **Ended by a `defer`, and ended by name.** Run on its own this is the
        // whole of the work and owns the ring ; run inside a full pass it is
        // one step of one, is handed no name, and ends nothing. Either way it
        // cannot leave a ring behind, whichever way it returns.
        let pass = await beginWork([.fetching, .indexing])
        defer { endWork(pass) }

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

        // Nothing to end here : the work opened the pass and closes its own.
        await exclusively("Finishing the setup") { await self.doOutstandingWork() }
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
        let pass = await beginWork([
            .fetching, .indexing, .grouping, .writing, .filing, .tidying, .synchronizing, .exchanging,
        ])
        defer { endWork(pass) }

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
        await announceNewArticles()
        await announceNewStories()
        await announceCollaborations()

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
    }

    /// Starts synchronizing with the reader's own iCloud.
    ///
    /// No account is not an error : Flong is fully usable on one device without
    /// one, and the sidebar says nothing rather than complaining.
    func startSync() async {
        guard cloud == nil else { return }

        let cloud = CloudSync(database: database) { [weak self] status in
            Task { @MainActor [weak self] in self?.report(status) }
        }
        self.cloud = cloud
        await cloud.start()

        // The collections other people shared, which are in a different
        // database and therefore a different engine. Its failures are its own
        // and do not colour the status the sidebar shows : a reader with no
        // shared collections has nothing here that could go wrong.
        let sharedCloud = SharedSync(database: database)
        self.sharedCloud = sharedCloud
        await sharedCloud.start()

        // An invitation accepted before there was a window says so now.
        await ShareAcceptance.pending.onArrival { [weak self] _ in
            await self?.sharedCloud?.synchronize()
            await self?.loadCollections()
        }
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

        let pass = await beginWork([
            .synchronizing, .fetching, .indexing, .grouping, .writing, .filing, .tidying, .exchanging,
        ])
        defer { endWork(pass) }

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
        forgetSearches()
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
            // The panel that lists everything Flong may interrupt the reader
            // for reads them here : they have just been fetched, and a handful
            // of rows out of hundreds is not a second query.
            announcingSources = feeds.filter(\.notifiesNewArticles)
        } catch {
            Log.store.error("The sidebar could not be built : \(error, privacy: .public)")
        }
    }

    private func item(for feed: Feed, counts: [UUID: Int]) -> SidebarItem {
        SidebarItem(
            kind: .feed(feed.id),
            title: feed.title,
            articleCount: counts[feed.id] ?? 0,
            isFavourite: feed.isFavourite,
            notifies: feed.notifiesNewArticles
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
            // The ones somebody else shared are added here rather than inside
            // `CollectionStore` : they are not in the tags, the columns or the
            // saved queries that store answers from, they are in a table of
            // their own, and a store that reached into it would be answering a
            // question about somebody else's data.
            collections = try await collectionStore.all() + sharedCollections.invited(from: sharedEntries)
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
        SharedCollectionItem(name: name, sharing: sharing) { [database, sharing, credentials] in
            await sharing.push(collectionNamed: name, from: database, credentials: credentials)
        }
    }

    // MARK: - Filing into somebody else's collection

    /// The collections the reader was invited to, for the article's own menu.
    private(set) var invitedCollections: [SharedCollection] = []

    /// Which of them the open article is already in, by this reader's own hand.
    ///
    /// Their own list alone : an article somebody else filed is in the
    /// collection without being theirs, and a tick against it would offer to
    /// remove something they cannot remove.
    private(set) var articleSharedCollections: Set<String> = []

    func loadInvitedCollections() async {
        invitedCollections = (try? await sharedCollections.all().filter { !$0.isOwned }) ?? []
    }

    /// Puts the open article into a collection somebody shared, or takes it out.
    ///
    /// The excerpt only, and the addresses truncated of whatever this reader
    /// designated as theirs : it is their device doing the writing, so it is
    /// their keychain the truncation is against.
    /// What other people put into one of the reader's own shared collections.
    ///
    /// Nothing at all for a collection that is not shared, which is most of
    /// them, and nothing for the reader's own list either : they read their own
    /// filings from their own articles, and showing them twice would be showing
    /// them twice.
    private func contributions(to kind: ArticleCollection.Kind) async throws -> [SharedEntry] {
        guard case .made(let name) = kind,
            let shared = try await sharedCollections.owned(named: name),
            let mine = await sharedCloud?.myListKey()
        else { return [] }

        return try await sharedEntries.entries(inZone: shared.zoneName, excluding: mine)
    }

    /// Who filed what in one shared collection, by the article's identity.
    ///
    /// Two questions joined : the store says which identifier filed which
    /// article, and the share says what that identifier is called. The share is
    /// in the owner's private database when it is the reader's own collection
    /// and in their shared database when it is not, which is the only thing
    /// `isOwned` decides here.
    private func namesFiling(inZone zone: String, isOwned: Bool) async -> [String: String] {
        let owner =
            isOwned
            ? nil : (try? await sharedCollections.all())?.first { $0.zoneName == zone }?.ownerName
        guard isOwned || owner != nil else { return [:] }

        return await sharing.attribution(inZone: zone, ownedBy: owner)
    }

    /// The open article as it would cross to somebody else, worked out once.
    ///
    /// Built by the store rather than from what the page holds : an ``Article``
    /// is what a reader looks at and carries no feed identity, and the identity
    /// is exactly what a recipient needs in order to recognize their own copy.
    private var openSharedEntry: SharedEntry?

    func fileArticle(inShared zone: String) async {
        guard let entry = openSharedEntry,
            let shared = invitedCollections.first(where: { $0.zoneName == zone })
        else { return }

        await sharedCloud?.file(entry, inZone: zone, ownedBy: shared.ownerName)
        await loadArticleSharedCollections()
        await loadCollections()
    }

    func unfileArticle(fromShared zone: String) async {
        guard let entry = openSharedEntry,
            let shared = invitedCollections.first(where: { $0.zoneName == zone })
        else { return }

        await sharedCloud?.file(nil, removing: entry.guid, inZone: zone, ownedBy: shared.ownerName)
        await loadArticleSharedCollections()
        await loadCollections()
    }

    func loadArticleSharedCollections() async {
        guard let opened = article else {
            openSharedEntry = nil
            articleSharedCollections = []
            return
        }

        openSharedEntry = try? await SharedEntry.entry(
            in: database, articleID: opened.id, credentials: credentials
        )

        guard let guid = openSharedEntry?.guid, let sharedCloud else {
            articleSharedCollections = []
            return
        }

        var found: Set<String> = []
        for shared in invitedCollections {
            if await sharedCloud.filedGUIDs(inZone: shared.zoneName).contains(guid) {
                found.insert(shared.zoneName)
            }
        }
        articleSharedCollections = found
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
        // Somebody else's. Leaving a share is the system's own sheet to do,
        // and deleting the rows here would only have them arrive again on the
        // next fetch : the share is still there and this device is still in it.
        case .shared: return
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
            await loadArticleSharedCollections()
            return
        }
        articleCollections = (try? await collectionStore.collections(of: id)) ?? []

        // What somebody else shared, and which of them this article is already
        // in by this reader's own hand. Asked here so that the menu has its
        // answer before it is opened rather than after.
        await loadInvitedCollections()
        await loadArticleSharedCollections()

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
            await pushIfShared(name)
        } catch {
            Log.store.error("The article could not be filed : \(error, privacy: .public)")
        }
    }

    /// Sends a collection the reader shared, after it has changed.
    ///
    /// A collection nobody was invited to does nothing, which is most of them.
    /// The whole list goes each time, so a filing and an unfiling travel the
    /// same way and a push that failed is made good by the next one.
    private func pushIfShared(_ name: String) async {
        guard sharedCollectionNames.contains(name) else { return }
        await sharing.push(collectionNamed: name, from: database, credentials: credentials)
    }

    func unfileArticle(from name: String) async {
        guard let opened = article else { return }

        try? await collectionStore.remove([opened.id], from: name)
        await loadArticleCollections()
        await loadCollections()
        await apply(marks: [opened.id])
        await pushIfShared(name)
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
            // A shared one holds nothing of this device's : what is in it came
            // from feeds the reader does not follow, and there is no article
            // here to summarize.
            if case .shared(let zone, _) = kind {
                sharedArticles = try await sharedEntries.entries(inZone: zone)
                filedBy = await namesFiling(inZone: zone, isOwned: false)
                collectionArticles = []
                return
            }

            // A dynamic one is a description, so it is answered by the same
            // query path any other search goes through. The other two are
            // memberships, which the articles carry themselves.
            if case .dynamic(let name) = kind {
                let query = try await collectionStore.query(of: name) ?? ""
                collectionArticles = try await articles.summaries(.all, matching: QueryParser.parse(query))
            } else {
                collectionArticles = try await articles.summaries(in: kind)
            }

            // **A collection the reader shared shows what the others put in
            // it.** Their own filings are the articles above, read from their
            // own store ; what a participant filed is an excerpt of a piece
            // this device does not hold, and it arrives here. Without this the
            // owner is the one person in a collaboration who cannot see it.
            sharedArticles = try await contributions(to: kind)
            if case .made(let name) = kind, let shared = try await sharedCollections.owned(named: name) {
                filedBy = await namesFiling(inZone: shared.zoneName, isOwned: true)
            } else {
                filedBy = [:]
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
        let pass = await beginWork([.fetching, .grouping, .writing, .filing], atOnce: reason.isAskedFor)

        // **The pass outlives this function, and is ended all the same.** The
        // model's work is the last two stages of it and runs behind the
        // gesture, in a task of its own, so the pass is handed to it rather
        // than closed here. Everything else, including a way out added later,
        // closes it on the way out : a pass that leaves by a door nobody
        // thought about is a ring that turns for good.
        var handedOn = false
        defer { if !handedOn { endWork(pass) } }

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
        // **Every pass reads the page back, the pull included.** It was the one
        // exception : SwiftUI held its refresh control out until the gesture's
        // work returned, so replacing the content there had the scroll view
        // retract against content it had never laid out, and the pull was left
        // waiting on the watcher that follows the store, which reads back only
        // when something happens to be written. The control lets go on the beat
        // now, so there is nothing to lay out against and nothing to except.
        moveWork(to: .grouping)
        await digestService.buildStories()
        await load()

        // An article from a favourite source or a favourite writer is chosen
        // the moment it lands, without the reader touching it, so a pass that
        // brought something is where the system index hears about it. Nothing
        // arrived means nothing to tell it, and the check costs a pass over the
        // identifiers rather than over the texts.
        if summary.newArticles > 0 { await synchronizeSpotlight() }

        // Before the model and outside its guard : an article from a source the
        // reader asked about is news the moment it lands, and nothing has to be
        // written or grouped for it to be said. The twenty-five seconds of a
        // background refresh are where this matters most, since they are the
        // moments the reader is not looking.
        await announceNewArticles()

        guard reason.mayRunTheModel else { return }

        handedOn = true
        enrich(until: deadline, pass: pass)
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
    /// - Parameter pass: the pass whose last two stages this is, when it was
    ///   started by one. It is ended here, on every path : a run standing aside
    ///   for one already going used to end nothing at all, and the pass that
    ///   had handed itself over was left with nothing to close it.
    private func enrich(until deadline: Date? = nil, pass: Work? = nil) {
        guard enriching?.isCancelled ?? true else {
            endWork(pass)
            return
        }

        enriching = Task { [weak self] in
            guard let self else { return }
            defer {
                endWork(pass)
                enriching = nil
            }

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
            await announceCollaborations()
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
    // MARK: - The parameters on a feed's addresses

    /// Every parameter this feed's addresses carry, with what each one holds.
    ///
    /// **Both the feed's own address and its articles'**, because the two are
    /// frequently different. A paper may serve its feed at a plain address and
    /// put a per-subscriber token on every link inside it, which is the case
    /// this exists for : the feed's address is masked already when it is itself
    /// the secret, and the articles' are written down exactly as published.
    ///
    /// Masked before it leaves the store. The whole reason a reader is looking
    /// at this screen is that some of these are secrets.
    func addressParameters(of feedID: UUID, feedURL: URL) async -> [AddressParameter] {
        var seen: [String: String] = [:]
        var order: [String] = []

        func take(_ url: URL?) {
            guard let url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
            for item in components.queryItems ?? [] {
                guard let folded = SecretParameters.folded(item.name) else { continue }
                if seen[folded] == nil { order.append(item.name) }
                // The longest value seen, which is the one that shows best what
                // the parameter is for : a token is long and a page number is
                // not, and the reader is being asked to tell them apart.
                if (item.value?.count ?? 0) >= (seen[folded]?.count ?? -1) { seen[folded] = item.value ?? "" }
            }
        }

        // **A masked address is looked up rather than skipped.** What the
        // database holds for a secret feed is a digest and nothing a reader
        // could recognize, so it used to be left out ; but the address behind
        // it is in the keychain, it is the one carrying the subscription, and
        // it is the case this screen exists for. Refusing to look at it left
        // the screen saying that neither the feed nor its articles carried a
        // parameter, to a reader looking straight at one.
        //
        // Only the names are shown. The values are masked here as everywhere
        // else on this screen.
        if MaskedURL.isMasked(feedURL) {
            take(Self.secretAddress(of: keptCredential(of: feedID)).flatMap(URL.init(string:)))
        } else {
            take(feedURL)
        }

        let addresses = (try? await articles.addresses(ofFeed: feedID)) ?? []
        for address in addresses { take(address) }

        return order.compactMap { name in
            guard let folded = SecretParameters.folded(name), let value = seen[folded] else { return nil }
            return AddressParameter(name: name, masked: AddressParameter.mask(value))
        }
    }

    /// A feed's own address, for the screen that asks about its parameters.
    func address(ofFeed feedID: UUID) async -> URL? {
        try? await subscriptions.feed(id: feedID)?.url
    }

    /// The address behind a masked one, for the screen that edits it.
    ///
    /// **Section 9 says a secret address is masked in the interface, and a
    /// field that hides it is masked.** What it may not be is unreachable :
    /// the masked form gives nothing back, so a reader whose platform reissues
    /// their token, or who has to add a parameter to their own subscription,
    /// had nothing to edit and no way to see what they were editing. It is
    /// handed to the editor of that source and nowhere else, shown hidden, and
    /// revealed only by a deliberate tap by whoever is holding the device.
    func secretAddress(ofFeed feedID: UUID) async -> String? {
        Self.secretAddress(of: keptCredential(of: feedID))
    }

    /// Which of them the reader has already said are theirs.
    func secretParameters(of feedID: UUID) async -> Set<String> {
        Set(((try? credentials.secretParameters(for: feedID))?.names ?? []))
    }

    /// Records what the reader designated, and nothing they did not.
    func setSecretParameters(_ names: Set<String>, for feedID: UUID) async {
        do {
            try credentials.setSecretParameters(names.isEmpty ? nil : SecretParameters(names), for: feedID)
        } catch {
            Log.store.error("The address parameters could not be kept : \(error, privacy: .public)")
        }
    }

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

    /// One source, whole, for the screen that edits it.
    func source(_ id: UUID) async -> Feed? {
        try? await subscriptions.feed(id: id)
    }

    /// Edits a source : its name, its address, the site it belongs to, how
    /// often it is asked and whether it is one of the reader's own.
    ///
    /// **The address is the reason this exists.** A publisher that moves their
    /// feed used to cost the reader everything under it : the only repair was
    /// to unsubscribe and subscribe again, which takes the articles, the stars,
    /// the notes and the filings with it, on every device. Editing the address
    /// moves the row and leaves all of that where it is.
    ///
    /// **Whether the address is a secret is part of the address**, and moving
    /// between the two is moving the source. A source made secret has the
    /// masked form of section 9 written in its place and the real address put
    /// in the keychain, which also takes that address out of the reader's
    /// iCloud, where the plain one had been sitting in the subscription record.
    /// One made open again is written back in the open, which is what the
    /// reader asked for and what the screen says before they ask.
    ///
    /// The keychain is written before the row and cleared after it. A secret
    /// stored for a source that did not move is a secret nothing will use ; a
    /// secret cleared from one that did is a source at an address whose secret
    /// nothing knows, and that source is simply broken.
    func editSource(_ id: UUID, to edit: SourceEdit, address: SourceAddress) async {
        guard let feed = try? await subscriptions.feed(id: id) else {
            failure = .notSaved
            return
        }

        var edit = edit
        let wasSecret = MaskedURL.isMasked(feed.url)
        var clearsTheSecret = false

        // Asking to be told about a source is asking the system too, and a
        // refusal there cannot be talked round from here : the field goes back
        // where it was and everything else the reader typed is saved all the
        // same. The editor has already asked at the moment they touched the
        // switch, so this prompts nobody twice ; it is what makes the refusal
        // impossible to save around.
        if edit.notifiesNewArticles, !feed.notifiesNewArticles {
            if await authorizeNotifications() {
                // From now : what the source published before the reader asked
                // about it is not news.
                preferences.articlesAnnouncedAt = Date()
            } else {
                edit.notifiesNewArticles = false
            }
        }

        switch address {
        case .open(let typed):
            let typed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
            if wasSecret {
                // Back into the open : the address the keychain holds is the
                // one to write, unless the reader typed another.
                guard let real = typed.isEmpty ? Self.secretAddress(of: keptCredential(of: id)) : typed else {
                    failure = .noAddress
                    return
                }
                edit.address = real
                clearsTheSecret = true
            } else {
                edit.address = typed
            }

        case .secret(let typed):
            let typed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
            let real: URL?
            if typed.isEmpty {
                real = (Self.secretAddress(of: keptCredential(of: id))).flatMap { try? FeedURL.canonical($0) }
            } else {
                real = try? FeedURL.canonical(typed)
            }

            guard let real else {
                failure = typed.isEmpty ? .noAddress : .invalidAddress
                return
            }
            guard let masked = MaskedURL.mask(real) else {
                failure = .invalidAddress
                return
            }

            do {
                try credentials.setCredential(.secretURL(real), for: id)
            } catch {
                // Never the address : an error message is one of the places
                // section 9 says a secret must not appear.
                failure = .notSaved
                return
            }
            edit.address = masked.absoluteString
        }

        do {
            let change = try await subscriptions.edit(id, to: edit)
            if clearsTheSecret { try? credentials.setCredential(nil, for: id) }
            await loadCredentials()
            await carry(change)
        } catch is FeedURLError {
            failure = .invalidAddress
        } catch SubscriptionError.addressAlreadyFollowed {
            failure = .addressAlreadyFollowed
        } catch {
            failure = .notSaved
            Log.store.error("The source could not be edited : \(error, privacy: .public)")
        }
    }

    /// The credential of a source, or nothing, and never a reason why.
    private func keptCredential(of id: UUID) -> FeedCredential? {
        try? credentials.credential(for: id)
    }

    /// The address a credential is, when the credential is an address.
    private static func secretAddress(of credential: FeedCredential?) -> String? {
        guard case .secretURL(let url) = credential else { return nil }
        return url.absoluteString
    }

    /// Carries an edited source everywhere the store cannot reach.
    ///
    /// **A source that moved is a new set of names.** Everything the reader's
    /// iCloud holds about a source is named after the address it is served at,
    /// so the old records are deleted and the new ones queued : the
    /// subscription, one record for each article marked under it, and every
    /// block of the stream this device wrote at the old address. The record that
    /// goes up says where the source came from, which is what has the reader's
    /// other devices move the row they already hold rather than remove it.
    ///
    /// The read states need nothing. They are fingerprints of the address and
    /// the article together, so they are all wrong the moment a source moves ;
    /// the next compaction reads them off the feed as it now stands and unions
    /// the new ones in, and the old ones are a few bytes nobody will ever match.
    private func carry(_ change: SourceChange) async {
        let feed = SyncRecords.name(forFeed: change.feed.url)
        let forgotten = change.forgottenName.map(SyncRecords.name(forSourceNamedDomain:))

        if let previous = change.previousURL {
            await cloud?.enqueueRemoval(
                ofFeed: previous,
                marks: change.marked.map { SyncRecords.name(forMarkWithGUID: $0.guid, feedURL: previous) },
                sourceName: forgotten
            )
            await cloud?.enqueue(
                recordNames: [feed]
                    + change.marked.map { SyncRecords.name(forMarkWithGUID: $0.guid, feedURL: change.feed.url) }
            )
        } else {
            await cloud?.enqueue(recordNames: [feed])
            if let forgotten { await cloud?.enqueue(deletions: [forgotten]) }
        }

        await loadSidebar()

        // A source that changed site changed publisher, and the heading it used
        // to sit under may have gone with it. The whole stream is where a
        // reader lands then, as it is when a source is removed, rather than on
        // a heading with nothing under it.
        if case .group(let domain) = selection, !sourceGroups.contains(where: { $0.kind == .group(domain) }) {
            selection = .all
        }

        await loadCollections()
        // The name of a publisher is on every article of theirs the index
        // holds, and a favourite source is what put those articles in it at
        // all, so one line typed here is a decision about thousands of rows.
        await synchronizeSpotlight()

        // An address nothing has ever asked, edited by somebody who is watching
        // to see whether it works. Everything else can wait for the clock.
        if change.movedAddress {
            _ = await refresher.refresh(change.feed)
            await load()
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

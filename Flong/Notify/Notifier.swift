//
//  Notifier.swift
//  Flong
//
//  Created by François Rousselet on 30/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import OSLog
import UserNotifications

#if os(iOS)
    import UIKit
#else
    import AppKit
#endif

/// Local notifications, and nothing else.
///
/// **No push, and nothing arrives from anywhere.** There is no server, so there
/// is nobody to send a notification : every one of these is written by the
/// device that shows it, about something that device worked out for itself.
/// A second device may say the same thing at a different moment, or never, and
/// that is correct rather than a drift to fix : each of them reads its own page
/// and tells its own reader.
///
/// **Permission is asked at the moment the reader asks for the notifications**,
/// and never before. A prompt at first launch is a prompt about something the
/// reader has not seen yet, which is how an application is refused permanently
/// for a feature that would have been welcome later. Every switch here starts
/// off, and turning one on is what asks.
protocol Announcing {
    func status() async -> UNAuthorizationStatus
    func authorize() async -> Bool
    func post(_ announcement: Announcement) async
    /// Takes back everything already said, for a reset.
    func withdrawEverything() async
}

struct Notifier: Announcing {
    /// Whether the system will let this device say anything, as it stands now.
    func status() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Asks the reader, or takes the answer they already gave.
    ///
    /// A refusal is final until the reader goes to the system settings : asking
    /// again does not prompt, it returns the refusal, which is why the screen
    /// says where to go rather than offering the switch again.
    func authorize() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                // No `.badge` : nothing here ever sets one, and a permission
                // asked for and never spent is a row in the system settings
                // that does nothing whichever way the reader sets it.
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            Log.notify.error("Notifications could not be asked for : \(error, privacy: .public)")
            return false
        }
    }

    /// Says one thing, now.
    ///
    /// The picture is fetched here rather than earlier because this is the one
    /// place that knows a notice is really going to be posted : everything
    /// upstream stops for a reader who is looking at the page, and asking a
    /// publisher for a photograph nobody will be shown is a request for
    /// nothing. See ``NotificationPicture``.
    func post(_ announcement: Announcement) async {
        // Asked before anything is built. A revoked permission is not an error
        // to report to the reader, but it is a reason not to ask a publisher
        // for a photograph nobody will ever be shown.
        let allowed = await status()
        guard allowed == .authorized || allowed == .provisional else {
            Log.notify.info("A notice was not posted : this device may not interrupt the reader")
            return
        }

        // Asked for, and then never spent. The permission has carried `.sound`
        // since the beginning while nothing here ever set one, so every notice
        // Flong has ever posted arrived without a sound and without a tap on the
        // wrist : a reader with the phone in a pocket was told nothing they
        // could perceive, which is indistinguishable from not being told.
        let content = UNMutableNotificationContent()
        content.title = announcement.title
        if let subtitle = announcement.subtitle { content.subtitle = subtitle }
        content.body = announcement.body
        // The first of a burst sounds ; the rest arrive quietly, in the same
        // stack. Eight sounds in a row is not eight pieces of news, it is a
        // device somebody puts face down. See ``Announcement/isQuiet``.
        content.sound = announcement.isQuiet ? nil : .default
        if announcement.isQuiet { content.interruptionLevel = .passive }
        content.threadIdentifier = announcement.thread
        // Held until the request has been added, and thrown out after : the
        // system copies an attachment into its own store rather than taking
        // the file, so a notice an hour would otherwise be a photograph left
        // in `tmp` an hour.
        var written: URL?
        if let picture = announcement.picture,
            let made = await NotificationPicture.attachment(for: picture)
        {
            content.attachments = [made.attachment]
            written = made.file
        }
        defer {
            if let written { try? FileManager.default.removeItem(at: written) }
        }
        if announcement.opensTheDigest {
            content.userInfo = [Key.digest: true]
        } else if let story = announcement.story {
            content.userInfo = [Key.story: story.uuidString]
        } else if let article = announcement.article {
            content.userInfo = [Key.article: article.uuidString]
        }

        // No trigger : a trigger of nil is delivered immediately, and nothing
        // here can be written before the moment it is about. An edition could
        // be, by closing its period early, and then its notice would be lodged
        // for its hour and delivered on it with nothing of ours running ; what
        // that costs is the last minutes of every period, and the period is
        // what the reader asked for.
        let request = UNNotificationRequest(
            identifier: Self.identifier(of: announcement),
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            Log.notify.error("A notification could not be posted : \(error, privacy: .public)")
        }
    }

    /// What the system knows this notice by.
    ///
    /// **The article's own identifier where there is one, and a name where the
    /// thing has one.** A notice about one article is about one article for
    /// ever, so posting it twice should replace it rather than stack a second
    /// copy : the system keys on this, and a fresh `UUID` every time meant
    /// nothing could ever be corrected or de-duplicated. An edition's name is
    /// its boundary, so two passes that both notice one page has come out
    /// replace one banner rather than stacking two. Everything else keeps a new
    /// one, having nothing stable to be known by.
    static func identifier(of announcement: Announcement) -> String {
        announcement.name ?? announcement.article?.uuidString ?? UUID().uuidString
    }

    /// Takes back every notice this device has posted.
    ///
    /// A notice names a story, and after a reset there is no story to open :
    /// left in the notification centre it is a headline that leads nowhere.
    func withdrawEverything() async {
        let centre = UNUserNotificationCenter.current()
        centre.removeAllDeliveredNotifications()
        centre.removeAllPendingNotificationRequests()
    }

    /// Takes the reader to where the system keeps its own answer.
    static func openSystemSettings() {
        #if os(iOS)
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
        #else
            guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") else {
                return
            }
            NSWorkspace.shared.open(url)
        #endif
    }

    enum Key {
        static let story = "story"
        static let article = "article"
        static let digest = "digest"
    }
}

/// What was said, for a test to read back.
///
/// The system's own delivery needs an authorization, a bundle and a device,
/// none of which a test can rely on, and none of which is where the mistakes
/// are. What is worth checking is which notifications are posted and when, and
/// that is exactly what this records.
final class MemoryAnnouncer: Announcing {
    private(set) var posted: [Announcement] = []
    var granted = true
    var stated = UNAuthorizationStatus.authorized

    init() {}

    func status() async -> UNAuthorizationStatus { stated }

    func authorize() async -> Bool {
        stated = granted ? .authorized : .denied
        return granted
    }

    /// **A name replaces rather than stacks, exactly as the system does.**
    /// `add(_:)` replaces a request carrying an identifier it already holds, so
    /// a test that saw two rows where a device shows one would be testing
    /// something that cannot happen.
    func post(_ announcement: Announcement) async {
        if let name = announcement.name, let seen = posted.firstIndex(where: { $0.name == name }) {
            posted[seen] = announcement
            return
        }
        posted.append(announcement)
    }

    func withdrawEverything() async { posted.removeAll() }
}

/// Holds what a tapped notification asked for, until there is a window to show
/// it in.
///
/// The delegate has to be in place before launching finishes, or a notification
/// tapped from a cold start is never handed over ; the window and its model do
/// not exist that early. This is the one link between the two, exactly as
/// ``BackgroundWorkBox`` is for the background tasks, and it holds the answer
/// rather than dropping it.
final class NotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationRouter()

    /// What a notice leads to, which is not one kind of thing.
    ///
    /// A story is a page in the digest and an article is read over everything,
    /// exactly as a result from the system index is : the two are not opened
    /// the same way, and a single identifier would have the window guess which
    /// it was holding.
    nonisolated enum Tap: Hashable, Sendable {
        case story(UUID)
        case article(UUID)
        /// The front page itself, which is where an edition is : the edition
        /// *is* the digest, so there is nowhere deeper to go.
        case digest
    }

    /// What was tapped before anything was listening.
    private var waiting: Tap?
    private var open: ((Tap) -> Void)?

    /// Starts listening, and takes whatever was tapped before there was a
    /// window.
    func listen(_ open: @escaping (Tap) -> Void) {
        self.open = open

        if let waiting {
            self.waiting = nil
            open(waiting)
        }
    }

    /// What to do with a notice that arrives while Flong is open.
    ///
    /// **The system asks, and a delegate that does not answer means `nothing`.**
    /// Without this the banner is dropped silently, which for most of these is
    /// right : nothing is announced while the reader is reading, so a notice
    /// that reaches a foreground application is one posted a moment before they
    /// opened it, or by a pass that started while they were away. Those are
    /// worth showing, and the reader is the one who decides whether a banner
    /// interrupts them, not this.
    ///
    /// **The edition is the one that is held back, and only the edition.** A
    /// banner and a sound over the page they are about is telling somebody
    /// something they are looking at, and a pass may publish a page while the
    /// reader has the front page open in front of them.
    ///
    /// **Filed rather than dropped.** It said nothing at all before, because
    /// posting was itself the interruption ; the notice exists now whichever
    /// way this answers, and Flong being open is not the same as the front page
    /// being read. A reader three articles deep should find the paper in the
    /// centre when they come up. A row, without a banner and without a sound.
    ///
    /// **Keyed on what it is about rather than on how it arrived.** Asking
    /// whether the trigger was a calendar one would give the paper on time and
    /// the paper late two different behaviours, which is the one thing the
    /// press exists not to have.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        Self.presentation(
            thread: notification.request.content.threadIdentifier,
            isReading: isReading?() ?? false
        )
    }

    /// What the window is doing, asked at the moment a notice is offered.
    ///
    /// A closure rather than the window itself : the router is made before
    /// there is one, exactly as it holds a tap from a cold start.
    private var isReading: (() -> Bool)?

    /// Says how to answer the question above, once there is a window to ask.
    func presenting(while isReading: @escaping () -> Bool) {
        self.isReading = isReading
    }

    static func presentation(thread: String, isReading: Bool) -> UNNotificationPresentationOptions {
        guard thread == Announcement.Thread.newEdition, isReading else { return [.banner, .list, .sound] }
        return [.list]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let information = response.notification.request.content.userInfo
        let tapped: Tap? =
            if information[Notifier.Key.digest] != nil {
                .digest
            } else if let named = information[Notifier.Key.story] as? String, let story = UUID(uuidString: named) {
                .story(story)
            } else if let named = information[Notifier.Key.article] as? String, let article = UUID(uuidString: named) {
                .article(article)
            } else {
                nil
            }

        guard let tapped else { return }

        guard let open else {
            waiting = tapped
            return
        }
        open(tapped)
    }
}

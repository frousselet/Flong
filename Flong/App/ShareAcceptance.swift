//
//  ShareAcceptance.swift
//  Flong
//
//  Created by François Rousselet on 01/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CloudKit
import Foundation
import OSLog
import SwiftUI

/// Taking an invitation to a collection somebody else shared.
///
/// **This is the one thing SwiftUI has no answer for.** Everything else in the
/// application is a scene and a view ; a share is handed over by the system to
/// a delegate, `windowScene(_:userDidAcceptCloudKitShareWith:)` on iOS and
/// `application(_:userDidAcceptCloudKitShareWith:)` on the Mac, and there is no
/// modifier or scene phase that hears it. So `FlongApp`, which had no delegate
/// of any kind, gains one on each platform for this and for nothing else.
///
/// **Accepting is the whole of what happens here.** The zone then turns up in
/// the reader's shared database, where the second sync engine of ``CloudSync``
/// finds it along with everything in it. Fetching the articles here as well
/// would be doing the engine's work in front of it, and doing it twice.
nonisolated enum ShareAcceptance {
    /// What the box holds while there is no model to tell.
    ///
    /// An invitation can arrive before any window exists : tapping a link in
    /// Messages launches the application, and the delegate is called while it
    /// is still starting. The acceptance itself needs nothing but the network,
    /// so it happens at once ; what has to wait is telling the window, and this
    /// is where that waits.
    static let pending = PendingShares()

    /// Takes the invitation, and says so once there is somebody to say it to.
    static func accept(_ metadata: CKShare.Metadata) async {
        let container = CKContainer(identifier: metadata.containerIdentifier)

        do {
            _ = try await container.accept(metadata)
            Log.sync.notice("An invitation to a shared collection was accepted")
            await pending.arrived(metadata.share.recordID.zoneID.zoneName)
        } catch let error as CKError where error.code == .alreadyShared {
            // The reader is already in it, from another device or from having
            // tapped the link twice. Nothing to do and nothing to report.
            await pending.arrived(metadata.share.recordID.zoneID.zoneName)
        } catch {
            Log.sync.error("An invitation could not be accepted : \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// The invitations accepted before there was a window to show them in.
nonisolated final class PendingShares: @unchecked Sendable {
    private let lock = NSLock()
    private var zones: [String] = []
    private var announce: (@Sendable (String) async -> Void)?

    /// Called by the window once it exists, which drains whatever is waiting.
    func onArrival(_ announce: @escaping @Sendable (String) async -> Void) async {
        let waiting = lock.withLock {
            self.announce = announce
            let waiting = zones
            zones = []
            return waiting
        }
        for zone in waiting { await announce(zone) }
    }

    func arrived(_ zone: String) async {
        guard let announce = lock.withLock({ announce }) else {
            lock.withLock { zones.append(zone) }
            return
        }
        await announce(zone)
    }
}

#if os(iOS)

    /// The scene delegate, which exists only to hear about a share.
    final class ShareSceneDelegate: NSObject, UIWindowSceneDelegate {
        func windowScene(
            _ windowScene: UIWindowScene,
            userDidAcceptCloudKitShareWith metadata: CKShare.Metadata
        ) {
            Task { await ShareAcceptance.accept(metadata) }
        }
    }

    /// The application delegate, which exists only to name the scene delegate.
    ///
    /// A scene delegate is not something a SwiftUI application can hand the
    /// system directly : it is named in a scene configuration, and the only
    /// place to answer that question is here.
    final class ShareAppDelegate: NSObject, UIApplicationDelegate {
        func application(
            _ application: UIApplication,
            configurationForConnecting session: UISceneSession,
            options: UIScene.ConnectionOptions
        ) -> UISceneConfiguration {
            let configuration = UISceneConfiguration(
                name: nil,
                sessionRole: session.role
            )
            configuration.delegateClass = ShareSceneDelegate.self
            return configuration
        }
    }

#endif

#if os(macOS)

    /// The application delegate, which exists only to hear about a share.
    final class ShareAppDelegate: NSObject, NSApplicationDelegate {
        func application(_ application: NSApplication, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
            Task { await ShareAcceptance.accept(metadata) }
        }
    }

#endif

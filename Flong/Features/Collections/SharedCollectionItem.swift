//
//  SharedCollectionItem.swift
//  Flong
//
//  Created by François Rousselet on 01/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CloudKit
import CoreTransferable
import Foundation

/// A collection, as the share sheet understands one.
///
/// **This is what makes the system's own collaboration appear.** Handed to a
/// `ShareLink`, a `CKShareTransferRepresentation` tells the sheet that the item
/// is a collaboration and not a file : Messages then shows the collaboration
/// pill instead of sending a copy, and the participant list, the permissions
/// and the invitations all become the system's business rather than something
/// this application draws.
///
/// **Nothing is created until somebody is picked.** `prepareShare` hands the
/// preparation handler a moment that only arrives once the reader has actually
/// chosen a recipient, so a sheet opened out of curiosity and dismissed leaves
/// no zone, no share and no row behind. That is the whole reason to prefer it
/// to `existing`, which needs a share to have been made first.
nonisolated struct SharedCollectionItem: Transferable, Sendable {
    /// The made collection being shared, by the name the reader gave it.
    let name: String
    let sharing: CollectionSharing
    /// Sends what is already in it, once there is a zone to send it to.
    let push: @Sendable () async -> Void

    static var transferRepresentation: some TransferRepresentation {
        CKShareTransferRepresentation { item in
            .prepareShare(container: item.sharing.container) {
                // Idempotent : a second invitation to a collection already
                // shared hands back the share it already has, rather than
                // making a second zone the first participant would never see.
                let share = try await item.sharing.share(ofCollectionNamed: item.name)
                await item.sharing.rememberURL(of: share)
                // What is already in it goes with the invitation. A collection
                // that arrived empty and filled itself on the owner's next
                // filing would look, to whoever was invited, like nothing was
                // shared at all.
                await item.push()
                return share
            }
        }
    }
}

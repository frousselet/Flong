//
//  NotificationsPanel.swift
//  Flong
//
//  Created by François Rousselet on 30/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI
import UserNotifications

/// Everything Flong may interrupt the reader for, in one panel.
///
/// One switch per thing worth saying, and every one of them off until the
/// reader turns it on. There is no master switch : a list of two switches with
/// a third above them that overrules both is a list where nobody is sure what
/// is on, and the system already has that switch, in the place a reader looks
/// for it.
///
/// **A panel from the bottom, and no longer a page.** It was pushed onto a
/// navigation stack, which is a whole screen and a way back for one switch :
/// a reader who turns a notice on is not going anywhere, they are answering a
/// question and returning to what they were reading. A short sheet sits over
/// the page, holds only what it holds, and goes with a flick.
///
/// **It floats, on all four corners, and the system draws that.** A sheet is
/// already inset from the edges of the screen and rounded on all four corners
/// here ; what squared it off was what was put inside it. A `List` paints its
/// own background edge to edge, over the rounded corners and down past the
/// safe area, so the panel read as the page having been cut off rather than as
/// something laid over it. Nothing here paints a background of its own, so the
/// shape the system draws is the shape that shows.
///
/// **It says nothing it does not have to.** It carried a heading over a single
/// switch, which is a heading naming the thing under it, and a paragraph
/// explaining what a story is to somebody who reaches this from a page made of
/// them. What is left is the switch, under the panel's own name.
struct NotificationsPanel: View {
    let model: AppModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var scheme

    private var isRefused: Bool {
        model.notificationStatus == .denied
    }

    /// How tall the panel stands.
    ///
    /// Fixed rather than half the screen : the panel holds one switch, and a
    /// sheet at `.medium` for one switch is a great deal of nothing under it.
    /// The refused state is the one thing that makes it taller, since it adds
    /// a line saying why nothing here can be turned on and the way to fix it.
    ///
    /// It is the height of the sheet and not of the panel : the system insets
    /// the one inside the other, so the panel stands a little taller than the
    /// number here.
    private var height: CGFloat { isRefused ? 250 : 132 }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            head

            Toggle(
                isOn: Binding(
                    get: { model.wantsNewStoryNotices },
                    set: { wanted in Task { await model.setWantsNewStoryNotices(wanted) } }
                )
            ) {
                Label("New stories", systemImage: "newspaper.fill")
            }
            .disabled(isRefused)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            // The theme's own row, one shade off its paper, rather than the
            // system's secondary background : a grey card is the right card
            // under the standard theme and a foreign one on warm paper.
            .background(theme.surface(in: scheme), in: .rect(cornerRadius: 14))

            if isRefused {
                refusal
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .themed()
        .presentationDetents([.height(height)])
        .presentationDragIndicator(.visible)
        .task { await model.refreshNotificationStatus() }
    }

    /// What the panel is, and the way out on the platform that needs one.
    private var head: some View {
        HStack(spacing: 14) {
            Text("Notifications")
                .font(theme.headline(.title3))

            Spacer(minLength: 8)

            PanelDismiss()
        }
    }

    /// What a refusal leaves the reader able to do, which is go and undo it.
    private var refusal: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(
                "Notifications are turned off for Flong in the system settings, so nothing here can be switched on until they are allowed again."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Button {
                Notifier.openSystemSettings()
            } label: {
                Label("Open the system settings", systemImage: "gear")
                    .font(.subheadline)
            }
            .buttonStyle(.borderless)
        }
    }
}

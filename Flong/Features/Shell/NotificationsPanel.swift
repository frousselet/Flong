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
/// **It says nothing it does not have to.** A heading over a single switch
/// named the list it was heading, and a paragraph under it explained what a
/// story is to somebody who has been reading a page of them. What is left is
/// the switch and its own name, which is what the reader came to set.
struct NotificationsPanel: View {
    let model: AppModel

    @Environment(\.dismiss) private var dismiss

    private var isRefused: Bool {
        model.notificationStatus == .denied
    }

    /// How tall the panel stands.
    ///
    /// Fixed rather than half the screen : the panel holds one switch, and a
    /// sheet at `.medium` for one switch is a great deal of nothing under it.
    /// The refused state is the one thing that makes it taller, since it adds
    /// a line saying why nothing here can be turned on and the way to fix it.
    private var height: CGFloat { isRefused ? 320 : 168 }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(
                        isOn: Binding(
                            get: { model.wantsNewStoryNotices },
                            set: { wanted in Task { await model.setWantsNewStoryNotices(wanted) } }
                        )
                    ) {
                        Label("New stories", systemImage: "sparkles.rectangle.stack")
                    }
                    .disabled(isRefused)
                }

                if isRefused {
                    Section {
                        Button {
                            Notifier.openSystemSettings()
                        } label: {
                            Label("Open the system settings", systemImage: "gear")
                        }
                    } footer: {
                        Text(
                            "Notifications are turned off for Flong in the system settings, so nothing here can be switched on until they are allowed again."
                        )
                    }
                }
            }
            .navigationTitle(Text("Notifications"))
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                // A Mac sheet cannot be flicked away, so the way out is a
                // button rather than a gesture, and the same button on both
                // platforms is one thing to learn instead of two.
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.height(height)])
        .presentationCornerRadius(28)
        .task { await model.refreshNotificationStatus() }
    }
}

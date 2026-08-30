//
//  NotificationsScreen.swift
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

/// Everything Flong may interrupt the reader for, in one place.
///
/// One switch per thing worth saying, and every one of them off until the
/// reader turns it on. There is no master switch : a list of two switches with
/// a third above them that overrules both is a list where nobody is sure what
/// is on, and the system already has that switch, in the place a reader looks
/// for it.
struct NotificationsScreen: View {
    let model: AppModel

    private var isRefused: Bool {
        model.notificationStatus == .denied
    }

    var body: some View {
        List {
            Section {
                Toggle(
                    isOn: Binding(
                        get: { model.wantsNewSubjectNotices },
                        set: { wanted in Task { await model.setWantsNewSubjectNotices(wanted) } }
                    )
                ) {
                    Label("New subjects", systemImage: "square.stack.3d.up")
                }
                .disabled(isRefused)
            } header: {
                Text("What Flong tells you")
            } footer: {
                Text(
                    "The model reads your front page and sorts it into subjects. Flong can tell you when it finds one it has never used before, which is usually a subject the press has just started covering."
                )
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
        .task { await model.refreshNotificationStatus() }
    }
}

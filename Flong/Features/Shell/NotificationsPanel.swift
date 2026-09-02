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

    /// The sources and the writers the reader asked to be told about, which are
    /// switches like any other and belong in the one panel that holds them all.
    private var sources: [Feed] { model.announcingSources }
    private var writers: [String] { model.notifiedAuthors }

    /// How many rows the panel stands tall enough to show before the rest is
    /// scrolled to.
    private static let shownSources = 4

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
    private var height: CGFloat {
        let switches: CGFloat = model.hasSharedCollections ? 62 : 0
        // The sources the reader asked about, up to the point where the panel
        // would be the whole page. Past that they scroll, and the reader can
        // pull the panel up to see the rest at once.
        let rows = min(sources.count + writers.count, Self.shownSources)
        let announced: CGFloat = rows == 0 ? 0 : 40 + CGFloat(rows) * 62
        return (isRefused ? 250 : 132) + switches + announced
    }

    /// What the panel may be pulled to, which is the whole page only when there
    /// is more in it than a panel can hold.
    private var detents: Set<PresentationDetent> {
        sources.count + writers.count > Self.shownSources ? [.height(height), .large] : [.height(height)]
    }

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

            // **Only where there is somebody to collaborate with.** A switch
            // about shared collections, on a device that is in none, is a
            // question about something the reader has never seen : the panel
            // says nothing rather than offering it. It appears the moment they
            // share one or are invited to one.
            if model.hasSharedCollections {
                Toggle(
                    isOn: Binding(
                        get: { model.wantsCollaborationNotices },
                        set: { wanted in Task { await model.setWantsCollaborationNotices(wanted) } }
                    )
                ) {
                    Label("Additions to shared collections", systemImage: "folder.badge.person.crop")
                }
                .disabled(isRefused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(theme.surface(in: scheme), in: .rect(cornerRadius: 14))
            }

            announcingSources

            if isRefused {
                refusal
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .themed()
        .presentationDetents(detents)
        .presentationDragIndicator(.visible)
        .task {
            await model.refreshNotificationStatus()
            // The sources come with the sidebar, which is always in step ; the
            // writers are a question nothing else in the window asks, so the
            // panel asks it when it opens.
            await model.loadNotifiedAuthors()
        }
    }

    /// The sources and the writers that announce everything they publish, one
    /// row apiece.
    ///
    /// **Only where there are any**, exactly as the shared collections are :
    /// the switch that puts one here is on the source or on the person, where
    /// the decision belongs, and a heading over an empty list would be the
    /// panel asking a question with nowhere to answer it.
    ///
    /// **One list and not two.** They are two kinds of thing to the machinery
    /// and one thing to the reader, who is looking at what may interrupt them ;
    /// a heading apiece over two rows each would be filing where there is
    /// nothing to file. The glyph says which is which : a publisher wears the
    /// aerial the sources list gives it, a person wears a signature.
    ///
    /// A row is one that is on, so switching it off takes it out of the list.
    /// This is where they are all seen at once and quietened, which is what a
    /// reader wants when several turn out to be louder than they expected ;
    /// adding one is done where the source or the writer is.
    @ViewBuilder
    private var announcingSources: some View {
        if !sources.isEmpty || !writers.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("New articles")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(sources) { source in
                            // Verbatim : it is what the publisher calls itself,
                            // or what the reader called it.
                            announcing(source.title, icon: "dot.radiowaves.up.forward") { wanted in
                                await model.setNotifications(wanted, forSource: source.id)
                            }
                        }
                        // Verbatim too : a person is called what they are
                        // called in every language.
                        ForEach(writers, id: \.self) { writer in
                            announcing(writer, icon: "signature") { wanted in
                                await model.setNotifications(wanted, forAuthor: writer)
                            }
                        }
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }

    /// One thing that may interrupt the reader, and the switch that stops it.
    private func announcing(
        _ name: String,
        icon: String,
        set: @escaping (Bool) async -> Void
    ) -> some View {
        Toggle(
            isOn: Binding(
                get: { true },
                set: { wanted in Task { await set(wanted) } }
            )
        ) {
            Label {
                Text(verbatim: name)
                    .lineLimit(1)
            } icon: {
                Image(systemName: icon)
            }
        }
        .disabled(isRefused)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(theme.surface(in: scheme), in: .rect(cornerRadius: 14))
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

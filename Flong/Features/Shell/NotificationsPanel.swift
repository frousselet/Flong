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
/// reader turns it on.
///
/// **The first of them covers every source.** There was none : an article
/// notice was asked for one publisher at a time, from a menu on that
/// publisher's own row, and a reader who follows thirty feeds and wants to know
/// when any of them publishes had thirty decisions to make to say one thing.
/// Most of them never found the menu at all, and this panel, the one place they
/// looked, offered them nothing about articles. The finer instrument stays,
/// where it belongs, and what it singles out is listed underneath.
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
    @Environment(\.scenePhase) private var scenePhase

    private var isRefused: Bool {
        model.notificationStatus == .denied
    }

    /// Whether the system has been told to stop doing anything nobody asked
    /// for, which includes waking a feed reader every half hour.
    ///
    /// Said here because nothing else in the application says it. A reader in
    /// Low Power Mode with every switch on gets nothing, and an application
    /// that stays quiet about the reason looks broken rather than obedient.
    private var isSaving: Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }

    /// The sources, the writers and the people the reader asked to be told
    /// about, which are switches like any other and belong in the one panel
    /// that holds them all.
    private var sources: [Feed] { model.announcingSources }
    private var writers: [String] { model.notifiedAuthors }
    private var people: [String] { model.notifiedNewsmakers }

    /// How many rows the announcing list holds, whatever kind each of them is.
    private var announcing: Int { sources.count + writers.count + people.count }

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
        let rows = min(announcing, Self.shownSources)
        let announced: CGFloat = rows == 0 ? 0 : 40 + CGFloat(rows) * 62
        return (isRefused ? 312 : 194) + switches + announced
    }

    /// What the panel may be pulled to.
    ///
    /// The full page is always one of them. The height above is an estimate of
    /// what is drawn, and an estimate is what it can only ever be : the rows
    /// grow with the reader's type size, so a reader at the accessibility sizes
    /// had a panel too short for its own content and no way to make it taller.
    private var detents: Set<PresentationDetent> {
        [.height(height), .large]
    }

    var body: some View {
        // Scrolled rather than laid out to a height. The panel stands at the
        // height of what it holds, and what it holds grows with the reader's
        // type size : at the accessibility sizes the way out of a refusal was
        // below the bottom of the sheet, where nothing could reach it.
        ScrollView {
            content
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .themed()
        .presentationDetents(detents)
        .presentationDragIndicator(.visible)
        .task {
            await model.refreshNotificationStatus()
            // The sources come with the sidebar, which is always in step ; the
            // writers and the people are questions nothing else in the window
            // asks, so the panel asks them when it opens.
            await model.loadNotifiedAuthors()
            await model.loadNotifiedNewsmakers()
        }
        // A reader sent to the system settings comes back having changed the
        // one answer this panel cannot change, and the panel has to ask again :
        // it read the refusal once, when it opened, and stayed refused for the
        // rest of the session however the reader answered.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await model.refreshNotificationStatus() }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            head

            Toggle(
                isOn: Binding(
                    get: { model.wantsNewArticleNotices },
                    set: { wanted in Task { await model.setWantsNewArticleNotices(wanted) } }
                )
            ) {
                Label("New articles", systemImage: "bell.fill")
            }
            .disabled(isRefused)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(theme.surface(in: scheme), in: .rect(cornerRadius: 14))

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
            } else if isSaving {
                saving
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
    }

    /// The sources and the writers that announce everything they publish, one
    /// row apiece.
    ///
    /// **Only where there are any**, exactly as the shared collections are :
    /// the switch that puts one here is on the source or on the person, where
    /// the decision belongs, and a heading over an empty list would be the
    /// panel asking a question with nowhere to answer it.
    ///
    /// **One list and not three.** They are three kinds of thing to the
    /// machinery and one thing to the reader, who is looking at what may
    /// interrupt them ; a heading apiece over two rows each would be filing
    /// where there is nothing to file. The glyph says which is which : a
    /// publisher wears the aerial the sources list gives it, a writer wears a
    /// signature, and somebody the articles are about wears the mark their own
    /// square wears.
    ///
    /// A row is one that is on, so switching it off takes it out of the list.
    /// This is where they are all seen at once and quietened, which is what a
    /// reader wants when several turn out to be louder than they expected ;
    /// adding one is done where the source, the writer or the person is.
    @ViewBuilder
    private var announcingSources: some View {
        if announcing > 0 {
            VStack(alignment: .leading, spacing: 8) {
                // Named for what they are rather than for what they announce :
                // with the switch above on, every source announces, and these
                // are the ones the reader singled out one at a time.
                Text("Asked about one at a time")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

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
                    // Verbatim too, and for the same reason.
                    ForEach(people, id: \.self) { person in
                        announcing(person, icon: "person.crop.rectangle.stack") { wanted in
                            await model.setNotifications(wanted, forNewsmaker: person)
                        }
                    }
                }
            }
        }
    }

    /// One thing that may interrupt the reader, and the switch that stops it.
    ///
    /// **Never disabled, unlike the switches above.** A row is here because it
    /// is on, so the only thing its switch does is turn it off, and that asks
    /// the system for nothing. Held out with the rest of the panel under a
    /// refusal, it left a reader who had refused Flong at the system level
    /// unable to quieten the sources still queued to interrupt them.
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

    /// Why a reader with every switch on may still be hearing nothing.
    ///
    /// Low Power Mode is the reader telling the system, in so many words, to
    /// stop doing things they did not ask for, and Flong stands aside for it.
    /// Saying so is the difference between an application that obeys and one
    /// that looks broken.
    private var saving: some View {
        Text(
            "Low Power Mode is on, so Flong is not fetching in the background. Opening it still refreshes."
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
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

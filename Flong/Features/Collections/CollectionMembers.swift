//
//  CollectionMembers.swift
//  Flong
//
//  Created by François Rousselet on 02/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import CoreGraphics
import SwiftUI

/// One person in a shared collection, as one small round thing.
///
/// The same three states as ``ReaderMark``, and in the same order a reader
/// arrives at them : the picture they chose, the initials of the name they
/// gave, and the generic face of somebody who has told the application nothing
/// about themselves. The third is not a failure : a participant is under no
/// obligation to have a face, and CloudKit has none to give on their behalf.
struct MemberFace: View {
    let member: ShareMember
    /// Their picture, decoded once by the model rather than at each draw.
    var face: CGImage?
    var side: CGFloat = 30

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Group {
            if let face {
                Image(decorative: face, scale: displayScale)
                    .resizable()
                    .scaledToFill()
            } else if let initials = member.initials {
                Text(verbatim: initials)
                    .font(.system(size: side * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Circle().fill(.tint))
            } else {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: side * 0.9))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: side, height: side)
        .clipShape(.circle)
        // Somebody who has not answered the invitation yet is drawn faintly
        // rather than left out : an owner who invited somebody a week ago and
        // sees nothing cannot tell a refusal from a message that never came.
        .opacity(member.standing == .invited ? 0.45 : 1)
        .accessibilityHidden(true)
    }
}

/// Who is in a collection, as a handful of overlapping faces.
///
/// **For a square, where there is room for a glance and not for a list.** Three
/// at most and a count for the rest : a pile that grew with the collection
/// would end up as a row of slivers saying nothing.
///
/// Each face is ringed in the colour behind it, which is what keeps two
/// overlapping circles legible over a photograph without a scrim between the
/// reader and the picture they came to recognize.
struct MemberPile: View {
    let members: [ShareMember]
    let faces: [String: CGImage]
    var side: CGFloat = 24

    private static let shown = 3

    var body: some View {
        if !members.isEmpty {
            HStack(spacing: -side / 3) {
                ForEach(members.prefix(Self.shown)) { member in
                    MemberFace(member: member, face: faces[member.id], side: side)
                        .background(Circle().fill(.background))
                        .overlay(Circle().strokeBorder(.background, lineWidth: 1.5))
                }

                if members.count > Self.shown {
                    Text(verbatim: "+\(members.count - Self.shown)")
                        .font(.system(size: side * 0.38, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: side, height: side)
                        .background(Circle().fill(.thickMaterial))
                        .overlay(Circle().strokeBorder(.background, lineWidth: 1.5))
                }
            }
            .accessibilityElement()
            .accessibilityLabel(Text("\(members.count) people"))
        }
    }
}

/// Everybody in a shared collection, along the top of it and staying there.
///
/// **The pills of the front page, for the people instead of the subjects.** The
/// digest already draws a strip of glass capsules that pins itself to the head
/// of the page as it scrolls, on the argument that a control a reader may want
/// while they are reading should not be somewhere they have to scroll back up
/// to. Who is in a collection is the same kind of thing : it is what the page
/// is about, and it is where the one command about a person lives.
///
/// It is the second place in the application to draw glass of its own, and it
/// is allowed for the same reason as the first : a pill is a control floating
/// over the page, which is the layer Apple's material is for.
///
/// **A menu and never a context menu.** ``DigestScreen`` records the finding
/// and it holds here : a context menu over glass never fires at all. The pill
/// is a `Menu` for the people the reader may take out, and a plain capsule for
/// everybody else, so a pill that opens nothing is a pill that says nothing
/// will happen.
///
/// **Taking somebody out is the owner's alone.** A share is theirs to change
/// and the server refuses everybody else, so a participant is shown who is in
/// the collection without being offered a button that could not work.
struct MembersStrip: View {
    let members: [ShareMember]
    let faces: [String: CGImage]
    /// Whether this reader may take somebody out : see
    /// ``AppModel/mayRemoveMembers(of:)``.
    var mayRemove = false
    var remove: (ShareMember) -> Void = { _ in }

    @State private var removing: ShareMember?
    @Namespace private var pills
    @Environment(\.theme) private var theme

    var body: some View {
        if !members.isEmpty {
            ScrollView(.horizontal) {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(members) { member in
                            pill(for: member)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
            .scrollIndicators(.hidden)
            .scrollClipDisabled()
            .accessibilityLabel(Text("In this collection"))
            .confirmationDialog(
                Text("Remove \(removing?.displayName ?? String(localized: "this person"))?"),
                isPresented: .init(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                titleVisibility: .visible
            ) {
                Button("Remove", role: .destructive) {
                    if let removing { remove(removing) }
                    removing = nil
                }
                Button("Cancel", role: .cancel) { removing = nil }
            } message: {
                // Said plainly, because it is the half a reader does not expect
                // and would otherwise discover afterwards.
                Text("They lose the collection. What they already filed stays in it.")
            }
        }
    }

    /// One person, as a capsule of glass.
    ///
    /// The owner is never one of the ones that open : a share cannot be without
    /// them, and neither can the reader themselves be taken out by themselves.
    @ViewBuilder
    private func pill(for member: ShareMember) -> some View {
        if mayRemove, !member.isOwner {
            Menu {
                Button(role: .destructive) {
                    removing = member
                } label: {
                    Label("Remove from the collection", systemImage: "person.crop.circle.badge.minus")
                }
            } label: {
                label(for: member)
            }
            .buttonStyle(.plain)
            .modifier(MemberPill(id: member.id, namespace: pills))
        } else {
            label(for: member)
                .modifier(MemberPill(id: member.id, namespace: pills))
        }
    }

    private func label(for member: ShareMember) -> some View {
        HStack(spacing: 7) {
            MemberFace(member: member, face: faces[member.id])

            VStack(alignment: .leading, spacing: 0) {
                name(of: member)
                    .font(.system(.subheadline))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let note = note(about: member) {
                    note
                        .font(theme.metadata)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.leading, 5)
        .padding(.trailing, 13)
        .padding(.vertical, 5)
        .contentShape(.capsule)
        .accessibilityElement(children: .combine)
    }

    /// What to call somebody, when there is anything to call them.
    ///
    /// The reader is named as themselves rather than by their own name : a list
    /// of people that tells you your name is a list you have to read to find
    /// yourself in.
    private func name(of member: ShareMember) -> Text {
        if member.isMe { return Text("You") }
        guard let name = member.displayName else { return Text("Someone") }
        return Text(verbatim: name)
    }

    /// The one line under a name, where there is anything worth saying.
    ///
    /// **It reads on from the name above it, so the verb agrees with it.**
    /// `Vous / A partagé` is not a sentence anybody would write : it is
    /// `Vous / Avez partagé` and `Elise / A partagé`. English has no agreement
    /// to make and says the same thing both ways, which is why the two are two
    /// strings rather than one with a person in it.
    private func note(about member: ShareMember) -> Text? {
        if member.standing == .invited { return Text("Invited") }
        if member.isOwner { return member.isMe ? Text("You shared this") : Text("Shared this") }
        if !member.mayWrite { return Text("Reading only") }
        return nil
    }
}

/// The glass one person's pill is drawn on.
///
/// Its own modifier so a menu and a plain capsule wear exactly the same one,
/// which is what ``DigestScreen`` does for the subjects and for the same
/// reason : what changes between two pills must not be their size.
private struct MemberPill: ViewModifier {
    let id: String
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        content
            .glassEffect(.regular.interactive(), in: .capsule)
            .glassEffectID(id, in: namespace)
    }
}

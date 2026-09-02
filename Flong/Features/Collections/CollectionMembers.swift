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

/// Everybody in a shared collection, along the top of it.
///
/// **A list rather than a pile, because this is the page about the
/// collection.** A square has room for a glance ; here there is room to say
/// who each face is, which is the difference between knowing that a collection
/// is shared and knowing who it is shared with.
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
    @Environment(\.theme) private var theme

    var body: some View {
        if !members.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("In this collection")
                    .font(.system(.footnote, weight: .semibold))
                    .textCase(.uppercase)
                    .kerning(0.6)
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(members) { member in
                            chip(for: member)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
            .padding(.top, Editorial.rhythm)
            .padding(.bottom, 4)
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

    private func chip(for member: ShareMember) -> some View {
        HStack(spacing: 7) {
            MemberFace(member: member, face: faces[member.id])

            VStack(alignment: .leading, spacing: 0) {
                name(of: member)
                    .font(.system(.subheadline))
                    .lineLimit(1)
                if let note = note(about: member) {
                    note
                        .font(theme.metadata)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.leading, 5)
        .padding(.trailing, 12)
        .padding(.vertical, 5)
        .background(Capsule().fill(.quaternary))
        .contextMenu {
            if mayRemove, !member.isOwner {
                Button(role: .destructive) {
                    removing = member
                } label: {
                    Label("Remove from the collection", systemImage: "person.crop.circle.badge.minus")
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityActions {
            if mayRemove, !member.isOwner {
                Button("Remove from the collection") { removing = member }
            }
        }
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
    private func note(about member: ShareMember) -> Text? {
        if member.standing == .invited { return Text("Invited") }
        if member.isOwner { return Text("Shared this") }
        if !member.mayWrite { return Text("Reading only") }
        return nil
    }
}

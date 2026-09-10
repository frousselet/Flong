//
//  EditionSettings.swift
//  Flong
//
//  Created by François Rousselet on 04/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import SwiftUI

/// When the four editions come out.
///
/// **Four, and the hours are the reader's.** A paper comes out at an hour and
/// the hour is not the same for everybody : somebody who reads on the train at
/// half past six is not served by a morning edition made at seven. Each of the
/// four can be moved, and each can be switched off outright, which is what a
/// reader who only ever looks in the evening will do with the other three.
///
/// Switching every one of them off is a legitimate answer and leaves no front
/// page at all, so the screen says so rather than letting the reader find out
/// on the page next door.
struct EditionSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        List {
            Section {
                ForEach(EditionSlot.allCases, id: \.self) { slot in
                    row(slot)
                }
            } header: {
                Text("Editions")
            } footer: {
                if model.editionSchedule.slots.isEmpty {
                    Text("With every edition off there is no front page. The wire still holds everything.")
                } else {
                    // One literal and never two joined by `+`. A concatenation
                    // is not a string literal, so SwiftUI picks the initializer
                    // that does not localize at all : the sentence would have
                    // read in English on a French device, and nothing would
                    // have said so.
                    Text(
                        "Each edition holds what happened since the one before it, with the stories that matter most. It does not change until the next one comes out, and what did not fit stays in the wire."
                    )
                }
            }

            length
        }
        .navigationTitle(Text("Editions"))
    }

    /// How long the reader wants their paper.
    ///
    /// **Three lengths in words, with the count under each.** A stepper on a
    /// number would ask the reader to have an opinion about a figure, and the
    /// figure is not what they have an opinion about : they want a short paper
    /// or a long one. The count is said all the same, since it is the only
    /// thing that separates the three and a reader picking blind would have to
    /// pick twice to find out.
    private var length: some View {
        Section {
            Picker(selection: $model.editionSize) {
                ForEach(EditionSize.allCases) { size in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(size.title)
                        Text("\(size.stories) stories")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                    .tag(size)
                }
            } label: {
                Text("Length")
            }
            .pickerStyle(.inline)
            .labelsHidden()
            .accessibilityIdentifier("edition-length")
        } header: {
            Text("Length")
        } footer: {
            Text(
                "A longer edition carries more stories. It takes nothing out of the wire, which holds everything either way."
            )
        }
    }

    private func row(_ slot: EditionSlot) -> some View {
        let minutes = model.editionSchedule.hours[slot]

        return VStack(alignment: .leading, spacing: 8) {
            Toggle(
                isOn: Binding(
                    get: { minutes != nil },
                    set: { wanted in
                        var schedule = model.editionSchedule
                        schedule.hours[slot] = wanted ? slot.defaultHour * 60 : nil
                        model.editionSchedule = schedule
                    }
                )
            ) {
                Text(slot.title)
            }

            if let minutes {
                DatePicker(
                    selection: Binding(
                        get: { Self.time(ofMinutes: minutes) },
                        set: { chosen in
                            var schedule = model.editionSchedule
                            schedule.hours[slot] = Self.minutes(of: chosen)
                            model.editionSchedule = schedule
                        }
                    ),
                    displayedComponents: .hourAndMinute
                ) {
                    Text("Time")
                }
            }
        }
        .accessibilityIdentifier("edition-\(slot.rawValue)")
    }

    /// A minute of the day as a moment today, which is what a picker wants.
    ///
    /// The day itself is thrown away on the way back : what is stored is a
    /// minute of the day, so a reader who sets an hour on a Tuesday does not
    /// have a schedule that expires on Wednesday.
    private static func time(ofMinutes minutes: Int, in calendar: Calendar = .current) -> Date {
        calendar.date(
            bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date(), matchingPolicy: .nextTime)
            ?? Date()
    }

    private static func minutes(of date: Date, in calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

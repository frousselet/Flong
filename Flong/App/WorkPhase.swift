//
//  WorkPhase.swift
//  Flong
//
//  Created by François Rousselet on 31/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// One thing the machinery does, named in words a reader can read.
///
/// **One vocabulary for the whole application.** The front page and the sources
/// list say the same thing about the same work, and two descriptions of one
/// pass are two descriptions that stop agreeing.
nonisolated enum WorkPhase: String, Hashable, Sendable, CaseIterable {
    case fetching
    case grouping
    case indexing
    case reading
    case writing
    case filing
    case tidying
    case synchronizing
    case exchanging

    /// What the reader is told, which is what is being brought in rather than
    /// which function is running.
    var title: LocalizedStringResource {
        switch self {
        case .fetching: "Fetching the feeds"
        case .grouping: "Grouping what arrived"
        case .indexing: "Indexing what you kept"
        case .reading: "Reading who is in the news"
        case .writing: "Writing the headlines"
        case .filing: "Filing the subjects"
        case .tidying: "Tidying up"
        case .synchronizing: "Synchronizing with iCloud"
        case .exchanging: "Exchanging with your other devices"
        }
    }

    /// Whether the stage can say how much of itself it has done.
    ///
    /// Five can, and they are the five that matter : each is a queue the store
    /// can count, of feeds, of stories or of articles. The others are a single
    /// query, a purge, or an exchange the system runs at its own pace.
    var isCountable: Bool {
        switch self {
        case .fetching, .writing, .filing, .indexing, .reading: true
        case .grouping, .tidying, .synchronizing, .exchanging: false
        }
    }

    /// What a stage nobody can count is worth, so the bar still moves through
    /// it rather than stopping dead.
    ///
    /// Small on purpose. A pass of three hundred feeds and sixty stories is
    /// hundreds of units, and a stage that cannot be counted should not be able
    /// to claim a quarter of the bar for a query that takes a moment.
    static let nominalUnits = 3
}

/// A whole pass, as one measure.
///
/// **The bar used to belong to each stage in turn.** Every stage brought its
/// own count, so a pass ran a bar from nothing to full, then from nothing to
/// full again, then again : five bars where the reader was doing one thing and
/// waiting for one answer. Nobody reads that as progress. They read it as an
/// application that keeps starting over.
///
/// So a pass declares what it is made of before it begins, and each stage owns
/// a **share** of the one bar. Two rules make the shares behave, and both were
/// learned the hard way :
///
/// - **They are settled when the pass is planned, and never move again.** They
///   were recomputed from live counts as the pass went, so the arithmetic under
///   the bar kept changing : a stage discovering it was bigger than it was told
///   made every earlier stage worth proportionally less, and the bar went
///   backwards. A reader cannot be asked to believe a measure that retreats.
/// - **No stage may be worth nothing, and none may be worth everything.** The
///   share is what the store says a stage will cost, blended halfway with an
///   equal split. Weighted purely by cost, a pass whose stories had not been
///   grouped yet gave the model's two stages nothing at all, so the fetching
///   owned the whole rail and finishing it left the bar full with two stages
///   still to run.
///
/// Within its own share a stage measures itself, from the queue it is working
/// through, so the bar moves smoothly rather than in steps. What a stage cannot
/// count contributes its share on the way out instead.
nonisolated struct WorkPlan: Hashable, Sendable {
    /// How much of the bar is split evenly rather than by measured cost.
    ///
    /// Half. All of it and a pass is eight equal steps, which says nothing
    /// about three hundred feeds against three stories ; none of it and a stage
    /// the store cannot count yet is worth nothing at all.
    static let evenness = 0.5

    /// The stages, in the order the pass will go through them.
    private let stages: [WorkPhase]
    /// What share of the bar each one owns. Settled once.
    private let share: [WorkPhase: Double]
    /// Which one is running.
    private(set) var phase: WorkPhase
    /// How far through the one running, nought to one.
    private var within: Double = 0
    /// The furthest the bar has been, which is the furthest it is ever shown.
    private var reached: Double = 0

    init(_ stages: [WorkPhase], costing costs: [WorkPhase: Int] = [:]) {
        let stages = stages.isEmpty ? [.fetching] : stages
        self.stages = stages
        self.phase = stages[0]

        var weight: [WorkPhase: Double] = [:]
        for stage in stages {
            weight[stage] = Double(stage.isCountable ? max(costs[stage] ?? 0, 0) : WorkPhase.nominalUnits)
        }

        let measured = weight.values.reduce(0, +)
        let even = 1 / Double(stages.count)
        var share: [WorkPhase: Double] = [:]
        for stage in stages {
            let byCost = measured > 0 ? (weight[stage] ?? 0) / measured : even
            share[stage] = Self.evenness * even + (1 - Self.evenness) * byCost
        }
        self.share = share
    }

    /// How far along the whole pass is, or `nil` where there is nothing in it
    /// that can be measured and the bar should simply run.
    var fraction: Double? {
        guard stages.contains(where: \.isCountable) else { return nil }
        return reached
    }

    /// Moves to a stage, crediting every stage before it in full.
    mutating func begin(_ phase: WorkPhase) {
        guard stages.contains(phase), phase != self.phase else { return }
        self.phase = phase
        within = 0
        settle()
    }

    /// Moves the stage running through its own share.
    mutating func advance(done: Int, total: Int) {
        guard total > 0 else { return }
        within = min(Double(done) / Double(total), 1)
        settle()
    }

    /// Everything owned by the stages already over, which is where this stage
    /// starts from.
    private var base: Double {
        let index = stages.firstIndex(of: phase) ?? 0
        return stages.prefix(index).reduce(0) { $0 + (share[$1] ?? 0) }
    }

    private mutating func settle() {
        reached = max(reached, min(base + (share[phase] ?? 0) * within, 1))
    }
}

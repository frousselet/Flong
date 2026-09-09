//
//  ModelProvider.swift
//  Flong
//
//  Created by François Rousselet on 09/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation

/// Something that answers a question put in a shape.
///
/// Section 14 treats the model as a feature flag : the path without it is
/// always present and always tested. This is what makes there be more than one
/// flag. The system's own model is one of these, and so is a service the reader
/// configured with credentials of their own ; nothing above this line knows
/// which it is talking to.
nonisolated protocol ModelProvider: Sendable {
    /// What the settings screen and the log line call it.
    var name: String { get }

    /// The host that will be spoken to, or nothing where nothing leaves the
    /// device. The consent names it and the log records it, so it can never be
    /// a secret.
    var host: String? { get }

    var isAvailable: Bool { get }

    /// Why it cannot be used, in a sentence for the reader, or nothing when it
    /// can.
    var absence: LocalizedStringResource? { get }

    /// Whether it writes the language the reader reads in.
    ///
    /// Not a reason to stop asking : a language a model does not write is one
    /// it is not asked for, and the articles' own language is asked for
    /// instead. What it gates is the check on the answer.
    func writes(_ locale: Locale) -> Bool

    /// How many of a thing are worth putting to it in one batch.
    ///
    /// Three on the device, where a call is a tenth of a second and free. One
    /// at a distance, where a call is seconds and the reader's own money, and
    /// where a slice of work that overruns should overrun by one item.
    var batch: Int { get }

    /// Whether a thing it will not write about is worth putting to it a second
    /// way.
    ///
    /// True on the device, where a third of ordinary news trips the guardrail
    /// and the condensing voice recovers four refusals in ten. False at a
    /// distance, where the second voice is a second paid call for a refusal
    /// that was not a guardrail.
    var triesASecondVoice: Bool { get }

    /// Opens an exchange.
    ///
    /// Deliberately not `async`, and deliberately handing back something that
    /// is not `Sendable` : the system's conversation holds a
    /// `LanguageModelSession`, which the framework does not make sendable, so
    /// nothing here may cross an isolation boundary. A conversation is opened,
    /// used and dropped inside one call.
    func conversation(saying instructions: String) -> any ModelConversation
}

/// One exchange with one model, from the first question to the last.
///
/// **The exchange is the unit and not the call**, because the hardest thing
/// either side does is ask again. A headline that came back too long is asked
/// for again in the same breath, so the model can see what it just wrote ; a
/// standfirst that repeated its headline is asked for on its own, third, with
/// everything already said still in front of it. Both sides remember : one in
/// a session the framework keeps, the other in an array of turns.
nonisolated protocol ModelConversation: AnyObject {
    /// Free, and worth doing where the assets have to load anyway.
    func prewarm()

    /// Whether one more question of this size fits beside everything already
    /// said, with room left for an answer.
    func hasRoom(for question: String, keeping budget: Int) async -> Bool

    /// Asks, and remembers the turn.
    func answer(to question: String, shaped: ResponseShape, keeping budget: Int) async throws(ModelFault) -> Answer
}

nonisolated extension ModelConversation {
    func prewarm() {}

    /// The same question, read into the shape the caller wanted.
    ///
    /// An answer that will not read into its own shape is this thing and not
    /// the model : it answered, and what it answered was the wrong shape, which
    /// is the class ``ModelFault/unreadable`` names and which no provider is
    /// given up on for.
    func answer<A: ModelAnswer>(
        to question: String,
        as type: A.Type = A.self,
        keeping budget: Int
    ) async throws(ModelFault) -> A {
        let answer = try await self.answer(to: question, shaped: A.shape, keeping: budget)
        do {
            return try A(answer)
        } catch {
            throw .unreadable
        }
    }
}

/// Why an ask did not produce an answer.
///
/// **The three the callers already act on, given names.** The one namespace every caller went
/// through drew the line between a model that will not write about one story and a model
/// that cannot be used, and three call sites drew the same conclusion from it
/// by hand. Everything a provider can fail with lands in one of these, and the
/// line is drawn once.
///
/// **Nothing from the wire is carried here.** A service is free to echo the
/// prompt into the body of its own error, and several do ; an error that
/// carried one would carry an article, and eventually a key, into a log line.
/// A small closed enumeration is what makes that a property a test can prove.
nonisolated enum ModelFault: Error, Hashable, Sendable {
    /// It read this and would not write about it.
    case declined

    /// What came back was not the shape asked for.
    case unreadable

    /// It did not fit in the window.
    case tooLong

    /// It is there and busy, which is the opposite of a reason to stop coming
    /// back.
    case busy(retryAfter: TimeInterval?)

    /// It cannot be used at all.
    case unusable(Reason)

    nonisolated enum Reason: Hashable, Sendable {
        /// The model is not on this device, or not loaded yet.
        case absent
        /// The key was refused.
        case notEntitled
        /// It was asked and nothing came back.
        case unreachable
        /// The address, the model name, or something else the reader set.
        case misconfigured
        /// The reader left, which is never counted against anything.
        case cancelled
    }

    /// Whether this says something about the model rather than about the thing
    /// it was shown.
    var isTheModelItself: Bool {
        switch self {
        case .declined, .unreadable, .tooLong: false
        case .busy, .unusable: true
        }
    }

    /// Whether this is the model asking for a moment.
    ///
    /// A rate limit and a clash of concurrent requests are the system saying to
    /// come back, which is the opposite of a reason to stop coming back. They
    /// stop this call and count towards nothing.
    var isBusy: Bool {
        switch self {
        case .busy, .unusable(.cancelled): true
        default: false
        }
    }
}

/// What came of asking : the three answers every call site already draws.
///
/// **Three and not two.** An optional folded a model that answered with nothing
/// into a model that could not be asked, and the caller then stamped the work
/// as done either way : one guardrail refusal, one rate limit or one moment
/// with the assets unloaded left a story unfiled for good. Written out three
/// times in three files it drifted ; written once it cannot.
nonisolated enum Answered<Value: Sendable>: Sendable {
    case wrote(Value)
    /// This thing, under this voice. Another voice is worth a try.
    case declined
    /// The model, not the thing : busy, or not there at all. Nothing may be
    /// stamped as answered.
    case unusable

    init(failing fault: ModelFault) {
        self = fault.isTheModelItself ? .unusable : .declined
    }

    var written: Value? {
        guard case .wrote(let value) = self else { return nil }
        return value
    }
}

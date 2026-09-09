//
//  ModelCatalogueTests.swift
//  FlongTests
//
//  Created by François Rousselet on 09/09/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing

@testable import Flong

/// Which models a service offers, and whether it answers at all.
@Suite("Testing a model of the reader's own", .serialized)
struct ModelCatalogueTests {
    /// A host of its own, and every suite that stubs one needs one : the
    /// registry is keyed by host, so two suites sharing an address take each
    /// other's handlers away when either of them resets.
    private static let host = "catalogue.example.com"

    private func account(model: String = "a-model") -> ProviderAccount {
        ProviderAccount(
            kind: .openAICompatible,
            name: "Mine",
            origin: URL(string: "https://\(Self.host)/v1"),
            model: model
        )
    }

    private let secret = ProviderSecret(key: "not-a-real-key")

    private func catalogue(_ stub: StubServer) -> ModelCatalogue {
        ModelCatalogue(transport: CloudTransport(session: stub.makeSession()))
    }

    @Test("The models a service offers come back newest first")
    func theListIsNewestFirst() async throws {
        let stub = StubServer(host: Self.host)
        defer { stub.reset() }
        stub.install { _ in
            .json(#"{"data":[{"id":"old","created":1000},{"id":"new","created":2000},{"id":"undated"}]}"#)
        }

        let models = try #require(try? await catalogue(stub).models(of: account(), with: secret).get())

        #expect(models.map(\.id) == ["new", "old", "undated"])
        #expect(try #require(stub.requests.first).url.path() == "/v1/models")
    }

    /// Several servers a reader may point Flong at route only the completion
    /// path. `The service will not say` is a state, not a failure : the field
    /// beside the menu is where they type the name themselves.
    @Test("A service that will not list its models is not a service that failed")
    func aMissingListIsNotAFailure() async throws {
        let stub = StubServer(host: Self.host)
        defer { stub.reset() }
        stub.install { _ in .json("{}", status: 404) }

        let models = try? await catalogue(stub).models(of: account(), with: secret).get()

        #expect(models?.isEmpty == true)
    }

    /// A refused key is worth reporting, because it means the key itself is
    /// wrong and nothing further will work.
    @Test("A refused key is reported rather than swallowed")
    func aRefusedKeyIsReported() async {
        let stub = StubServer(host: Self.host)
        defer { stub.reset() }
        stub.install { _ in .json("{}", status: 401) }

        let answer = await catalogue(stub).models(of: account(), with: secret)

        #expect(answer == .failure(.keyRefused))
    }

    /// The whole configuration proved in one cheap round trip : the key, the
    /// address, the model name, and the way the question has to be shaped.
    @Test("A test that works says how long it took and what answered")
    func aWorkingProviderAnswers() async throws {
        let stub = StubServer(host: Self.host)
        defer { stub.reset() }
        stub.install { request in
            guard request.path.hasSuffix("chat/completions") else {
                return .json(#"{"data":[{"id":"a-model"},{"id":"another"}]}"#)
            }
            return .json(
                #"{"model":"a-model","choices":[{"message":{"content":"{\"ok\":\"ok\"}"},"finish_reason":"stop"}]}"#
            )
        }

        let probe = await catalogue(stub).probe(account(), with: secret)

        guard case .answered(_, let model, let dialect, let models) = probe else {
            Issue.record("A service that answers is an answer")
            return
        }
        #expect(model == "a-model")
        #expect(dialect == .strictSchema)
        #expect(models == 2)
    }

    @Test("A test against a refused key says so and asks nothing further")
    func aRefusedKeyStopsTheTest() async {
        let stub = StubServer(host: Self.host)
        defer { stub.reset() }
        stub.install { _ in .json("{}", status: 401) }

        #expect(await catalogue(stub).probe(account(), with: secret) == .trouble(.keyRefused))
        // The list refused it, so the paid round trip is never made.
        #expect(stub.requests.count == 1)
    }

    /// What makes it honest to offer a test before any consent has been given.
    @Test("The test sends a fixed sentence and nothing of the reader's")
    func theTestSendsNothingOfTheirs() async throws {
        let stub = StubServer(host: Self.host)
        defer { stub.reset() }
        stub.install { request in
            guard request.path.hasSuffix("chat/completions") else { return .json(#"{"data":[]}"#) }
            return .json(#"{"choices":[{"message":{"content":"{\"ok\":\"ok\"}"},"finish_reason":"stop"}]}"#)
        }

        _ = await catalogue(stub).probe(account(), with: secret)

        let sent = try #require(stub.requests.last?.body)
        #expect(sent.contains("Answer with ok."))
        #expect(!sent.contains("headline"))
    }

    /// A model server on the reader's own network is the one configuration that
    /// sends nothing to anybody, and the system will not carry a plain request
    /// to a public host.
    @Test("A plain address on a public host is refused before it is sent")
    func plainHTTPGoesNowherePublic() {
        #expect(!LocalNetwork.allowsPlainHTTP(URL(string: "http://api.example.com/v1")!))
        #expect(LocalNetwork.allowsPlainHTTP(URL(string: "http://192.168.1.20:11434/v1")!))
        #expect(LocalNetwork.allowsPlainHTTP(URL(string: "http://localhost:1234/v1")!))
        #expect(LocalNetwork.allowsPlainHTTP(URL(string: "http://my-mac.local:1234/v1")!))
        #expect(LocalNetwork.allowsPlainHTTP(URL(string: "https://api.example.com/v1")!))
    }

    @Test("Every private range is one, and a public address is not")
    func theRangesAreRight() {
        for host in ["10.0.0.1", "172.16.3.4", "172.31.255.255", "192.168.0.1", "127.0.0.1", "169.254.1.1"] {
            #expect(LocalNetwork.isPrivate(host), "\(host) is on the reader's own network")
        }
        for host in ["8.8.8.8", "172.32.0.1", "192.169.0.1", "api.openai.com", "1.2.3"] {
            #expect(!LocalNetwork.isPrivate(host), "\(host) is not")
        }
    }

    /// A failure about one story is ordinary and is what the fallback exists
    /// for. A row that complained about it would be complaining about the news.
    @Test("Only a failure of the model itself is worth telling the reader about")
    func onlyTheModelIsWorthReporting() {
        #expect(ProviderTrouble(.declined) == nil)
        #expect(ProviderTrouble(.tooLong) == nil)
        #expect(ProviderTrouble(.unusable(.cancelled)) == nil)
        #expect(ProviderTrouble(.unusable(.notEntitled)) == .keyRefused)
        #expect(ProviderTrouble(.unusable(.unreachable)) == .unreachable)
        #expect(ProviderTrouble(.busy(retryAfter: nil)) == .busy)
    }
}

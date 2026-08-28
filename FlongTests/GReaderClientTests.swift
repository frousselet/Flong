//
//  GReaderClientTests.swift
//  FlongTests
//
//  Created by François Rousselet on 28/08/2026.
//
//  This Source Code Form is subject to the terms of the Mozilla Public
//  License, v. 2.0. If a copy of the MPL was not distributed with this
//  file, You can obtain one at https://mozilla.org/MPL/2.0/.
//

import Foundation
import Testing

@testable import Flong

@Suite("GReader HTTP client", .serialized)
struct GReaderClientTests {
    private let server = StubServer(host: "client.rss.example.com")

    private func makeClient(authToken: String? = nil, baseURL: URL? = nil) -> GReaderClient {
        GReaderClient(baseURL: baseURL ?? server.url, session: server.makeSession(), authToken: authToken)
    }

    private static let loginBody = """
        SID=alice/0123456789abcdef
        LSID=null
        Auth=alice/0123456789abcdef
        """

    // MARK: - Sign in

    @Test("ClientLogin posts the credentials and keeps the Auth line")
    func clientLoginSucceeds() async throws {
        server.install { _ in .text(Self.loginBody) }
        defer { server.reset() }

        let client = makeClient()
        let token = try await client.clientLogin(email: "alice", password: "s3cret")

        #expect(token == "alice/0123456789abcdef")
        #expect(await client.currentAuthToken == token)

        let request = try #require(server.requests.first)
        #expect(request.method == "POST")
        #expect(request.path == "/api/greader.php/accounts/ClientLogin")
        #expect(request.formValue("Email") == "alice")
        #expect(request.formValue("Passwd") == "s3cret")
    }

    /// The server answers 401 on a wrong password and 400 on an unknown user.
    @Test("A refused sign in is reported as bad credentials", arguments: [400, 401, 403])
    func clientLoginRejected(status: Int) async {
        server.install { _ in .text("", status: status) }
        defer { server.reset() }

        await #expect(throws: GReaderError.badCredentials) {
            try await makeClient().clientLogin(email: "alice", password: "wrong")
        }
    }

    @Test("A reply without an Auth line is refused")
    func clientLoginWithoutToken() async {
        server.install { _ in .text("SID=alice/1\nLSID=null") }
        defer { server.reset() }

        await #expect(throws: GReaderError.missingAuthToken) {
            try await makeClient().clientLogin(email: "alice", password: "s3cret")
        }
    }

    // MARK: - Authenticated requests

    @Test("Requests carry the GoogleLogin authorization header")
    func authorizationHeader() async throws {
        server.install { _ in .json("{}") }
        defer { server.reset() }

        _ = try await makeClient(authToken: "alice/abc").getData("reader/api/0/user-info")

        let request = try #require(server.requests.first)
        #expect(request.headers["Authorization"] == "GoogleLogin auth=alice/abc")
    }

    @Test("A request made without a token never reaches the network")
    func requestWithoutToken() async {
        server.install { _ in .json("{}") }
        defer { server.reset() }

        await #expect(throws: GReaderError.notAuthenticated) {
            try await makeClient().getData("reader/api/0/user-info")
        }
        #expect(server.requests.isEmpty)
    }

    @Test("A rejected session is reported as such", arguments: [401, 403])
    func rejectedSession(status: Int) async {
        server.install { _ in .json("", status: status) }
        defer { server.reset() }

        await #expect(throws: GReaderError.notAuthenticated) {
            try await makeClient(authToken: "alice/abc").getData("reader/api/0/user-info")
        }
    }

    @Test("Any other failure keeps its status code")
    func serverFailure() async {
        server.install { _ in .json("boom", status: 500) }
        defer { server.reset() }

        await #expect(throws: GReaderError.http(status: 500, body: "boom")) {
            try await makeClient(authToken: "alice/abc").getData("reader/api/0/user-info")
        }
    }

    @Test("Malformed JSON is reported as a decoding failure")
    func malformedJSON() async {
        server.install { _ in .json("{ nope") }
        defer { server.reset() }

        await #expect(throws: GReaderError.self) {
            try await makeClient(authToken: "alice/abc")
                .get("reader/api/0/tag/list", as: GReaderDTO.TagList.self)
        }
    }

    // MARK: - Modification token

    /// The token endpoint answers with a trailing newline, which must not travel
    /// into the form body.
    @Test("The modification token is trimmed and attached to writes")
    func modificationToken() async throws {
        server.install { request in
            request.path.hasSuffix("/token") ? .text("abcdefZZZZ\n") : .text("OK")
        }
        defer { server.reset() }

        let client = makeClient(authToken: "alice/abc")
        _ = try await client.post("reader/api/0/edit-tag", form: [("i", "1")])

        let write = try #require(server.requests.last)
        #expect(write.formValue("T") == "abcdefZZZZ")
    }

    @Test("The modification token is fetched once and reused")
    func modificationTokenReuse() async throws {
        server.install { request in
            request.path.hasSuffix("/token") ? .text("abcdef\n") : .text("OK")
        }
        defer { server.reset() }

        let client = makeClient(authToken: "alice/abc")
        _ = try await client.post("reader/api/0/edit-tag", form: [("i", "1")])
        _ = try await client.post("reader/api/0/edit-tag", form: [("i", "2")])

        let tokenCalls = server.requests.filter { $0.path.hasSuffix("/token") }
        #expect(tokenCalls.count == 1)
    }

    @Test("An empty modification token is refused")
    func emptyModificationToken() async {
        server.install { request in
            request.path.hasSuffix("/token") ? .text("  \n") : .text("OK")
        }
        defer { server.reset() }

        await #expect(throws: GReaderError.missingAuthToken) {
            try await makeClient(authToken: "alice/abc").post("reader/api/0/edit-tag", form: [("i", "1")])
        }
    }

    // MARK: - URL building

    @Test("A trailing slash on the server URL does not double up")
    func trailingSlashInBaseURL() async throws {
        server.install { _ in .json("{}") }
        defer { server.reset() }

        let client = makeClient(authToken: "alice/abc", baseURL: URL(string: "\(server.url.absoluteString)/")!)
        _ = try await client.getData("reader/api/0/user-info")

        let request = try #require(server.requests.first)
        #expect(request.url.absoluteString == "\(server.url.absoluteString)/api/greader.php/reader/api/0/user-info")
    }

    @Test("A form value is escaped so it cannot be read as a separator")
    func formEncoding() {
        let encoded = GReaderClient.formEncoded([("s", "user/-/label/A&B"), ("ts", "1")])
        #expect(String(decoding: encoded, as: UTF8.self) == "s=user%2F-%2Flabel%2FA%26B&ts=1")
    }
}

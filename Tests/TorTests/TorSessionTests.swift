//
//  TorSessionTests.swift
//  swift-tor
//
//  Copyright (c) 2025 21 Development Innovations LLC
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation
import Testing
@testable import Tor

@Suite("TorSession Protocol")
struct TorSessionTests {

    @Test("TorClient conforms to TorSession")
    func torClientConformsToTorSession() {
        // Compile-time check: if this builds, TorClient: TorSession holds.
        let _: any TorSession = TorClient(configuration: .ephemeral())
    }

    @Test("TorSession.waitUntilBootstrapped() default uses 120s timeout")
    func defaultTimeoutIsReasonable() {
        // Purely compile-time: exercise the default-parameter extension.
        let session: any TorSession = TorClient(configuration: .ephemeral())
        let _: () async throws -> Void = session.waitUntilBootstrapped
    }
}

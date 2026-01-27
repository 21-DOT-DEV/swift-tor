//
//  ControlProtocolParserTests.swift
//  21-DOT-DEV/swift-tor
//
//  Copyright (c) 2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Testing
@testable import Tor

// MARK: - Reply Parsing Tests

@Suite("Control Reply Parsing Tests")
struct ControlReplyParsingTests {
    
    @Test("parses single-line 250 OK")
    func testSingleLineOK() throws {
        let reply = try ControlProtocolParser.parseSingleLine("250 OK")
        
        #expect(reply.statusCode == 250)
        #expect(reply.isSuccess)
        #expect(!reply.isError)
        #expect(reply.lines == ["OK"])
        #expect(reply.message == "OK")
        #expect(reply.data == nil)
    }
    
    @Test("parses single-line error response")
    func testSingleLineError() throws {
        let reply = try ControlProtocolParser.parseSingleLine("515 Bad authentication")
        
        #expect(reply.statusCode == 515)
        #expect(!reply.isSuccess)
        #expect(reply.isError)
        #expect(reply.message == "Bad authentication")
    }
    
    @Test("parses multi-line continuation response")
    func testMultiLineContinuation() throws {
        let lines = [
            "250-ServiceID=abc123def456",
            "250-PrivateKey=ED25519-V3:secretkey",
            "250 OK"
        ]
        let reply = try ControlProtocolParser.parseReply(lines)
        
        #expect(reply.statusCode == 250)
        #expect(reply.isSuccess)
        #expect(reply.lines.count == 3)
        #expect(reply.lines[0] == "ServiceID=abc123def456")
        #expect(reply.lines[1] == "PrivateKey=ED25519-V3:secretkey")
        #expect(reply.lines[2] == "OK")
    }
    
    @Test("parses data block with dot termination")
    func testDataBlock() throws {
        let lines = [
            "250+info/names=",
            "version -- Tor version",
            "config-file -- Config file path",
            ".",
            "250 OK"
        ]
        let reply = try ControlProtocolParser.parseReply(lines)
        
        #expect(reply.statusCode == 250)
        #expect(reply.isSuccess)
        #expect(reply.data != nil)
        #expect(reply.data!.contains("version -- Tor version"))
        #expect(reply.data!.contains("config-file -- Config file path"))
    }
    
    @Test("handles dot-stuffing in data blocks")
    func testDotStuffing() throws {
        let lines = [
            "250+data=",
            "normal line",
            "..line starting with dot",
            ".",
            "250 OK"
        ]
        let reply = try ControlProtocolParser.parseReply(lines)
        
        #expect(reply.data != nil)
        #expect(reply.data!.contains(".line starting with dot"))
    }
    
    @Test("extracts key-value pairs from reply lines")
    func testKeyValuePairs() throws {
        let lines = [
            "250-ServiceID=myonion123",
            "250-PrivateKey=ED25519-V3:base64key",
            "250 OK"
        ]
        let reply = try ControlProtocolParser.parseReply(lines)
        let kv = reply.keyValuePairs
        
        #expect(kv["ServiceID"] == "myonion123")
        #expect(kv["PrivateKey"] == "ED25519-V3:base64key")
    }
    
    @Test("throws on empty reply")
    func testEmptyReplyThrows() {
        #expect(throws: TorError.self) {
            try ControlProtocolParser.parseReply([])
        }
    }
    
    @Test("throws on invalid status code")
    func testInvalidStatusCodeThrows() {
        #expect(throws: TorError.self) {
            try ControlProtocolParser.parseSingleLine("ABC Invalid")
        }
    }
    
    @Test("throws on line too short")
    func testLineTooShortThrows() {
        #expect(throws: TorError.self) {
            try ControlProtocolParser.parseSingleLine("25")
        }
    }
}

// MARK: - Bootstrap Status Parsing Tests

@Suite("Bootstrap Status Parsing Tests")
struct BootstrapStatusParsingTests {
    
    @Test("parses bootstrap starting status")
    func testBootstrapStarting() {
        let line = "BOOTSTRAP PROGRESS=0 TAG=starting SUMMARY=\"Starting\""
        let status = ControlProtocolParser.parseBootstrapStatus(line)
        
        #expect(status != nil)
        #expect(status?.progress == 0)
        #expect(status?.tag == "starting")
        #expect(status?.summary == "Starting")
        #expect(!status!.isComplete)
    }
    
    @Test("parses bootstrap done status")
    func testBootstrapDone() {
        let line = "BOOTSTRAP PROGRESS=100 TAG=done SUMMARY=\"Done\""
        let status = ControlProtocolParser.parseBootstrapStatus(line)
        
        #expect(status != nil)
        #expect(status?.progress == 100)
        #expect(status?.tag == "done")
        #expect(status?.summary == "Done")
        #expect(status!.isComplete)
    }
    
    @Test("parses bootstrap with descriptors")
    func testBootstrapDescriptors() {
        let line = "BOOTSTRAP PROGRESS=50 TAG=loading_descriptors SUMMARY=\"Loading relay descriptors\""
        let status = ControlProtocolParser.parseBootstrapStatus(line)
        
        #expect(status != nil)
        #expect(status?.progress == 50)
        #expect(status?.tag == "loading_descriptors")
        #expect(status?.summary == "Loading relay descriptors")
    }
    
    @Test("parses bootstrap with warning")
    func testBootstrapWithWarning() {
        let line = "BOOTSTRAP PROGRESS=5 TAG=conn SUMMARY=\"Connecting\" WARNING=\"Resource temporarily unavailable\" REASON=TIMEOUT"
        let status = ControlProtocolParser.parseBootstrapStatus(line)
        
        #expect(status != nil)
        #expect(status?.progress == 5)
        #expect(status?.warning == "Resource temporarily unavailable")
        #expect(status?.reason == "TIMEOUT")
    }
    
    @Test("returns nil for non-bootstrap line")
    func testNonBootstrapLine() {
        let line = "CIRCUIT 5 BUILT"
        let status = ControlProtocolParser.parseBootstrapStatus(line)
        
        #expect(status == nil)
    }
    
    @Test("handles STATUS_CLIENT bootstrap event")
    func testStatusClientBootstrap() {
        let line = "STATUS_CLIENT NOTICE BOOTSTRAP PROGRESS=75 TAG=ap_conn SUMMARY=\"Connecting to a relay to build circuits\""
        let status = ControlProtocolParser.parseBootstrapStatus(line)
        
        #expect(status != nil)
        #expect(status?.progress == 75)
        #expect(status?.tag == "ap_conn")
    }
}

// MARK: - Attribute Parsing Tests

@Suite("Attribute Parsing Tests")
struct AttributeParsingTests {
    
    @Test("parses simple key=value pairs")
    func testSimpleKeyValue() {
        let attributes = ControlProtocolParser.parseAttributes("KEY1=value1 KEY2=value2")
        
        #expect(attributes["KEY1"] == "value1")
        #expect(attributes["KEY2"] == "value2")
    }
    
    @Test("parses quoted values")
    func testQuotedValues() {
        let attributes = ControlProtocolParser.parseAttributes("SUMMARY=\"Hello World\" TAG=test")
        
        #expect(attributes["SUMMARY"] == "Hello World")
        #expect(attributes["TAG"] == "test")
    }
    
    @Test("parses escaped quotes in values")
    func testEscapedQuotes() {
        let attributes = ControlProtocolParser.parseAttributes("MSG=\"Say \\\"hello\\\"\"")
        
        #expect(attributes["MSG"] == "Say \"hello\"")
    }
    
    @Test("handles values with equals signs")
    func testValuesWithEquals() {
        let attributes = ControlProtocolParser.parseAttributes("KEY=value=with=equals")
        
        #expect(attributes["KEY"] == "value=with=equals")
    }
}

// MARK: - ADD_ONION Response Parsing Tests

@Suite("ADD_ONION Response Parsing Tests")
struct AddOnionResponseParsingTests {
    
    @Test("parses ADD_ONION response with key")
    func testAddOnionWithKey() throws {
        let lines = [
            "250-ServiceID=duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad",
            "250-PrivateKey=ED25519-V3:base64privatekey==",
            "250 OK"
        ]
        let response = try ControlProtocolParser.parseAddOnionResponse(lines)
        
        #expect(response.serviceID == "duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad")
        #expect(response.privateKey == "ED25519-V3:base64privatekey==")
    }
    
    @Test("parses ADD_ONION response with DiscardPK")
    func testAddOnionWithDiscardPK() throws {
        let lines = [
            "250-ServiceID=xyz123abc456def789",
            "250 OK"
        ]
        let response = try ControlProtocolParser.parseAddOnionResponse(lines)
        
        #expect(response.serviceID == "xyz123abc456def789")
        #expect(response.privateKey == nil)
    }
    
    @Test("throws on ADD_ONION error response")
    func testAddOnionError() {
        let lines = [
            "552 Unrecognized key type"
        ]
        
        #expect(throws: TorError.self) {
            try ControlProtocolParser.parseAddOnionResponse(lines)
        }
    }
    
    @Test("throws on missing ServiceID")
    func testMissingServiceID() {
        let lines = [
            "250-SomeOtherKey=value",
            "250 OK"
        ]
        
        #expect(throws: TorError.self) {
            try ControlProtocolParser.parseAddOnionResponse(lines)
        }
    }
}

// MARK: - GETINFO Response Parsing Tests

@Suite("GETINFO Response Parsing Tests")
struct GetInfoResponseParsingTests {
    
    @Test("parses GETINFO response")
    func testGetInfoResponse() throws {
        let lines = [
            "250-version=0.4.8.21",
            "250-config-file=/etc/tor/torrc",
            "250 OK"
        ]
        let reply = try ControlProtocolParser.parseReply(lines)
        let info = try ControlProtocolParser.parseGetInfoResponse(reply)
        
        #expect(info["version"] == "0.4.8.21")
        #expect(info["config-file"] == "/etc/tor/torrc")
    }
    
    @Test("throws on GETINFO error")
    func testGetInfoError() throws {
        let lines = [
            "552 Unrecognized key \"invalid-key\""
        ]
        let reply = try ControlProtocolParser.parseReply(lines)
        
        #expect(throws: TorError.self) {
            try ControlProtocolParser.parseGetInfoResponse(reply)
        }
    }
}

// MARK: - Async Event Parsing Tests

@Suite("Async Event Parsing Tests")
struct AsyncEventParsingTests {
    
    @Test("parses STATUS_CLIENT event")
    func testStatusClientEvent() {
        let line = "650 STATUS_CLIENT NOTICE BOOTSTRAP PROGRESS=50 TAG=loading_descriptors"
        let event = ControlProtocolParser.parseAsyncEvent(line)
        
        #expect(event != nil)
        #expect(event?.event == .statusClient)
        #expect(event?.attributes["PROGRESS"] == "50")
    }
    
    @Test("parses CIRC event")
    func testCircuitEvent() {
        let line = "650 CIRC 5 BUILT"
        let event = ControlProtocolParser.parseAsyncEvent(line)
        
        #expect(event != nil)
        #expect(event?.event == .circuitStatus)
        #expect(event?.data.contains("5") == true)
    }
    
    @Test("returns nil for non-event line")
    func testNonEventLine() {
        let line = "250 OK"
        let event = ControlProtocolParser.parseAsyncEvent(line)
        
        #expect(event == nil)
    }
}

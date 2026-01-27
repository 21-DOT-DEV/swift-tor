//
//  ControlProtocolParser.swift
//  21-DOT-DEV/swift-tor
//
//  Copyright (c) 2026 Timechain Software Initiative, Inc.
//  Distributed under the MIT software license
//
//  See the accompanying file LICENSE for information
//

import Foundation

/// Represents a parsed control protocol reply.
public struct ControlReply: Sendable, Equatable {
    /// The status code (e.g., 250 for success, 5xx for errors).
    public let statusCode: Int
    
    /// The reply lines (without status code prefixes).
    public let lines: [String]
    
    /// Data block content, if present (from 250+ replies).
    public let data: String?
    
    /// Whether this is a success reply (2xx status code).
    public var isSuccess: Bool {
        (200..<300).contains(statusCode)
    }
    
    /// Whether this is an error reply (4xx or 5xx status code).
    public var isError: Bool {
        statusCode >= 400
    }
    
    /// The first line of the reply, often containing the main message.
    public var message: String {
        lines.first ?? ""
    }
    
    /// Parses key-value pairs from reply lines.
    /// Lines in format "KEY=VALUE" are extracted.
    public var keyValuePairs: [String: String] {
        var result: [String: String] = [:]
        for line in lines {
            if let equalIndex = line.firstIndex(of: "=") {
                let key = String(line[..<equalIndex])
                let value = String(line[line.index(after: equalIndex)...])
                result[key] = value
            }
        }
        return result
    }
    
    public init(statusCode: Int, lines: [String], data: String? = nil) {
        self.statusCode = statusCode
        self.lines = lines
        self.data = data
    }
}

/// Parser for the Tor control protocol.
///
/// The Tor control protocol uses line-based communication with the following reply formats:
/// - Single-line: `250 OK\r\n`
/// - Multi-line with continuation: `250-line1\r\n250-line2\r\n250 OK\r\n`
/// - Data block: `250+data=\r\ndata line 1\r\ndata line 2\r\n.\r\n250 OK\r\n`
///
/// See: https://spec.torproject.org/control-spec/
public enum ControlProtocolParser {
    
    /// Parses a complete control protocol reply from raw lines.
    /// - Parameter rawLines: Array of raw lines (including status codes).
    /// - Returns: A parsed `ControlReply`.
    /// - Throws: `TorError.invalidResponse` if the reply is malformed.
    public static func parseReply(_ rawLines: [String]) throws -> ControlReply {
        guard !rawLines.isEmpty else {
            throw TorError.invalidResponse("Empty reply")
        }
        
        var lines: [String] = []
        var data: String? = nil
        var statusCode: Int? = nil
        var inDataBlock = false
        var dataLines: [String] = []
        
        for rawLine in rawLines {
            if inDataBlock {
                if rawLine == "." {
                    inDataBlock = false
                    data = dataLines.joined(separator: "\n")
                } else {
                    // Handle dot-stuffing: lines starting with "." have it removed
                    let line = rawLine.hasPrefix(".") ? String(rawLine.dropFirst()) : rawLine
                    dataLines.append(line)
                }
                continue
            }
            
            guard rawLine.count >= 3 else {
                throw TorError.invalidResponse("Line too short: \(rawLine)")
            }
            
            let codeStr = String(rawLine.prefix(3))
            guard let code = Int(codeStr) else {
                throw TorError.invalidResponse("Invalid status code: \(codeStr)")
            }
            
            if statusCode == nil {
                statusCode = code
            }
            
            let separatorIndex = rawLine.index(rawLine.startIndex, offsetBy: 3)
            let separator = rawLine.count > 3 ? rawLine[separatorIndex] : " "
            let content = rawLine.count > 4 ? String(rawLine[rawLine.index(after: separatorIndex)...]) : ""
            
            switch separator {
            case "-":
                // Continuation line
                lines.append(content)
            case "+":
                // Data block follows
                lines.append(content)
                inDataBlock = true
                dataLines = []
            case " ":
                // Final line
                lines.append(content)
            default:
                throw TorError.invalidResponse("Invalid separator: \(separator)")
            }
        }
        
        guard let finalCode = statusCode else {
            throw TorError.invalidResponse("No status code found")
        }
        
        return ControlReply(statusCode: finalCode, lines: lines, data: data)
    }
    
    /// Parses a single-line reply.
    /// - Parameter line: A single reply line (e.g., "250 OK").
    /// - Returns: A parsed `ControlReply`.
    public static func parseSingleLine(_ line: String) throws -> ControlReply {
        try parseReply([line])
    }
}

// MARK: - Bootstrap Parsing

/// Represents parsed bootstrap status information.
public struct BootstrapStatus: Sendable, Equatable {
    /// Progress percentage (0-100).
    public let progress: Int
    
    /// Machine-readable phase tag (e.g., "done", "loading_descriptors").
    public let tag: String
    
    /// Human-readable summary.
    public let summary: String
    
    /// Warning message, if any.
    public let warning: String?
    
    /// Reason for warning, if any.
    public let reason: String?
    
    /// Whether bootstrap is complete.
    public var isComplete: Bool {
        progress >= 100
    }
    
    public init(progress: Int, tag: String, summary: String, warning: String? = nil, reason: String? = nil) {
        self.progress = progress
        self.tag = tag
        self.summary = summary
        self.warning = warning
        self.reason = reason
    }
}

extension ControlProtocolParser {
    
    /// Parses bootstrap status from a GETINFO status/bootstrap-phase response or STATUS_CLIENT event.
    ///
    /// Format: `BOOTSTRAP PROGRESS=X TAG=tag SUMMARY="summary"`
    ///
    /// - Parameter line: The status line to parse.
    /// - Returns: Parsed bootstrap status, or nil if not a bootstrap status line.
    public static func parseBootstrapStatus(_ line: String) -> BootstrapStatus? {
        guard line.contains("BOOTSTRAP") else {
            return nil
        }
        
        let attributes = parseAttributes(line)
        
        guard let progressStr = attributes["PROGRESS"],
              let progress = Int(progressStr),
              let tag = attributes["TAG"] else {
            return nil
        }
        
        let summary = attributes["SUMMARY"] ?? ""
        let warning = attributes["WARNING"]
        let reason = attributes["REASON"]
        
        return BootstrapStatus(
            progress: progress,
            tag: tag,
            summary: summary,
            warning: warning,
            reason: reason
        )
    }
    
    /// Parses key=value and key="quoted value" attributes from a line.
    /// - Parameter line: The line to parse.
    /// - Returns: Dictionary of attribute key-value pairs.
    public static func parseAttributes(_ line: String) -> [String: String] {
        var result: [String: String] = [:]
        
        // Use a regex-like approach: find all KEY=VALUE or KEY="VALUE" patterns
        var index = line.startIndex
        
        while index < line.endIndex {
            // Skip whitespace
            while index < line.endIndex && line[index].isWhitespace {
                index = line.index(after: index)
            }
            
            guard index < line.endIndex else { break }
            
            // Find the next '=' to locate a key
            var keyEnd = index
            while keyEnd < line.endIndex && line[keyEnd] != "=" && line[keyEnd] != " " {
                keyEnd = line.index(after: keyEnd)
            }
            
            // If we hit a space before '=', this is a plain word - skip it
            if keyEnd >= line.endIndex || line[keyEnd] == " " {
                index = keyEnd
                continue
            }
            
            // We found '=', extract the key
            let key = String(line[index..<keyEnd])
            index = line.index(after: keyEnd) // Move past '='
            
            guard index < line.endIndex else { break }
            
            // Parse value (quoted or unquoted)
            let value: String
            if line[index] == "\"" {
                // Quoted value
                index = line.index(after: index) // Move past opening quote
                var valueEnd = index
                var escaped = false
                
                while valueEnd < line.endIndex {
                    let char = line[valueEnd]
                    if escaped {
                        escaped = false
                    } else if char == "\\" {
                        escaped = true
                    } else if char == "\"" {
                        break
                    }
                    valueEnd = line.index(after: valueEnd)
                }
                
                value = String(line[index..<valueEnd])
                    .replacingOccurrences(of: "\\\"", with: "\"")
                    .replacingOccurrences(of: "\\\\", with: "\\")
                
                // Move past closing quote
                if valueEnd < line.endIndex {
                    index = line.index(after: valueEnd)
                } else {
                    index = valueEnd
                }
            } else {
                // Unquoted value (ends at space or end of string)
                var valueEnd = index
                while valueEnd < line.endIndex && !line[valueEnd].isWhitespace {
                    valueEnd = line.index(after: valueEnd)
                }
                value = String(line[index..<valueEnd])
                index = valueEnd
            }
            
            result[key] = value
        }
        
        return result
    }
}

// MARK: - ADD_ONION Response Parsing

/// Represents a parsed ADD_ONION response.
public struct AddOnionResponse: Sendable, Equatable {
    /// The service ID (without .onion suffix).
    public let serviceID: String
    
    /// The private key, if returned.
    public let privateKey: String?
    
    public init(serviceID: String, privateKey: String? = nil) {
        self.serviceID = serviceID
        self.privateKey = privateKey
    }
}

extension ControlProtocolParser {
    
    /// Parses an ADD_ONION response.
    ///
    /// Format:
    /// ```
    /// 250-ServiceID=<onion_address_without_.onion>
    /// 250-PrivateKey=<key_type>:<key_blob>  (optional, if not DiscardPK)
    /// 250 OK
    /// ```
    ///
    /// - Parameter reply: The control reply to parse.
    /// - Returns: Parsed ADD_ONION response.
    /// - Throws: `TorError` if the response is invalid.
    public static func parseAddOnionResponse(_ reply: ControlReply) throws -> AddOnionResponse {
        guard reply.isSuccess else {
            throw TorError.controlProtocolError(
                code: reply.statusCode,
                message: reply.message
            )
        }
        
        let kv = reply.keyValuePairs
        
        guard let serviceID = kv["ServiceID"] else {
            throw TorError.invalidResponse("ADD_ONION response missing ServiceID")
        }
        
        let privateKey = kv["PrivateKey"]
        
        return AddOnionResponse(serviceID: serviceID, privateKey: privateKey)
    }
    
    /// Parses an ADD_ONION response from raw reply lines.
    /// - Parameter rawLines: The raw reply lines.
    /// - Returns: Parsed ADD_ONION response.
    public static func parseAddOnionResponse(_ rawLines: [String]) throws -> AddOnionResponse {
        let reply = try parseReply(rawLines)
        return try parseAddOnionResponse(reply)
    }
}

// MARK: - GETINFO Response Parsing

extension ControlProtocolParser {
    
    /// Parses a GETINFO response into a dictionary.
    ///
    /// Format:
    /// ```
    /// 250-key1=value1
    /// 250-key2=value2
    /// 250 OK
    /// ```
    ///
    /// - Parameter reply: The control reply to parse.
    /// - Returns: Dictionary of info key-value pairs.
    public static func parseGetInfoResponse(_ reply: ControlReply) throws -> [String: String] {
        guard reply.isSuccess else {
            throw TorError.controlProtocolError(
                code: reply.statusCode,
                message: reply.message
            )
        }
        
        return reply.keyValuePairs
    }
}

// MARK: - Async Event Parsing

extension ControlProtocolParser {
    
    /// Parses an async event line (650 prefix).
    ///
    /// Format: `650 EVENT_TYPE [arguments...]`
    ///
    /// - Parameter line: The event line to parse.
    /// - Returns: Parsed event message, or nil if not an event line.
    public static func parseAsyncEvent(_ line: String) -> TorControlEventMessage? {
        guard line.hasPrefix("650") else {
            return nil
        }
        
        let content = line.dropFirst(4) // Drop "650 " or "650-"
        guard !content.isEmpty else {
            return nil
        }
        
        // Find the event type (first word)
        let parts = content.split(separator: " ", maxSplits: 1)
        guard let eventTypeStr = parts.first else {
            return nil
        }
        
        let eventType = String(eventTypeStr)
        let data = parts.count > 1 ? String(parts[1]) : ""
        
        // Try to match to known event type
        guard let event = TorControlEvent(rawValue: eventType) else {
            // Unknown event type, still parse it
            return TorControlEventMessage(
                event: .statusGeneral,
                data: String(content),
                attributes: parseAttributes(data)
            )
        }
        
        return TorControlEventMessage(
            event: event,
            data: data,
            attributes: parseAttributes(data)
        )
    }
}

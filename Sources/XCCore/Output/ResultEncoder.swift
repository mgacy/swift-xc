//
//  ResultEncoder.swift
//  XCCore
//
//  Created by Mathew Gacy on 9/6/26.
//  Copyright © 2026 Mathew Gacy. All rights reserved.
//

import Foundation

public struct ResultEncodingError: Error, Sendable {
    public let underlyingError: any Error
}

public enum ResultEncoder {
    /// Encodes the final bytes shared by the artifact and output stream.
    ///
    /// ```swift
    /// let bytes = try ResultEncoder.encode(document)
    /// try bytes.write(to: resultURL, options: .atomic)
    /// ```
    /// - Parameter document: The versioned result to serialize.
    /// - Returns: Sorted, pretty-printed UTF-8 JSON with unescaped slashes, ISO-8601 dates, and
    ///   one trailing newline.
    /// - Throws: `ResultEncodingError` when the document cannot be encoded.
    public static func encode(_ document: ProbeResultDocument.V1) throws(ResultEncodingError) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        do {
            var bytes = try encoder.encode(document)
            bytes.append(0x0A)
            return bytes
        } catch {
            throw ResultEncodingError(underlyingError: error)
        }
    }
}

//
//  RunIdentifier.swift
//  XCCore
//
//  Created by Mathew Gacy on 9/6/26.
//  Copyright © 2026 Mathew Gacy. All rights reserved.
//

import Foundation

public struct RunIdentifier: Sendable, Equatable, Hashable {
    public let rawValue: String

    /// Creates a UTC timestamp followed by 48 random bits encoded as hexadecimal.
    ///
    /// - Parameter date: The instant represented by the timestamp.
    public init(date: Date = Date()) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let suffix = (0..<6).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max)) }.joined()
        rawValue = formatter.string(from: date) + "-" + suffix
    }
}

//
//  StorageProbeReport.swift
//  XCCore
//
//  Created by Mathew Gacy on 9/6/26.
//  Copyright © 2026 Mathew Gacy. All rights reserved.
//

import Foundation

public struct ProbeOperation: Sendable, Equatable {
    public enum Kind: String, Sendable {
        case resolve
        case createDirectory
        case write
        case read
        case verify
        case removeStub
        case removeDirectory
    }

    public let kind: Kind
    public let path: String?
    public let succeeded: Bool
    public let byteCount: Int?
    public let duration: Duration
    public let failure: OperationFailure?
}

/// Error evidence without an inferred cause.
public struct OperationFailure: Sendable, Equatable {
    public let message: String
    public let domain: String
    public let code: Int

    public init(_ error: NSError) {
        message = error.localizedDescription
        domain = error.domain
        code = error.code
    }
}

public struct LocationProbe: Sendable, Equatable {
    public let role: StorageRole
    public let path: String?
    public let completed: Bool
    public let preexisting: Bool
    public let operations: [ProbeOperation]
}

public struct StorageProbeReport: Sendable {
    public let runID: RunIdentifier
    public let workspace: WorkspaceIdentity?
    public let toolVersion: String
    public let startedAt: Date
    public let duration: Duration
    public let locations: [LocationProbe]
    public let artifactPath: URL?
    public let artifactWrite: ProbeOperation?
}

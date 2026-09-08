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

    /// What an attempted action established.
    public enum Outcome: Sendable, Equatable {
        /// The action's postcondition holds.
        case satisfied
        /// The postcondition does not hold, and no defect in the storage is attributed: a cleanup
        /// removal refused because the directory is not empty.
        case declined
        /// The action failed, and the failure is evidence of a storage defect.
        case failed(OperationFailure)
    }

    public let kind: Kind
    public let path: String?
    public let outcome: Outcome
    public let byteCount: Int?
    public let duration: Duration
    /// Whether a path the action touched was already in the state the action would have produced,
    /// or already held contents the action did not create.
    ///
    /// Only directory creation and removal record this, and it can describe a path earlier in the
    /// action than the one a failure stopped on.
    public let contended: Bool

    /// Whether the action's postcondition holds.
    public var succeeded: Bool { outcome == .satisfied }

    /// The failure the action raised, when it failed.
    public var failure: OperationFailure? {
        if case .failed(let failure) = outcome { failure } else { nil }
    }

    /// Whether the operation is evidence of a storage defect.
    ///
    /// A declined action leaves its postcondition unmet without attributing a failure, so an
    /// operation can be evidence of no defect without having succeeded.
    public var faulted: Bool { failure != nil }

    public init(kind: Kind, path: String?, outcome: Outcome, byteCount: Int?, duration: Duration, contended: Bool) {
        self.kind = kind
        self.path = path
        self.outcome = outcome
        self.byteCount = byteCount
        self.duration = duration
        self.contended = contended
    }
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
    public let preexisting: Bool
    public let operations: [ProbeOperation]

    /// Whether the location was probed with no operation attributing a failure.
    ///
    /// A declined operation leaves its postcondition unmet without attributing a failure, so a
    /// location can complete holding an operation that did not succeed.
    public var completed: Bool { !operations.contains(where: \.faulted) }
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

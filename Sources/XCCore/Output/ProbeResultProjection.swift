//
//  ProbeResultProjection.swift
//  XCCore
//
//  Created by Mathew Gacy on 9/6/26.
//  Copyright © 2026 Mathew Gacy. All rights reserved.
//

import Foundation

/// Projects probe evidence into a V1 document for JSON serialization.
public enum ProbeResultProjection {
    /// Projects storage evidence, including any artifact write failure.
    ///
    /// - Parameter report: The completed probe evidence and run metadata.
    /// - Returns: A V1 document. Retention assumes the pending artifact write succeeds when a path
    ///   exists.
    public static func project(_ report: StorageProbeReport) -> ProbeResultDocument.V1 {
        let failed = report.locations.contains { !$0.completed } || report.artifactWrite?.faulted == true
        return ProbeResultDocument.V1(
            schemaVersion: 1,
            toolVersion: report.toolVersion,
            outcome: failed ? .infrastructureError : .passed,
            reason: nil,
            run: .init(id: report.runID.rawValue, startedAt: report.startedAt, durationMS: milliseconds(report.duration)),
            workspace: report.workspace.map {
                .init(
                    id: $0.id,
                    worktreeRoot: $0.worktreeRoot.path,
                    repositoryRoot: $0.repositoryRoot?.path,
                    resolution: resolution($0.resolution)
                )
            },
            artifacts: .init(
                result: report.artifactPath?.path,
                retained: report.artifactPath != nil && report.artifactWrite?.faulted != true,
                write: report.artifactWrite.map(operation)
            ),
            storage: .init(
                locations: report.locations.map {
                    .init(
                        role: $0.role.rawValue,
                        path: $0.path,
                        completed: $0.completed,
                        preexisting: $0.preexisting,
                        operations: $0.operations.map(operation)
                    )
                }
            )
        )
    }

    /// Projects a usage failure without run or filesystem claims.
    ///
    /// - Parameters:
    ///   - reason: The parser's explanation, preserved verbatim.
    ///   - toolVersion: The emitting executable's version.
    /// - Returns: A configuration-error document with no storage operations.
    public static func configurationError(reason: String, toolVersion: String) -> ProbeResultDocument.V1 {
        .init(
            schemaVersion: 1,
            toolVersion: toolVersion,
            outcome: .configurationError,
            reason: reason,
            run: nil,
            workspace: nil,
            artifacts: nil,
            storage: nil
        )
    }

    /// Projects a completed storage operation.
    ///
    /// - Parameter operation: The completed storage operation.
    /// - Returns: Wire evidence with milliseconds and explicit operation spelling.
    private static func operation(_ operation: ProbeOperation) -> ProbeResultDocument.Operation {
        .init(
            kind: kind(operation.kind),
            path: operation.path,
            succeeded: operation.succeeded,
            byteCount: operation.byteCount,
            durationMS: milliseconds(operation.duration),
            error: operation.failure.map { .init(message: $0.message, domain: $0.domain, code: $0.code) },
            contended: operation.contended ? true : nil
        )
    }

    /// Returns the V1 spelling for a probe operation kind.
    ///
    /// - Parameter kind: The probe operation kind.
    /// - Returns: The V1 kind spelling.
    private static func kind(_ kind: ProbeOperation.Kind) -> String {
        switch kind {
        case .resolve: "resolve"
        case .createDirectory: "create_directory"
        case .write: "write"
        case .read: "read"
        case .verify: "verify"
        case .removeStub: "remove_stub"
        case .removeDirectory: "remove_created_directories"
        }
    }

    /// Returns the V1 resolution spelling for a workspace identity.
    ///
    /// - Parameter resolution: The workspace identity resolution.
    /// - Returns: The V1 resolution spelling.
    private static func resolution(_ resolution: WorkspaceIdentity.Resolution) -> String {
        switch resolution {
        case .gitWorktree: "git_worktree"
        case .gitLinkedWorktree: "git_linked_worktree"
        case .gitBareLinkedWorktree: "git_bare_linked_worktree"
        case .packageRoot: "package_root"
        case .workingDirectory: "working_directory"
        }
    }

    /// Returns the elapsed milliseconds for a duration, preserving fractional milliseconds.
    ///
    /// - Parameter duration: The duration to convert to milliseconds.
    /// - Returns: Elapsed milliseconds, preserving fractional milliseconds.
    private static func milliseconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1_000_000_000_000_000
    }
}

//
//  RunSession.swift
//  XCCore
//
//  Created by Mathew Gacy on 9/6/26.
//  Copyright © 2026 Mathew Gacy. All rights reserved.
//

import Foundation

public struct RunSession: Sendable {
    public struct Output: Sendable {
        /// The newline-terminated document, identical to the artifact when retention succeeds.
        public let bytes: Data
        public let outcome: RunOutcome
    }

    private let toolVersion: String
    private let workingDirectory: URL
    private let caches: Result<URL, StorageResolutionError>?
    private let applicationSupport: Result<URL, StorageResolutionError>?

    /// Creates a run session with injected roots for testing, or nil to resolve the user-domain
    /// Foundation directories.
    ///
    /// - Parameters:
    ///   - toolVersion: The version recorded in the document.
    ///   - workingDirectory: The directory from which workspace discovery begins.
    ///   - caches: An injected cache root or failure; nil resolves the user-domain Foundation
    ///     directory.
    ///   - applicationSupport: An injected support root or failure; nil resolves the user-domain
    ///     Foundation directory.
    public init(
        toolVersion: String,
        workingDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        caches: Result<URL, StorageResolutionError>? = nil,
        applicationSupport: Result<URL, StorageResolutionError>? = nil
    ) {
        self.toolVersion = toolVersion
        self.workingDirectory = workingDirectory
        self.caches = caches
        self.applicationSupport = applicationSupport
    }

    /// Probes storage and atomically retains its result when the artifact path is resolved.
    ///
    /// ```swift
    /// let output = try RunSession(toolVersion: "1.0.0").run()
    /// try FileHandle.standardOutput.write(contentsOf: output.bytes)
    /// ```
    ///
    /// - Parameter runIdentifier: A unique identifier for this invocation's artifact directory.
    /// - Returns: Final bytes and their outcome, including contained filesystem failures.
    /// - Throws: `ResultEncodingError` if the initial or artifact-failure document cannot be
    ///   encoded.
    public func run(runIdentifier: RunIdentifier = RunIdentifier()) throws(ResultEncodingError) -> Output {
        let startedAt = Date()
        let start = ContinuousClock.now
        let workspace = resolveWorkspace()
        let layout = StorageLayout(caches: caches ?? StorageLayout.resolveRoot(.cachesDirectory),
            applicationSupport: applicationSupport ?? StorageLayout.resolveRoot(.applicationSupportDirectory),
            workspace: workspace, runIdentifier: runIdentifier)
        let locations = StorageProbe(layout: layout).run()
        let artifactPath = layout.locations.first { $0.role == .userCacheRun }.flatMap {
            try? $0.resolution.get().directory.appendingPathComponent("result.json")
        }
        let report = StorageProbeReport(runID: runIdentifier, workspace: try? workspace.get(),
            toolVersion: toolVersion, startedAt: startedAt, duration: start.duration(to: .now),
            locations: locations, artifactPath: artifactPath, artifactWrite: nil)
        let document = ProbeResultProjection.project(report)
        let bytes = try ResultEncoder.encode(document)
        guard let artifactPath else { return Output(bytes: bytes, outcome: document.outcome) }
        guard let failure = writeArtifact(bytes, to: artifactPath) else {
            return Output(bytes: bytes, outcome: document.outcome)
        }
        let failedReport = StorageProbeReport(runID: report.runID, workspace: report.workspace,
            toolVersion: report.toolVersion, startedAt: report.startedAt, duration: start.duration(to: .now),
            locations: report.locations, artifactPath: artifactPath, artifactWrite: failure)
        let failedDocument = ProbeResultProjection.project(failedReport)
        return Output(bytes: try ResultEncoder.encode(failedDocument), outcome: failedDocument.outcome)
    }

    /// Returns the workspace identity or its original resolution failure.
    private func resolveWorkspace() -> Result<WorkspaceIdentity, WorkspaceResolutionError> {
        do {
            return .success(try WorkspaceResolver.resolve(workingDirectory: workingDirectory))
        } catch {
            return .failure(error)
        }
    }

    /// Writes the artifact document atomically, returning a failure operation if the write fails.
    ///
    /// - Parameters:
    ///   - bytes: The complete newline-terminated document.
    ///   - path: The destination file.
    /// - Returns: Failed write evidence, or nil when the atomic write succeeds.
    private func writeArtifact(_ bytes: Data, to path: URL) -> ProbeOperation? {
        let start = ContinuousClock.now
        do {
            try bytes.write(to: path, options: .atomic)
            return nil
        } catch {
            return ProbeOperation(kind: .write, path: path.path, succeeded: false, byteCount: nil,
                duration: start.duration(to: .now), failure: OperationFailure(error as NSError))
        }
    }
}

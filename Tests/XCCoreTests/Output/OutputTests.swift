//
//  OutputTests.swift
//  XCCoreTests
//
//  Created by Mathew Gacy on 9/6/26.
//  Copyright © 2026 Mathew Gacy. All rights reserved.
//

import Foundation
import Testing
@testable import XCCore

@Suite("Output")
struct OutputTests {
    @Test("Only reachable outcomes map to process status", arguments: [
        (RunOutcome.passed, "passed", Int32(0)),
        (.infrastructureError, "infrastructure_error", Int32(1)),
        (.configurationError, "configuration_error", Int32(1))
    ])
    func outcomes(outcome: RunOutcome, spelling: String, code: Int32) {
        #expect(outcome.rawValue == spelling)
        #expect(outcome.exitCode == code)
    }

    @Test("Every failed operation including cleanup yields infrastructure error", arguments: [
        ProbeOperation.Kind.resolve, .createDirectory, .write, .read, .verify, .removeStub, .removeDirectory
    ])
    func operationFailure(kind: ProbeOperation.Kind) {
        let document = ProbeResultProjection.project(report(operations: [operation(kind: kind, succeeded: false)]))
        #expect(document.outcome == .infrastructureError)
    }

    @Test("Successful storage evidence passes and preserves byte counts")
    func success() {
        let document = ProbeResultProjection.project(report(operations: [operation(kind: .write, succeeded: true)]))
        #expect(document.outcome == .passed)
        #expect(document.artifacts?.retained == true)
        #expect(document.storage?.locations.first?.operations.first?.byteCount == 32)
    }

    @Test("Artifact failure is retained as evidence and clears retention")
    func artifactFailure() {
        let failed = operation(kind: .write, succeeded: false)
        let document = ProbeResultProjection.project(report(operations: [], artifactWrite: failed))
        #expect(document.outcome == .infrastructureError)
        #expect(document.artifacts?.retained == false)
        #expect(document.artifacts?.write?.error?.code == 513)
    }

    @Test("Configuration failures carry the parser reason without storage claims")
    func configuration() throws {
        let document = ProbeResultProjection.configurationError(reason: "Unknown option '--bad'", toolVersion: "0.0.1")
        let bytes = try ResultEncoder.encode(document)
        let object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        #expect(document.outcome == .configurationError)
        #expect(object["reason"] as? String == "Unknown option '--bad'")
        #expect(object["storage"] == nil)
        #expect(object["run"] == nil)
        #expect(object["artifacts"] == nil)
        #expect(object["workspace"] == nil)
        #expect(object["tests"] == nil)
    }

    @Test("Unresolved roots never invent workspace or artifact paths")
    func unresolved() {
        let original = report(operations: [operation(kind: .resolve, succeeded: false)])
        let unresolved = StorageProbeReport(
            runID: original.runID, workspace: nil, toolVersion: original.toolVersion,
            startedAt: original.startedAt, duration: original.duration, locations: original.locations,
            artifactPath: nil, artifactWrite: nil
        )
        let document = ProbeResultProjection.project(unresolved)
        #expect(document.workspace == nil)
        #expect(document.artifacts?.result == nil)
        #expect(document.artifacts?.retained == false)
        #expect(document.outcome == .infrastructureError)
    }

    @Test("Projection matches V1 golden bytes and independent schema")
    func golden() throws {
        let source = report(operations: [operation(kind: .createDirectory, succeeded: false)])
        let bytes = try ResultEncoder.encode(ProbeResultProjection.project(source))
        let text = try #require(String(data: bytes, encoding: .utf8))
            .replacingOccurrences(of: source.runID.rawValue, with: "20260907T024233Z-3f91c04a2b6d")
        let url = try #require(Bundle.module.url(forResource: "probe-result-v1", withExtension: "json"))
        let golden = try Data(contentsOf: url)
        #expect(Data(text.utf8) == golden)
        #expect(text.hasSuffix("\n"))
        #expect(!text.hasSuffix("\n\n"))
        #expect(!text.contains("\\/"))
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let checked = try decoder.decode(CheckingDocument.self, from: golden)
        #expect(checked.schemaVersion == 1)
        #expect(checked.run.startedAt == "2026-09-07T02:42:33Z")
        #expect(checked.storage.locations[0].operations[0].error.domain == "NSCocoaErrorDomain")
        let object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        #expect(object["tests"] == nil)
    }

    @Test("Encoding failures retain the underlying error at a typed boundary")
    func encodingFailure() {
        let document = ProbeResultDocument.V1(
            schemaVersion: 1, toolVersion: "0.0.1", outcome: .passed, reason: nil,
            run: .init(id: "example", startedAt: Date(), durationMS: .infinity),
            workspace: nil, artifacts: nil, storage: nil
        )
        do {
            _ = try ResultEncoder.encode(document)
            Issue.record("Non-finite JSON duration must fail encoding")
        } catch {
            #expect(error.underlyingError is EncodingError)
        }
    }

    @Test("Operation spellings are explicit V1 values", arguments: [
        (ProbeOperation.Kind.resolve, "resolve"), (.createDirectory, "create_directory"),
        (.write, "write"), (.read, "read"), (.verify, "verify"),
        (.removeStub, "remove_stub"), (.removeDirectory, "remove_created_directories")
    ])
    func operationSpelling(kind: ProbeOperation.Kind, expected: String) {
        let document = ProbeResultProjection.project(report(operations: [operation(kind: kind, succeeded: true)]))
        #expect(document.storage?.locations.first?.operations.first?.kind == expected)
    }

    @Test("Workspace resolution uses V1 spelling", arguments: [
        (WorkspaceIdentity.Resolution.gitWorktree, "git_worktree"),
        (.gitLinkedWorktree, "git_linked_worktree"), (.packageRoot, "package_root"),
        (.workingDirectory, "working_directory")
    ])
    func resolutionSpelling(resolution: WorkspaceIdentity.Resolution, expected: String) {
        let source = report(operations: [])
        let workspace = WorkspaceIdentity(worktreeRoot: URL(fileURLWithPath: "/fixture/project"),
                                          repositoryRoot: nil, resolution: resolution)
        let report = StorageProbeReport(runID: source.runID, workspace: workspace, toolVersion: source.toolVersion,
                                        startedAt: source.startedAt, duration: source.duration, locations: [],
                                        artifactPath: nil, artifactWrite: nil)
        let document = ProbeResultProjection.project(report)
        #expect(document.workspace?.resolution == expected)
        #expect(document.workspace?.repositoryRoot == nil)
    }

    private func operation(kind: ProbeOperation.Kind, succeeded: Bool) -> ProbeOperation {
        ProbeOperation(
            kind: kind, path: "/fixture/support/xc/simulator-pools", succeeded: succeeded,
            byteCount: kind == .write ? 32 : nil, duration: .milliseconds(1),
            failure: succeeded ? nil : OperationFailure(NSError(
                domain: NSCocoaErrorDomain, code: 513,
                userInfo: [NSLocalizedDescriptionKey: "Permission denied."]
            ))
        )
    }

    private func report(operations: [ProbeOperation], artifactWrite: ProbeOperation? = nil) -> StorageProbeReport {
        StorageProbeReport(
            runID: RunIdentifier(),
            workspace: WorkspaceIdentity(
                worktreeRoot: URL(fileURLWithPath: "/fixture/project"),
                repositoryRoot: URL(fileURLWithPath: "/fixture/project"), resolution: .gitWorktree
            ),
            toolVersion: "0.0.1", startedAt: Date(timeIntervalSince1970: 1788748953),
            duration: .milliseconds(12),
            locations: [LocationProbe(
                role: .applicationSupport, path: "/fixture/support/xc/simulator-pools",
                completed: operations.allSatisfy(\.succeeded), preexisting: false, operations: operations
            )],
            artifactPath: URL(fileURLWithPath: "/fixture/cache/result.json"), artifactWrite: artifactWrite
        )
    }
}

private struct CheckingDocument: Decodable {
    let schemaVersion: Int
    let toolVersion: String
    let outcome: String
    let run: Run
    let storage: Storage
    let artifacts: Artifacts
    let workspace: Workspace

    struct Artifacts: Decodable {
        let result: String
        let retained: Bool
    }

    struct Workspace: Decodable {
        let id: String
        let worktreeRoot: String
        let repositoryRoot: String
        let resolution: String
    }

    struct Run: Decodable {
        let id: String
        let startedAt: String
        let durationMs: Double
    }

    struct Storage: Decodable {
        let locations: [Location]
    }

    struct Location: Decodable {
        let role: String
        let path: String
        let completed: Bool
        let preexisting: Bool
        let operations: [Operation]
    }

    struct Operation: Decodable {
        let kind: String
        let path: String
        let succeeded: Bool
        let durationMs: Double
        let error: Failure
    }

    struct Failure: Decodable {
        let message: String
        let domain: String
        let code: Int
    }
}

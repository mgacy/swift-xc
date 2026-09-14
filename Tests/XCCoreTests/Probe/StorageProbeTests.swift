//
//  StorageProbeTests.swift
//  XCCoreTests
//
//  Created by Mathew Gacy on 9/6/26.
//  Copyright © 2026 Mathew Gacy. All rights reserved.
//

import Darwin
import Foundation
import Testing
@testable import XCCore

@Suite("Probe")
struct StorageProbeTests {
    @Test("Round trips 32 bytes at every location, retaining long-lived tool storage and removing disposable directories")
    func roundTrip() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let layout = try layout(root)
        let reports = StorageProbe(layout: layout).run()
        #expect(reports.count == 6)
        for report in reports {
            #expect(report.completed)
            #expect(!report.preexisting)
            #expect(report.operations.prefix(6).map(\.kind) == [.resolve, .createDirectory, .write, .read, .verify, .removeStub])
            #expect(report.operations.allSatisfy { $0.succeeded && $0.duration >= .zero })
            #expect(report.operations.filter { [.write, .read, .verify].contains($0.kind) }.map(\.byteCount) == [32, 32, 32])
            let path = try #require(report.path)
            #expect(FileManager.default.fileExists(atPath: path) == !report.role.removesCreatedDirectories)
        }
        let run = try layout.locations[0].resolution.get().directory
        #expect(try FileManager.default.contentsOfDirectory(atPath: run.path).isEmpty)
        #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("support").path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".build").path))
    }

    @Test("A directory created between the scan and the attempt is treated as satisfied, not owned")
    func creationCollision() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let probe = StorageProbe(layout: try layout(root))
        let target = root.appendingPathComponent("a/b/c")
        let missing = probe.missingAncestors(of: target)
        let raced = root.appendingPathComponent("a")
        try FileManager.default.createDirectory(at: raced, withIntermediateDirectories: false)
        var created: [URL] = []
        let contended = try probe.createDirectories(target, missing: missing, created: &created)
        #expect(contended)
        #expect(!created.map(\.path).contains(raced.path))
        #expect(created.map(\.path) == [root.appendingPathComponent("a/b").path, target.path])
        #expect(FileManager.default.fileExists(atPath: target.path))
    }

    @Test("A file blocking a scanned path is still a genuine failure, not swallowed as contention")
    func creationBlockedByFile() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let probe = StorageProbe(layout: try layout(root))
        let target = root.appendingPathComponent("a/b/c")
        let missing = probe.missingAncestors(of: target)
        let blocked = root.appendingPathComponent("a")
        try Data().write(to: blocked)
        var created: [URL] = []
        let failure = #expect(throws: StorageProbe.DirectoryCreationFailure.self) {
            try probe.createDirectories(target, missing: missing, created: &created)
        }
        #expect(failure?.path.path == blocked.path)
        #expect(created.isEmpty)
    }

    @Test("A file already blocking an ancestor is named itself, not the child that cannot be created inside it")
    func creationBlockedByPreexistingFile() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let probe = StorageProbe(layout: try layout(root))
        let blocked = root.appendingPathComponent("a")
        try Data().write(to: blocked)
        let target = root.appendingPathComponent("a/b/c")
        var created: [URL] = []
        let failure = #expect(throws: StorageProbe.DirectoryCreationFailure.self) {
            try probe.createDirectories(target, missing: probe.missingAncestors(of: target), created: &created)
        }
        #expect(failure?.path.path == blocked.path)
        #expect(failure?.underlyingError.code == Int(ENOTDIR))
        #expect(created.isEmpty)
    }

    @Test("An ancestor symbolic link to a directory is not a blocker, since creation through it succeeds")
    func creationThroughPreexistingSymbolicLink() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let probe = StorageProbe(layout: try layout(root))
        let elsewhere = root.appendingPathComponent("elsewhere")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("a"), withDestinationURL: elsewhere)
        let target = root.appendingPathComponent("a/b/c")
        var created: [URL] = []
        let contended = try probe.createDirectories(target, missing: probe.missingAncestors(of: target), created: &created)
        #expect(!contended)
        #expect(created.map(\.path) == [root.appendingPathComponent("a/b").path, target.path])
        var operations: [ProbeOperation] = []
        probe.cleanup(created, operations: &operations)
        #expect(try FileManager.default.contentsOfDirectory(atPath: elsewhere.path).isEmpty)
    }

    @Test("A directory removed after an empty scan is recreated as owned rather than left behind")
    func emptyScanRecreation() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let probe = StorageProbe(layout: try layout(root))
        let target = root.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        let missing = probe.missingAncestors(of: target)
        #expect(missing.isEmpty)
        try FileManager.default.removeItem(at: target)
        var created: [URL] = []
        let contended = try probe.createDirectories(target, missing: missing, created: &created)
        #expect(contended)
        #expect(created.map(\.path) == [target.path])
        var operations: [ProbeOperation] = []
        probe.cleanup(created, operations: &operations)
        #expect(!FileManager.default.fileExists(atPath: target.path))
    }

    @Test("A directory still present at an empty scan's attempt is neither claimed nor reported as contention")
    func emptyScanRetention() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let probe = StorageProbe(layout: try layout(root))
        let target = root.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        var created: [URL] = []
        let contended = try probe.createDirectories(target, missing: probe.missingAncestors(of: target), created: &created)
        #expect(!contended)
        #expect(created.isEmpty)
        #expect(FileManager.default.fileExists(atPath: target.path))
    }

    @Test("Preserves preexisting directories and their files")
    func preexisting() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let layout = try layout(root)
        let directory = try layout.locations[5].resolution.get().directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let foreign = directory.appendingPathComponent("foreign")
        try Data([1, 2, 3]).write(to: foreign)
        let report = StorageProbe(layout: layout).run()[5]
        #expect(report.preexisting && report.completed)
        #expect(try Data(contentsOf: foreign) == Data([1, 2, 3]))
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["foreign"])
        #expect(!report.operations.contains { $0.kind == .removeDirectory })
    }

    @Test("Permission failure stops dependent operations and continues independent locations", .enabled(if: geteuid() != 0))
    func permissionFailure() throws {
        let root = try temporaryDirectory()
        let support = root.appendingPathComponent("support")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: support.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: support.path)
            try? FileManager.default.removeItem(at: root)
        }
        let reports = StorageProbe(layout: try layout(root)).run()
        let failed = reports[3]
        #expect(!failed.completed)
        #expect(failed.operations.map(\.kind) == [.resolve, .createDirectory])
        #expect(failed.operations.last?.path == support.appendingPathComponent("xc").path)
        let failure = try #require(failed.operations.last?.failure)
        #expect(failure.domain == NSCocoaErrorDomain)
        #expect(failure.code == NSFileWriteNoPermissionError)
        #expect(!failure.message.isEmpty)
        #expect(reports.enumerated().filter { $0.offset != 3 }.allSatisfy { $0.element.completed })
    }

    @Test("Unresolved roots retain original error evidence and do not invent operations")
    func resolutionFailure() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let error = NSError(domain: "original.domain", code: 41, userInfo: [NSLocalizedDescriptionKey: "Original message"])
        let layout = StorageLayout(caches: .failure(StorageResolutionError(path: nil, underlyingError: error)),
            applicationSupport: .success(root.appendingPathComponent("support")),
            workspace: .success(try WorkspaceResolver.resolve(workingDirectory: root)), runIdentifier: RunIdentifier())
        let reports = StorageProbe(layout: layout).run()
        for report in reports.prefix(3) {
            #expect(report.path == nil && !report.completed)
            #expect(report.operations.count == 1)
            #expect(report.operations[0].kind == .resolve)
            #expect(report.operations[0].path == nil)
            #expect(report.operations[0].failure == OperationFailure(error))
        }
        #expect(reports.suffix(3).allSatisfy { $0.completed })
    }

    @Test("A symbolic link at a scanned path is a genuine failure, not swallowed as contention")
    func creationBlockedBySymbolicLink() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let probe = StorageProbe(layout: try layout(root))
        let target = root.appendingPathComponent("a/b/c")
        let missing = probe.missingAncestors(of: target)
        let elsewhere = root.appendingPathComponent("elsewhere")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("a"), withDestinationURL: elsewhere)
        var created: [URL] = []
        let failure = #expect(throws: StorageProbe.DirectoryCreationFailure.self) {
            try probe.createDirectories(target, missing: missing, created: &created)
        }
        #expect(failure?.path.path == root.appendingPathComponent("a").path)
        #expect(created.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: elsewhere.path).isEmpty)
    }

    @Test("A failed creation carries the contention it observed into its evidence")
    func failedOperationCarriesContention() {
        let failure = StorageProbe.DirectoryCreationFailure(
            path: URL(fileURLWithPath: "/fixture/a/b"),
            underlyingError: NSError(domain: NSCocoaErrorDomain, code: 513),
            contended: true
        )
        let operation = StorageProbe.failedOperation(
            .createDirectory, path: URL(fileURLWithPath: "/fixture/a"), error: failure, duration: .zero
        )
        #expect(operation.path == "/fixture/a/b")
        #expect(!operation.succeeded)
        #expect(operation.contended)
        #expect(operation.faulted)
        #expect(operation.failure?.code == 513)
    }

    @Test("Contention recorded before a genuine failure is preserved on the failure", .enabled(if: geteuid() != 0))
    func creationFailureAfterContention() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let probe = StorageProbe(layout: try layout(root))
        let target = root.appendingPathComponent("a/b/c")
        let missing = probe.missingAncestors(of: target)
        let raced = root.appendingPathComponent("a")
        try FileManager.default.createDirectory(at: raced, withIntermediateDirectories: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: raced.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: raced.path) }
        var created: [URL] = []
        let failure = #expect(throws: StorageProbe.DirectoryCreationFailure.self) {
            try probe.createDirectories(target, missing: missing, created: &created)
        }
        #expect(failure?.contended == true)
        #expect(failure?.path.path == root.appendingPathComponent("a/b").path)
        #expect(created.isEmpty)
    }

    @Test("Cleanup records a non-empty directory as contention rather than failure, and preserves foreign contents")
    func cleanupFailure() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let occupied = root.appendingPathComponent("occupied")
        let empty = root.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: occupied, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: false)
        let foreign = occupied.appendingPathComponent("foreign")
        try Data([4, 5]).write(to: foreign)
        var operations: [ProbeOperation] = []
        StorageProbe(layout: try layout(root)).cleanup([empty, occupied], operations: &operations)
        #expect(operations.map(\.kind) == [.removeDirectory, .removeDirectory])
        #expect(operations.map(\.outcome) == [.declined, .satisfied])
        #expect(operations.allSatisfy { !$0.faulted })
        #expect(operations[0].contended)
        #expect(operations[0].failure == nil)
        #expect(!operations[1].contended)
        #expect(FileManager.default.fileExists(atPath: occupied.path))
        #expect(try Data(contentsOf: foreign) == Data([4, 5]))
        #expect(!FileManager.default.fileExists(atPath: empty.path))
    }

    @Test("A directory already gone satisfies its removal rather than failing the run")
    func cleanupAlreadyRemoved() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        var operations: [ProbeOperation] = []
        StorageProbe(layout: try layout(root)).cleanup([root.appendingPathComponent("gone")], operations: &operations)
        #expect(operations.map(\.outcome) == [.satisfied])
        #expect(operations[0].contended)
        #expect(!operations[0].faulted)
    }

    @Test("A removal refused for a reason other than contents is a failure")
    func cleanupDeniedRemoval() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path) }
        defer { try? FileManager.default.removeItem(at: root) }
        let locked = root.appendingPathComponent("locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: false)
        let probe = StorageProbe(layout: try layout(root))
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)
        var operations: [ProbeOperation] = []
        probe.cleanup([locked], operations: &operations)
        #expect(!operations[0].succeeded)
        #expect(operations[0].faulted)
        #expect(operations[0].failure?.domain == NSPOSIXErrorDomain)
    }

    @Test("A failed write preserves the existing directory and omits dependent operations", .enabled(if: geteuid() != 0))
    func writeFailure() throws {
        let root = try temporaryDirectory()
        let layout = try layout(root)
        let directory = try layout.locations[5].resolution.get().directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: root)
        }
        let report = StorageProbe(layout: layout).run()[5]
        #expect(report.preexisting && !report.completed)
        #expect(report.operations.map(\.kind) == [.resolve, .createDirectory, .write])
        #expect(report.operations.last?.failure?.code == NSFileWriteNoPermissionError)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    /// - Returns: A layout with all roots confined to the fixture.
    /// - Throws: A workspace resolution error if the fixture is unavailable.
    private func layout(_ root: URL) throws -> StorageLayout {
        StorageLayout(caches: root.appendingPathComponent("cache"), applicationSupport: root.appendingPathComponent("support"),
            workspace: try WorkspaceResolver.resolve(workingDirectory: root), runIdentifier: RunIdentifier())
    }

    /// - Returns: An empty directory owned by this test.
    /// - Throws: A Foundation error if creation fails.
    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

// MARK: - Concurrency

extension StorageProbeTests {
    @Test("Concurrent runs from distinct worktrees never fail on a cold, shared cache and Application Support root")
    func crossWorktreeConcurrency() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let caches = root.appendingPathComponent("caches")
        let support = root.appendingPathComponent("support")
        let probes = try (0..<8).map { index -> StorageProbe in
            let worktree = root.appendingPathComponent("worktree-\(index)")
            try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
            let workspace = try WorkspaceResolver.resolve(workingDirectory: worktree)
            return StorageProbe(layout: StorageLayout(caches: caches, applicationSupport: support,
                workspace: workspace, runIdentifier: RunIdentifier()))
        }
        let reports = await runConcurrently(probes)
        #expect(reports.count == 8)
        for report in reports {
            #expect(report.allSatisfy { $0.completed })
            #expect(report.flatMap(\.operations).allSatisfy { $0.succeeded })
        }
    }

    @Test("Concurrent runs in one worktree never fail on cold, shared user-cache paths")
    func sameWorktreeToolStorageConcurrency() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = try WorkspaceResolver.resolve(workingDirectory: root)
        let caches = root.appendingPathComponent("caches")
        let support = root.appendingPathComponent("support")
        // Pre-create the worktree-local roles so no run owns them. Two runs in one worktree
        // resolve .build/xc-probe and .deriveddata to the same path, where one run's sweep can
        // remove a directory the other is probing; that case needs a lock rather than tolerance,
        // so this test isolates the shared tool-storage paths instead.
        for role in StorageRole.allCases where role.removesCreatedDirectories {
            let directory = role.directory(root: workspace.worktreeRoot, workspaceID: workspace.id,
                                           runIdentifier: RunIdentifier())
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let probes = (0..<8).map { _ in
            StorageProbe(layout: StorageLayout(caches: caches, applicationSupport: support,
                workspace: workspace, runIdentifier: RunIdentifier()))
        }
        let reports = await runConcurrently(probes)
        #expect(reports.count == 8)
        for report in reports {
            let catalog = try #require(report.first { $0.role == .userCacheCatalog })
            let locks = try #require(report.first { $0.role == .userCacheLocks })
            #expect(catalog.completed && catalog.operations.allSatisfy { $0.succeeded })
            #expect(locks.completed && locks.operations.allSatisfy { $0.succeeded })
        }
    }

    /// - Parameter probes: The probes to run at the same time.
    /// - Returns: Each probe's evidence, in completion order.
    private func runConcurrently(_ probes: [StorageProbe]) async -> [[LocationProbe]] {
        await withTaskGroup(of: [LocationProbe].self) { group in
            for probe in probes {
                group.addTask { probe.run() }
            }
            var reports: [[LocationProbe]] = []
            for await report in group { reports.append(report) }
            return reports
        }
    }
}

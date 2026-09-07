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
    @Test("Round trips 32 bytes at every location and removes disposable directories")
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
            #expect(FileManager.default.fileExists(atPath: path) == (report.role == .userCacheRun))
        }
        let run = try layout.locations[0].resolution.get().directory
        #expect(try FileManager.default.contentsOfDirectory(atPath: run.path).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("support").path))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(".build").path))
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

    @Test("Cleanup preserves foreign contents and continues after a refused removal")
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
        #expect(operations.map(\.succeeded) == [false, true])
        #expect(operations[0].failure?.domain == NSPOSIXErrorDomain)
        #expect(operations[0].failure?.code == Int(ENOTEMPTY))
        #expect(try Data(contentsOf: foreign) == Data([4, 5]))
        #expect(!FileManager.default.fileExists(atPath: empty.path))
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

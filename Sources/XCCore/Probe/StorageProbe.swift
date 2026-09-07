//
//  StorageProbe.swift
//  XCCore
//
//  Created by Mathew Gacy on 9/6/26.
//  Copyright © 2026 Mathew Gacy. All rights reserved.
//

import Darwin
import Foundation

public struct StorageProbe: Sendable {
    private struct DirectoryCreationFailure: Error {
        let path: URL
        let underlyingError: NSError
    }

    private let layout: StorageLayout

    public init(layout: StorageLayout) {
        self.layout = layout
    }

    /// Exercises every location and cleans up owned stubs and empty disposable directories.
    /// The run directory and its ancestors remain available for artifact retention.
    /// - Returns: Ordered evidence for every location, including failures and cleanup attempts.
    public func run() -> [LocationProbe] {
        layout.locations.map { probe($0) }
    }

    /// - Returns: The attempted operations for one location, including applicable cleanup.
    private func probe(_ location: StorageLayout.Location) -> LocationProbe {
        let start = ContinuousClock.now
        switch location.resolution {
        case .failure(let error):
            return LocationProbe(role: location.role, path: nil, completed: false, preexisting: false,
                operations: [ProbeOperation(kind: .resolve, path: error.path?.path, succeeded: false,
                    byteCount: nil, duration: start.duration(to: .now), failure: OperationFailure(error.underlyingError))])
        case .success(let resolved):
            var operations = [ProbeOperation(kind: .resolve, path: resolved.root.path, succeeded: true,
                byteCount: nil, duration: start.duration(to: .now), failure: nil)]
            let preexisting = FileManager.default.fileExists(atPath: resolved.directory.path)
            var created: [URL] = []
            let ready = record(.createDirectory, path: resolved.directory, operations: &operations) {
                try createDirectories(resolved.directory, created: &created)
                return nil
            }
            if ready {
                roundTrip(in: resolved.directory, operations: &operations)
            }
            if location.role != .userCacheRun || !ready {
                cleanup(created, operations: &operations)
            }
            return LocationProbe(role: location.role, path: resolved.directory.path,
                completed: operations.allSatisfy(\.succeeded), preexisting: preexisting, operations: operations)
        }
    }

    /// Removes owned directories deepest-first and records failures without stopping cleanup.
    /// - Parameters:
    ///   - created: Owned directories in parent-before-child creation order.
    ///   - operations: Evidence to append for every attempted removal.
    internal func cleanup(_ created: [URL], operations: inout [ProbeOperation]) {
        for directory in created.reversed() {
            record(.removeDirectory, path: directory, operations: &operations) {
                try removeEmptyDirectory(directory)
                return nil
            }
        }
    }

    private func roundTrip(in directory: URL, operations: inout [ProbeOperation]) {
        let stub = directory.appendingPathComponent("xc-probe-\(UUID().uuidString)")
        var generator = SystemRandomNumberGenerator()
        let expected = Data((0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
        let written = record(.write, path: stub, operations: &operations) {
            try expected.write(to: stub, options: .withoutOverwriting)
            return expected.count
        }
        // A failed write can leave a partially written file that still needs removal.
        let collision = operations.last?.failure.map { $0.domain == NSCocoaErrorDomain && $0.code == NSFileWriteFileExistsError } ?? false
        let ownsStub = written || (!collision && FileManager.default.fileExists(atPath: stub.path))
        defer {
            if ownsStub {
                record(.removeStub, path: stub, operations: &operations) {
                    try FileManager.default.removeItem(at: stub)
                    return nil
                }
            }
        }
        guard written else { return }
        var actual = Data()
        guard record(.read, path: stub, operations: &operations, action: {
            actual = try Data(contentsOf: stub)
            return actual.count
        }) else { return }
        record(.verify, path: stub, operations: &operations) {
            guard actual == expected else {
                throw NSError(domain: "XCCore.StorageProbe", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Read-back bytes differ from the written bytes."])
            }
            return actual.count
        }
    }

    /// Creates missing parents one at a time; only successful creations become owned.
    /// - Throws: The Foundation failure for the first directory that cannot be created.
    private func createDirectories(_ directory: URL, created: inout [URL]) throws(DirectoryCreationFailure) {
        var missing: [URL] = []
        var current = directory
        while !FileManager.default.fileExists(atPath: current.path) && current.path != "/" {
            missing.append(current)
            current.deleteLastPathComponent()
        }
        var attempted = directory
        do {
            if missing.isEmpty {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            for candidate in missing.reversed() {
                attempted = candidate
                try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: false)
                created.append(candidate)
            }
        } catch {
            throw DirectoryCreationFailure(path: attempted, underlyingError: error as NSError)
        }
    }

    /// Removes a directory only when it is empty, including at the instant of removal.
    /// - Throws: The POSIX failure if removal is refused.
    private func removeEmptyDirectory(_ directory: URL) throws(NSError) {
        guard directory.path.withCString({ Darwin.rmdir($0) }) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }

    /// - Returns: Whether the operation succeeded, after appending its evidence.
    @discardableResult
    private func record(_ kind: ProbeOperation.Kind, path: URL, operations: inout [ProbeOperation],
                        action: () throws -> Int?) -> Bool {
        let start = ContinuousClock.now
        do {
            let bytes = try action()
            operations.append(ProbeOperation(kind: kind, path: path.path, succeeded: true, byteCount: bytes,
                duration: start.duration(to: .now), failure: nil))
            return true
        } catch {
            let creation = error as? DirectoryCreationFailure
            operations.append(ProbeOperation(kind: kind, path: (creation?.path ?? path).path, succeeded: false, byteCount: nil,
                duration: start.duration(to: .now), failure: OperationFailure(creation?.underlyingError ?? error as NSError)))
            return false
        }
    }
}

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
    internal struct DirectoryCreationFailure: Error {
        let path: URL
        let underlyingError: NSError
        /// Whether a competing process created one of the earlier directories first.
        let contended: Bool
    }

    /// How an attempted removal left a directory.
    private enum Removal {
        /// The directory was removed.
        case removed
        /// The directory was already gone.
        case absent
        /// The directory holds contents, so it was left in place.
        case refused
    }

    /// What an action reports when it completes without throwing.
    private struct ActionResult {
        /// Bytes transferred, when the action moves data.
        var byteCount: Int?
        /// Whether the action's postcondition holds.
        var satisfied = true
        /// Whether a competing process interfered with the action.
        var contended = false
    }

    private let layout: StorageLayout

    public init(layout: StorageLayout) {
        self.layout = layout
    }

    /// Exercises every location, removing the stubs it wrote and, for roles that do not retain
    /// them, the directories it created.
    ///
    /// - Returns: Ordered evidence for every location, including failures and cleanup attempts.
    public func run() -> [LocationProbe] {
        layout.locations.map { probe($0) }
    }

    /// - Returns: The attempted operations for one location, including applicable cleanup.
    private func probe(_ location: StorageLayout.Location) -> LocationProbe {
        let start = ContinuousClock.now
        switch location.resolution {
        case .failure(let error):
            return LocationProbe(role: location.role, path: nil, preexisting: false,
                operations: [ProbeOperation(kind: .resolve, path: error.path?.path,
                    outcome: .failed(OperationFailure(error.underlyingError)), byteCount: nil,
                    duration: start.duration(to: .now), contended: false)])
        case .success(let resolved):
            var operations = [ProbeOperation(kind: .resolve, path: resolved.root.path, outcome: .satisfied,
                byteCount: nil, duration: start.duration(to: .now), contended: false)]
            let preexisting = FileManager.default.fileExists(atPath: resolved.directory.path)
            var created: [URL] = []
            let ready = record(.createDirectory, path: resolved.directory, operations: &operations) {
                ActionResult(contended: try createDirectories(resolved.directory,
                                                              missing: missingAncestors(of: resolved.directory),
                                                              created: &created))
            }
            if ready {
                roundTrip(in: resolved.directory, operations: &operations)
            }
            if location.role.removesCreatedDirectories {
                cleanup(created, operations: &operations)
            }
            return LocationProbe(role: location.role, path: resolved.directory.path,
                preexisting: preexisting, operations: operations)
        }
    }

    /// Removes owned directories deepest-first and records the result of every attempt without
    /// stopping cleanup.
    ///
    /// - Parameters:
    ///   - created: Owned directories in parent-before-child creation order.
    ///   - operations: Evidence to append for every attempted removal.
    internal func cleanup(_ created: [URL], operations: inout [ProbeOperation]) {
        for directory in created.reversed() {
            record(.removeDirectory, path: directory, operations: &operations) {
                switch try removeEmptyDirectory(directory) {
                case .removed: ActionResult()
                case .absent: ActionResult(contended: true)
                case .refused: ActionResult(satisfied: false, contended: true)
                }
            }
        }
    }

    private func roundTrip(in directory: URL, operations: inout [ProbeOperation]) {
        let stub = directory.appendingPathComponent("xc-probe-\(UUID().uuidString)")
        var generator = SystemRandomNumberGenerator()
        let expected = Data((0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
        let written = record(.write, path: stub, operations: &operations) {
            try expected.write(to: stub, options: .withoutOverwriting)
            return ActionResult(byteCount: expected.count)
        }
        // A failed write can leave a partially written file that still needs removal.
        let collision = operations.last?.failure.map { $0.domain == NSCocoaErrorDomain && $0.code == NSFileWriteFileExistsError } ?? false
        let ownsStub = written || (!collision && FileManager.default.fileExists(atPath: stub.path))
        defer {
            if ownsStub {
                record(.removeStub, path: stub, operations: &operations) {
                    try FileManager.default.removeItem(at: stub)
                    return ActionResult()
                }
            }
        }
        guard written else { return }
        var actual = Data()
        guard record(.read, path: stub, operations: &operations, action: {
            actual = try Data(contentsOf: stub)
            return ActionResult(byteCount: actual.count)
        }) else { return }
        record(.verify, path: stub, operations: &operations) {
            guard actual == expected else {
                throw NSError(domain: "XCCore.StorageProbe", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Read-back bytes differ from the written bytes."])
            }
            return ActionResult(byteCount: actual.count)
        }
    }

    /// Returns every path that must be created for a directory to exist.
    ///
    /// - Parameter directory: The directory that will be created.
    /// - Returns: Paths that do not currently exist, `directory` itself first and its ancestors
    ///   after. Empty when the directory already exists.
    internal func missingAncestors(of directory: URL) -> [URL] {
        var missing: [URL] = []
        var current = directory
        while !FileManager.default.fileExists(atPath: current.path) && current.path != "/" {
            missing.append(current)
            current.deleteLastPathComponent()
        }
        return missing
    }

    /// Creates the scanned directories one at a time; only successful creations become owned.
    ///
    /// A directory that appears between the scan and the attempt is treated as satisfied rather
    /// than failed, and is not claimed as owned.
    ///
    /// - Parameters:
    ///   - directory: The target directory. Created with intermediates when the scan is empty, in
    ///     which case nothing on that path is claimed as owned; also attributes a failure there.
    ///   - missing: The scan result, ordered child-before-parent.
    ///   - created: Receives every directory this call created, in parent-before-child order.
    /// - Returns: Whether a competing process created one of the directories first.
    /// - Throws: The Foundation failure for the first directory that cannot be created.
    internal func createDirectories(
        _ directory: URL,
        missing: [URL],
        created: inout [URL]
    ) throws(DirectoryCreationFailure) -> Bool {
        var attempted = directory
        var contended = false
        do {
            if missing.isEmpty {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            for candidate in missing.reversed() {
                attempted = candidate
                do {
                    try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: false)
                    created.append(candidate)
                } catch let error as NSError where isExistingDirectory(error, at: candidate) {
                    contended = true
                }
            }
        } catch {
            throw DirectoryCreationFailure(path: attempted, underlyingError: error as NSError, contended: contended)
        }
        return contended
    }

    /// - Parameters:
    ///   - error: The failure raised by directory creation.
    ///   - url: The path that could not be created.
    /// - Returns: Whether the failure is a collision with a directory itself, rather than with a
    ///   file or with a symbolic link. The link is excluded because the probe would otherwise write
    ///   its evidence through the link while reporting the path it was given.
    private func isExistingDirectory(_ error: NSError, at url: URL) -> Bool {
        guard error.domain == NSCocoaErrorDomain, error.code == NSFileWriteFileExistsError else { return false }
        var status = stat()
        guard url.path.withCString({ lstat($0, &status) }) == 0 else { return false }
        return status.st_mode & S_IFMT == S_IFDIR
    }

    /// Removes a directory only when it is empty, including at the instant of removal.
    ///
    /// - Parameter directory: The directory to remove.
    /// - Returns: How the directory was left. A directory that is already gone satisfies the
    ///   removal; one that holds contents is left in place.
    /// - Throws: The POSIX failure if removal fails for any other reason.
    private func removeEmptyDirectory(_ directory: URL) throws(NSError) -> Removal {
        let code = directory.path.withCString { path in Darwin.rmdir(path) == 0 ? 0 : errno }
        switch code {
        case 0: return .removed
        case ENOENT: return .absent
        case ENOTEMPTY, EEXIST: return .refused
        default: throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
        }
    }

    /// - Returns: Whether the operation's postcondition holds, after appending its evidence.
    @discardableResult
    private func record(
        _ kind: ProbeOperation.Kind,
        path: URL,
        operations: inout [ProbeOperation],
        action: () throws -> ActionResult
    ) -> Bool {
        let start = ContinuousClock.now
        do {
            let result = try action()
            operations.append(ProbeOperation(kind: kind, path: path.path,
                outcome: result.satisfied ? .satisfied : .declined, byteCount: result.byteCount,
                duration: start.duration(to: .now), contended: result.contended))
            return result.satisfied
        } catch {
            operations.append(Self.failedOperation(kind, path: path, error: error, duration: start.duration(to: .now)))
            return false
        }
    }

    /// Attributes a failed action, preferring the path a directory creation stopped at and keeping
    /// any contention it observed before stopping.
    ///
    /// - Parameters:
    ///   - kind: The kind of action that failed.
    ///   - path: The action's nominal path.
    ///   - error: The failure the action raised.
    ///   - duration: How long the action ran before failing.
    /// - Returns: Evidence for the failure.
    internal static func failedOperation(
        _ kind: ProbeOperation.Kind,
        path: URL,
        error: any Error,
        duration: Duration
    ) -> ProbeOperation {
        let creation = error as? DirectoryCreationFailure
        return ProbeOperation(kind: kind, path: (creation?.path ?? path).path,
            outcome: .failed(OperationFailure(creation?.underlyingError ?? error as NSError)), byteCount: nil,
            duration: duration, contended: creation?.contended ?? false)
    }
}

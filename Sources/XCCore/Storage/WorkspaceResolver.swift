//
//  WorkspaceResolver.swift
//  XCCore
//
//  Created by Mathew Gacy on 9/6/26.
//  Copyright © 2026 Mathew Gacy. All rights reserved.
//

import Foundation

public struct WorkspaceResolutionError: Error, Sendable {
    public let path: URL
    public let underlyingError: NSError

    public init(path: URL, underlyingError: NSError) {
        self.path = path
        self.underlyingError = underlyingError
    }
}

public enum WorkspaceResolver {
    /// Finds the nearest git root, otherwise the nearest package root, otherwise the working
    /// directory.
    ///
    /// - Parameter workingDirectory: An existing directory from which to search upward.
    /// - Returns: An identity with symlinks resolved in both root paths.
    /// - Throws: `WorkspaceResolutionError` for inaccessible paths or malformed linked-worktree
    ///   metadata.
    public static func resolve(workingDirectory: URL) throws(WorkspaceResolutionError) -> WorkspaceIdentity {
        let working = workingDirectory.resolvingSymlinksInPath()
        guard try isDirectory(working) else { throw invalid(working, "The working directory is not a directory.") }
        var candidate = working
        var packageRoot: URL?
        while true {
            let git = candidate.appendingPathComponent(".git")
            if let directory = try directoryIfPresent(git) {
                if directory {
                    return WorkspaceIdentity(worktreeRoot: candidate, repositoryRoot: candidate, resolution: .gitWorktree)
                }
                return try linkedIdentity(worktree: candidate, gitFile: git)
            }
            if packageRoot == nil, try directoryIfPresent(candidate.appendingPathComponent("Package.swift")) == false {
                packageRoot = candidate
            }
            if candidate.path == "/" { break }
            let parent = candidate.deletingLastPathComponent().standardizedFileURL
            if parent.path == candidate.path { break }
            candidate = parent
        }
        return WorkspaceIdentity(
            worktreeRoot: packageRoot ?? working,
            repositoryRoot: nil,
            resolution: packageRoot == nil ? .workingDirectory : .packageRoot
        )
    }

    /// Reads a single-line path record and resolves it against a base directory.
    ///
    /// - Parameters:
    ///   - file: The record to read.
    ///   - base: The directory a relative record is resolved against.
    ///   - prefix: A required leading marker to strip, or nil when the record holds only a path.
    /// - Returns: A canonical directory URL with symlinks resolved.
    /// - Throws: `WorkspaceResolutionError` if the record is unreadable, empty, or malformed.
    private static func pathRecord(
        _ file: URL,
        relativeTo base: URL,
        prefix: String? = nil
    ) throws(WorkspaceResolutionError) -> URL {
        let contents: String
        do {
            contents = try String(contentsOf: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            throw WorkspaceResolutionError(path: file, underlyingError: error as NSError)
        }
        var record = contents
        if let prefix {
            guard record.hasPrefix(prefix) else { throw invalid(file, "Expected a \(prefix) pointer.") }
            record = String(record.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        guard !record.isEmpty, !record.contains("\n") else { throw invalid(file, "The record is empty or malformed.") }
        let resolvedPath = record.hasPrefix("/") ? record : (base.path as NSString).appendingPathComponent(record)
        return URL(fileURLWithPath: resolvedPath, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
    }

    /// Returns the common git directory git recorded for a linked worktree.
    ///
    /// Falls back to the conventional `<common>/worktrees/<name>` layout when the record is absent,
    /// so worktrees written without one still resolve.
    ///
    /// - Parameters:
    ///   - metadata: The worktree's metadata directory.
    ///   - gitFile: The pointer file, used to attribute a fallback failure.
    /// - Returns: A canonical directory that exists.
    /// - Throws: `WorkspaceResolutionError` if the record is malformed or names no directory.
    private static func commonDirectory(metadata: URL, gitFile: URL) throws(WorkspaceResolutionError) -> URL {
        let record = metadata.appendingPathComponent("commondir")
        guard try directoryIfPresent(record) != nil else {
            let worktrees = metadata.deletingLastPathComponent()
            guard worktrees.lastPathComponent == "worktrees" else {
                throw invalid(gitFile, "Expected a <common>/worktrees/<name> metadata directory.")
            }
            return worktrees.deletingLastPathComponent()
        }
        let common = try pathRecord(record, relativeTo: metadata)
        guard try isDirectory(common) else {
            throw invalid(record, "The commondir record does not name a directory.")
        }
        return common
    }

    /// - Parameters:
    ///   - worktree: The directory containing the git pointer.
    ///   - gitFile: The pointer file.
    /// - Returns: The identity associated with standard linked-worktree metadata.
    /// - Throws: `WorkspaceResolutionError` if the pointer cannot be read or resolved.
    private static func linkedIdentity(worktree: URL, gitFile: URL) throws(WorkspaceResolutionError) -> WorkspaceIdentity {
        let metadata = try pathRecord(gitFile, relativeTo: worktree, prefix: "gitdir:")
        guard try isDirectory(metadata) else {
            throw invalid(gitFile, "The gitdir: pointer does not name a metadata directory.")
        }
        let common = try commonDirectory(metadata: metadata, gitFile: gitFile)
        let bare = common.lastPathComponent != ".git"
        return WorkspaceIdentity(
            worktreeRoot: worktree,
            repositoryRoot: bare ? common : common.deletingLastPathComponent(),
            resolution: bare ? .gitBareLinkedWorktree : .gitLinkedWorktree
        )
    }

    /// - Parameter url: The path to inspect.
    /// - Returns: Whether the existing item is a directory.
    /// - Throws: `WorkspaceResolutionError` if the path is missing or inaccessible.
    private static func isDirectory(_ url: URL) throws(WorkspaceResolutionError) -> Bool {
        guard let directory = try directoryIfPresent(url) else {
            throw WorkspaceResolutionError(
                path: url,
                underlyingError: NSError(
                    domain: NSCocoaErrorDomain,
                    code: NSFileReadNoSuchFileError,
                    userInfo: [NSFilePathErrorKey: url.path]
                )
            )
        }
        return directory
    }

    /// - Parameter url: The path to inspect.
    /// - Returns: Whether the item is a directory, or nil only when it does not exist.
    /// - Throws: `WorkspaceResolutionError` if metadata cannot be read.
    private static func directoryIfPresent(_ url: URL) throws(WorkspaceResolutionError) -> Bool? {
        do {
            return try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
        } catch {
            let error = error as NSError
            if error.domain == NSCocoaErrorDomain, error.code == NSFileReadNoSuchFileError { return nil }
            throw WorkspaceResolutionError(path: url, underlyingError: error)
        }
    }

    /// - Parameters:
    ///   - path: The invalid input path.
    ///   - message: The reason the input is invalid.
    /// - Returns: A typed error carrying Cocoa corrupt-file evidence.
    private static func invalid(_ path: URL, _ message: String) -> WorkspaceResolutionError {
        WorkspaceResolutionError(
            path: path,
            underlyingError: NSError(
                domain: NSCocoaErrorDomain,
                code: NSFileReadCorruptFileError,
                userInfo: [NSLocalizedDescriptionKey: message, NSFilePathErrorKey: path.path]
            )
        )
    }
}

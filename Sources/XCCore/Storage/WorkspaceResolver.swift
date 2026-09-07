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
        return WorkspaceIdentity(worktreeRoot: packageRoot ?? working, repositoryRoot: nil,
                                 resolution: packageRoot == nil ? .workingDirectory : .packageRoot)
    }

    /// - Parameters:
    ///   - worktree: The directory containing the git pointer.
    ///   - gitFile: The pointer file.
    /// - Returns: The identity associated with standard linked-worktree metadata.
    /// - Throws: `WorkspaceResolutionError` if the pointer cannot be read or resolved.
    private static func linkedIdentity(worktree: URL, gitFile: URL) throws(WorkspaceResolutionError) -> WorkspaceIdentity {
        let contents: String
        do {
            contents = try String(contentsOf: gitFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            throw WorkspaceResolutionError(path: gitFile, underlyingError: error as NSError)
        }
        guard contents.hasPrefix("gitdir:") else { throw invalid(gitFile, "Expected a gitdir: pointer.") }
        let pointer = String(contents.dropFirst(7)).trimmingCharacters(in: .whitespaces)
        guard !pointer.isEmpty, !pointer.contains("\n") else { throw invalid(gitFile, "The gitdir: pointer is empty or malformed.") }
        let metadataPath = pointer.hasPrefix("/") ? pointer : (worktree.path as NSString).appendingPathComponent(pointer)
        let metadata = URL(fileURLWithPath: metadataPath, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
        let worktrees = metadata.deletingLastPathComponent()
        let common = worktrees.deletingLastPathComponent()
        guard worktrees.lastPathComponent == "worktrees", common.lastPathComponent == ".git", try isDirectory(metadata) else {
            throw invalid(gitFile, "Expected a .git/worktrees/<name> metadata directory.")
        }
        return WorkspaceIdentity(worktreeRoot: worktree, repositoryRoot: common.deletingLastPathComponent(), resolution: .gitLinkedWorktree)
    }

    /// - Parameter url: The path to inspect.
    /// - Returns: Whether the existing item is a directory.
    /// - Throws: `WorkspaceResolutionError` if the path is missing or inaccessible.
    private static func isDirectory(_ url: URL) throws(WorkspaceResolutionError) -> Bool {
        guard let directory = try directoryIfPresent(url) else {
            throw WorkspaceResolutionError(path: url, underlyingError: NSError(domain: NSCocoaErrorDomain,
                code: NSFileReadNoSuchFileError, userInfo: [NSFilePathErrorKey: url.path]))
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
        WorkspaceResolutionError(path: path, underlyingError: NSError(domain: NSCocoaErrorDomain,
            code: NSFileReadCorruptFileError, userInfo: [NSLocalizedDescriptionKey: message, NSFilePathErrorKey: path.path]))
    }
}

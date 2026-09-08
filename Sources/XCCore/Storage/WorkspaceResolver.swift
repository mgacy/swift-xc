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
        return directoryURL(record, relativeTo: base)
    }

    /// - Parameters:
    ///   - path: An absolute path, or one relative to `base`.
    ///   - base: The directory a relative path is resolved against.
    /// - Returns: A canonical directory URL with symlinks resolved.
    private static func directoryURL(_ path: String, relativeTo base: URL) -> URL {
        let resolved = path.hasPrefix("/") ? path : (base.path as NSString).appendingPathComponent(path)
        return URL(fileURLWithPath: resolved, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
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

    /// Resolves a linked worktree against the topology recorded for its repository.
    ///
    /// `core.bare` decides whether the common directory is itself the repository. A repository that
    /// records no topology is classified by the conventional `.git` spelling of its common
    /// directory.
    ///
    /// - Parameters:
    ///   - worktree: The directory containing the pointer.
    ///   - gitFile: The pointer file.
    /// - Returns: The identity associated with standard linked-worktree metadata.
    /// - Throws: `WorkspaceResolutionError` if the pointer cannot be read or resolved.
    private static func linkedIdentity(worktree: URL, gitFile: URL) throws(WorkspaceResolutionError) -> WorkspaceIdentity {
        let metadata = try pathRecord(gitFile, relativeTo: worktree, prefix: "gitdir:")
        guard try isDirectory(metadata) else {
            throw invalid(gitFile, "The gitdir: pointer does not name a metadata directory.")
        }
        let common = try commonDirectory(metadata: metadata, gitFile: gitFile)
        let core = try coreConfiguration(in: common)
        let bare = core.bare ?? (common.lastPathComponent != ".git")
        return WorkspaceIdentity(
            worktreeRoot: worktree,
            repositoryRoot: bare ? common : mainWorktree(common: common, recorded: core.worktree),
            resolution: bare ? .gitBareLinkedWorktree : .gitLinkedWorktree
        )
    }

    /// Locates the working tree that a non-bare repository's worktrees branch from.
    ///
    /// `core.worktree` is recorded only when the working tree is somewhere other than the parent of
    /// a `.git` common directory. Nothing names the working tree of a repository that records
    /// neither, so the common directory stands in as the root its worktrees share.
    ///
    /// - Parameters:
    ///   - common: The common directory.
    ///   - recorded: The `core.worktree` record, when present.
    /// - Returns: The main working tree, otherwise the common directory.
    private static func mainWorktree(common: URL, recorded: String?) -> URL {
        if let recorded, !recorded.isEmpty { return directoryURL(recorded, relativeTo: common) }
        return common.lastPathComponent == ".git" ? common.deletingLastPathComponent() : common
    }

    /// Reads `core.bare` and `core.worktree` from a repository's configuration.
    ///
    /// Only the `core` section is scanned, and only for those two keys; every other section, key,
    /// and include directive is ignored, as is a key written on a section header's own line. An
    /// absent configuration yields no records, so a repository without one still resolves.
    ///
    /// - Parameter common: The common directory holding the configuration.
    /// - Returns: The recorded values, each nil when the key is absent or uninterpretable.
    /// - Throws: `WorkspaceResolutionError` if a configuration exists but cannot be read.
    private static func coreConfiguration(
        in common: URL
    ) throws(WorkspaceResolutionError) -> (bare: Bool?, worktree: String?) {
        let file = common.appendingPathComponent("config")
        guard try directoryIfPresent(file) != nil else { return (nil, nil) }
        let contents: String
        do {
            contents = try String(contentsOf: file, encoding: .utf8)
        } catch {
            throw WorkspaceResolutionError(path: file, underlyingError: error as NSError)
        }
        var core = false
        var bare: Bool?
        var worktree: String?
        for line in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let statement = line.trimmingCharacters(in: .whitespaces)
            if statement.isEmpty || statement.hasPrefix("#") || statement.hasPrefix(";") { continue }
            if statement.hasPrefix("[") {
                core = statement.dropFirst().prefix { !" \t]".contains($0) }.lowercased() == "core"
                continue
            }
            guard core else { continue }
            let separator = statement.firstIndex(of: "=")
            let key = statement[..<(separator ?? statement.endIndex)].trimmingCharacters(in: .whitespaces).lowercased()
            let value = separator.map { String(statement[statement.index(after: $0)...]) }
            switch key {
            case "bare": bare = booleanRecord(value)
            case "worktree": worktree = value.map(unquoted)
            default: continue
            }
        }
        return (bare, worktree)
    }

    /// - Parameter value: A configuration value, or nil when the key carries none.
    /// - Returns: The value read as a boolean, or nil when it names neither. A key written without
    ///   a value is true; a key written with an empty one is false.
    private static func booleanRecord(_ value: String?) -> Bool? {
        guard let value else { return true }
        switch unquoted(value).lowercased() {
        case "true", "yes", "on", "1": return true
        case "", "false", "no", "off", "0": return false
        default: return nil
        }
    }

    /// Strips the quoting and trailing comment from a configuration value.
    ///
    /// Escapes are taken literally rather than translated, which suits the path and boolean values
    /// this resolver reads.
    ///
    /// - Parameter value: The raw text following a key's `=`.
    /// - Returns: The value's content.
    private static func unquoted(_ value: String) -> String {
        var content = ""
        var quoted = false
        var escaped = false
        for character in value {
            if escaped {
                content.append(character)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                quoted.toggle()
            } else if !quoted, character == "#" || character == ";" {
                break
            } else {
                content.append(character)
            }
        }
        return content.trimmingCharacters(in: .whitespaces)
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

//
//  WorkspaceIdentity.swift
//  XCCore
//
//  Created by Mathew Gacy on 9/6/26.
//  Copyright © 2026 Mathew Gacy. All rights reserved.
//

import CryptoKit
import Foundation

public struct WorkspaceIdentity: Equatable, Sendable {
    public enum Resolution: Sendable {
        case gitWorktree
        case gitLinkedWorktree
        case gitBareLinkedWorktree
        case packageRoot
        case workingDirectory
    }

    public let id: String
    public let worktreeRoot: URL
    public let repositoryRoot: URL?
    public let resolution: Resolution

    /// Creates an identity from canonical paths; a missing repository contributes an empty hash
    /// component.
    ///
    /// - Parameters:
    ///   - worktreeRoot: The workspace directory.
    ///   - repositoryRoot: The root its worktrees share: the working tree for `.gitWorktree` and
    ///     `.gitLinkedWorktree`, the repository directory itself for `.gitBareLinkedWorktree`, and
    ///     nil when no repository was found.
    ///   - resolution: How the workspace directory was discovered.
    public init(worktreeRoot: URL, repositoryRoot: URL?, resolution: Resolution) {
        self.worktreeRoot = worktreeRoot.resolvingSymlinksInPath()
        self.repositoryRoot = repositoryRoot?.resolvingSymlinksInPath()
        self.resolution = resolution
        let name = resolution == .gitBareLinkedWorktree
            ? Self.displayName(for: self.repositoryRoot ?? self.worktreeRoot)
            : (self.repositoryRoot ?? self.worktreeRoot).lastPathComponent
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        let slug = name.unicodeScalars.map { allowed.contains($0) ? String($0) : "-" }.joined()
        let input = (self.repositoryRoot?.path ?? "") + "\n" + self.worktreeRoot.path
        let digest = SHA256.hash(data: Data(input.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
        self.id = "\(slug.isEmpty ? "workspace" : slug)-\(digest)"
    }

    /// Returns a readable repository name for a bare repository's common directory.
    ///
    /// A trailing `.git` is dropped so a bare repository reads like its clone. When nothing readable
    /// remains — a hidden name, as in the `<project>/.bare` layout — the parent directory names the
    /// repository instead.
    ///
    /// - Parameter root: The common directory of a bare repository.
    /// - Returns: The unsanitized name for the identity's readable prefix.
    private static func displayName(for root: URL) -> String {
        var name = root.lastPathComponent
        if name.hasSuffix(".git") { name = String(name.dropLast(4)) }
        guard name.isEmpty || name.hasPrefix(".") else { return name }
        let parent = root.deletingLastPathComponent().lastPathComponent
        return parent.isEmpty || parent == "/" ? name : parent
    }
}

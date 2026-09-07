//
//  WorkspaceIdentity.swift
//  XCCore
//
//  Created by Mathew Gacy on 9/6/26.
//  Copyright © 2026 Mathew Gacy. All rights reserved.
//

import CryptoKit
import Foundation

public struct WorkspaceIdentity: Sendable, Equatable {
    public enum Resolution: String, Sendable {
        case gitWorktree
        case gitLinkedWorktree
        case packageRoot
        case workingDirectory
    }

    public let id: String
    public let worktreeRoot: URL
    public let repositoryRoot: URL?
    public let resolution: Resolution

    /// Creates an identity from canonical paths; a missing repository contributes an empty hash component.
    /// - Parameters:
    ///   - worktreeRoot: The workspace directory.
    ///   - repositoryRoot: The shared repository directory, when known.
    ///   - resolution: How the workspace directory was discovered.
    public init(worktreeRoot: URL, repositoryRoot: URL?, resolution: Resolution) {
        self.worktreeRoot = worktreeRoot.resolvingSymlinksInPath()
        self.repositoryRoot = repositoryRoot?.resolvingSymlinksInPath()
        self.resolution = resolution
        let name = (self.repositoryRoot ?? self.worktreeRoot).lastPathComponent
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")
        let slug = name.unicodeScalars.map { allowed.contains($0) ? String($0) : "-" }.joined()
        let input = (self.repositoryRoot?.path ?? "") + "\n" + self.worktreeRoot.path
        let digest = SHA256.hash(data: Data(input.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
        self.id = "\(slug.isEmpty ? "workspace" : slug)-\(digest)"
    }
}

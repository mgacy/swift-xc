//
//  StorageTests.swift
//  XCCoreTests
//
//  Created by Mathew Gacy on 9/6/26.
//  Copyright © 2026 Mathew Gacy. All rights reserved.
//

import CryptoKit
import Darwin
import Foundation
import Testing
@testable import XCCore

@Suite("Storage")
struct StorageTests {
    @Test("Discovers every workspace fallback", arguments: ["git", "package", "plain"])
    func discoversWorkspace(_ mode: String) throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let child = root.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        if mode == "git" {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(".git"), withIntermediateDirectories: true)
        } else if mode == "package" {
            try Data().write(to: root.appendingPathComponent("Package.swift"))
        }
        let identity = try WorkspaceResolver.resolve(workingDirectory: child)
        #expect(identity.resolution == (mode == "git" ? .gitWorktree : mode == "package" ? .packageRoot : .workingDirectory))
        #expect(identity.worktreeRoot.path == (mode == "plain" ? child : root).path)
        #expect(identity.repositoryRoot?.path == (mode == "git" ? root.path : nil))
    }

    @Test("Linked worktrees share a repository slug and have isolated hashes")
    func linkedWorktrees() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = root.appendingPathComponent("Example Repo")
        var identities: [WorkspaceIdentity] = []
        for name in ["first", "second"] {
            let metadata = repo.appendingPathComponent(".git/worktrees/\(name)")
            let worktree = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
            if name == "second" {
                // Exercise the commondir-record branch; "first" exercises the no-record fallback.
                try Data("../..\n".utf8).write(to: metadata.appendingPathComponent("commondir"))
            }
            try Data("gitdir: ../Example Repo/.git/worktrees/\(name)\n".utf8).write(to: worktree.appendingPathComponent(".git"))
            let identity = try WorkspaceResolver.resolve(workingDirectory: worktree)
            #expect(identity.resolution == .gitLinkedWorktree)
            #expect(identity.repositoryRoot?.path == repo.path)
            #expect(identity.id.hasPrefix("Example-Repo-"))
            let digest = SHA256.hash(data: Data("\(repo.path)\n\(worktree.path)".utf8))
            #expect(identity.id == "Example-Repo-" + digest.prefix(6).map { String(format: "%02x", $0) }.joined())
            identities.append(identity)
        }
        #expect(identities[0].id != identities[1].id)
    }

    @Test("A worktree of a bare repository resolves as bare-linked with the bare directory as its root")
    func bareRepositoryWorktree() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bare = root.appendingPathComponent("repo.git")
        let metadata = bare.appendingPathComponent("worktrees/wt")
        let worktree = root.appendingPathComponent("wt")
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        try Data("../..\n".utf8).write(to: metadata.appendingPathComponent("commondir"))
        try Data("gitdir: \(metadata.path)\n".utf8).write(to: worktree.appendingPathComponent(".git"))
        let identity = try WorkspaceResolver.resolve(workingDirectory: worktree)
        #expect(identity.resolution == .gitBareLinkedWorktree)
        #expect(identity.repositoryRoot?.path == bare.path)
        #expect(identity.id.hasPrefix("repo-"))
    }

    @Test("The <project>/.bare layout resolves with a slug derived from the project, not .bare")
    func bareDirectoryLayout() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let proj = root.appendingPathComponent("proj")
        let bare = proj.appendingPathComponent(".bare")
        let metadata = bare.appendingPathComponent("worktrees/wt")
        let worktree = root.appendingPathComponent("wt")
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        try Data("../..\n".utf8).write(to: metadata.appendingPathComponent("commondir"))
        try Data("gitdir: \(metadata.path)\n".utf8).write(to: worktree.appendingPathComponent(".git"))
        let identity = try WorkspaceResolver.resolve(workingDirectory: worktree)
        #expect(identity.resolution == .gitBareLinkedWorktree)
        #expect(identity.repositoryRoot?.path == bare.path)
        #expect(identity.id.hasPrefix("proj-"))
        #expect(!identity.id.hasPrefix(".bare-"))
    }

    @Test("An absolute commondir naming a directory outside <metadata>/../.. still resolves")
    func relocatedCommonDirectory() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let common = root.appendingPathComponent("elsewhere/.git")
        let metadata = root.appendingPathComponent("somewhere/worktrees/wt")
        let worktree = root.appendingPathComponent("wt")
        try FileManager.default.createDirectory(at: common, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        try Data("\(common.path)\n".utf8).write(to: metadata.appendingPathComponent("commondir"))
        try Data("gitdir: \(metadata.path)\n".utf8).write(to: worktree.appendingPathComponent(".git"))
        let identity = try WorkspaceResolver.resolve(workingDirectory: worktree)
        #expect(identity.resolution == .gitLinkedWorktree)
        #expect(identity.repositoryRoot?.path == common.deletingLastPathComponent().path)
    }

    @Test("Topology comes from the recorded core.bare rather than the common directory's name", arguments: [
        ("repo.git", "[core]\n\tbare = false\n", WorkspaceIdentity.Resolution.gitLinkedWorktree),
        ("repo.git", "[core]\n\tbare = true\n", .gitBareLinkedWorktree),
        (".git", "[core]\n\tbare\n", .gitBareLinkedWorktree),
        ("repo.git", "[core]\n\tbare =\n", .gitLinkedWorktree),
        ("repo.git", "[core]\n\tbare = \"false\" ; trailing\n", .gitLinkedWorktree),
        ("repo.git", "[remote \"origin\"]\n\tbare = true\n", .gitBareLinkedWorktree),
        (".git", "[remote \"origin\"]\n\tbare = true\n", .gitLinkedWorktree),
        (".git", "[core]\n\tbare = true\n", .gitBareLinkedWorktree)
    ])
    func recordedTopology(_ name: String, _ config: String, _ expected: WorkspaceIdentity.Resolution) throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let common = root.appendingPathComponent("main/\(name)")
        let metadata = common.appendingPathComponent("worktrees/wt")
        let worktree = root.appendingPathComponent("wt")
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        try Data(config.utf8).write(to: common.appendingPathComponent("config"))
        try Data("gitdir: \(metadata.path)\n".utf8).write(to: worktree.appendingPathComponent(".git"))
        let identity = try WorkspaceResolver.resolve(workingDirectory: worktree)
        #expect(identity.resolution == expected)
    }

    @Test("A recorded core.worktree names the repository root of a separate metadata directory")
    func separateMetadataDirectory() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let common = root.appendingPathComponent("sepdir")
        let main = root.appendingPathComponent("checkout")
        let metadata = common.appendingPathComponent("worktrees/wt")
        let worktree = root.appendingPathComponent("wt")
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: main, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        try Data("[core]\n\tbare = false\n\tworktree = \(main.path)\n".utf8)
            .write(to: common.appendingPathComponent("config"))
        try Data("gitdir: \(metadata.path)\n".utf8).write(to: worktree.appendingPathComponent(".git"))
        let identity = try WorkspaceResolver.resolve(workingDirectory: worktree)
        #expect(identity.resolution == .gitLinkedWorktree)
        #expect(identity.repositoryRoot?.path == main.path)
        #expect(identity.id.hasPrefix("checkout-"))
    }

    @Test("A separate metadata directory that records no working tree is its own repository root")
    func unrecordedMetadataDirectory() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let common = root.appendingPathComponent("sepdir")
        let metadata = common.appendingPathComponent("worktrees/wt")
        let worktree = root.appendingPathComponent("wt")
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        try Data("[core]\n\tbare = false\n".utf8).write(to: common.appendingPathComponent("config"))
        try Data("gitdir: \(metadata.path)\n".utf8).write(to: worktree.appendingPathComponent(".git"))
        let identity = try WorkspaceResolver.resolve(workingDirectory: worktree)
        #expect(identity.resolution == .gitLinkedWorktree)
        #expect(identity.repositoryRoot?.path == common.path)
        #expect(identity.id.hasPrefix("sepdir-"))
    }

    @Test("A configuration that exists but cannot be read is an error, not a silent fallback",
          .enabled(if: geteuid() != 0))
    func unreadableConfiguration() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let common = root.appendingPathComponent("repo.git")
        let metadata = common.appendingPathComponent("worktrees/wt")
        let worktree = root.appendingPathComponent("wt")
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        let config = common.appendingPathComponent("config")
        try Data("[core]\n\tbare = true\n".utf8).write(to: config)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: config.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: config.path) }
        try Data("gitdir: \(metadata.path)\n".utf8).write(to: worktree.appendingPathComponent(".git"))
        #expect(throws: WorkspaceResolutionError.self) { try WorkspaceResolver.resolve(workingDirectory: worktree) }
    }

    @Test("Malformed commondir records throw typed errors", arguments: ["", "one\ntwo", "/definitely/missing/path"])
    func malformedCommonDirectory(_ content: String) throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let metadata = root.appendingPathComponent("repo.git/worktrees/wt")
        let worktree = root.appendingPathComponent("wt")
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        try Data(content.utf8).write(to: metadata.appendingPathComponent("commondir"))
        try Data("gitdir: \(metadata.path)\n".utf8).write(to: worktree.appendingPathComponent(".git"))
        #expect(throws: WorkspaceResolutionError.self) { try WorkspaceResolver.resolve(workingDirectory: worktree) }
    }

    @Test("Bare-repository slugs strip a trailing .git and fall back to the parent for a hidden name", arguments: [
        ("repo.git", "repo-"), ("proj/.bare", "proj-"), ("party🎉.git", "party--")
    ])
    func bareSlugDerivation(_ path: String, _ expectedPrefix: String) {
        let root = URL(fileURLWithPath: "/tmp/workspace-fixture/\(path)")
        let identity = WorkspaceIdentity(worktreeRoot: root, repositoryRoot: root, resolution: .gitBareLinkedWorktree)
        #expect(identity.id.hasPrefix(expectedPrefix))
    }

    @Test("Slug for a plain git worktree repository still uses the raw last path component")
    func slugScopingGitWorktree() {
        let root = URL(fileURLWithPath: "/tmp/workspace-fixture/dev/.dotfiles")
        let identity = WorkspaceIdentity(worktreeRoot: root, repositoryRoot: root, resolution: .gitWorktree)
        #expect(identity.id.hasPrefix(".dotfiles-"))
    }

    @Test("Slug for a normal linked worktree still uses the raw last path component")
    func slugScopingLinkedWorktree() {
        let worktree = URL(fileURLWithPath: "/tmp/workspace-fixture/worktrees/wt")
        let repo = URL(fileURLWithPath: "/tmp/workspace-fixture/dev/.dotfiles")
        let identity = WorkspaceIdentity(worktreeRoot: worktree, repositoryRoot: repo, resolution: .gitLinkedWorktree)
        #expect(identity.id.hasPrefix(".dotfiles-"))
    }

    @Test("Slug for a hidden package root still uses its own name")
    func slugScopingPackageRoot() {
        let root = URL(fileURLWithPath: "/tmp/workspace-fixture/.hidden-package")
        let identity = WorkspaceIdentity(worktreeRoot: root, repositoryRoot: nil, resolution: .packageRoot)
        #expect(identity.id.hasPrefix(".hidden-package-"))
    }

    @Test("Slug for a plain working directory still uses its own name")
    func slugScopingWorkingDirectory() {
        let root = URL(fileURLWithPath: "/tmp/workspace-fixture/.config")
        let identity = WorkspaceIdentity(worktreeRoot: root, repositoryRoot: nil, resolution: .workingDirectory)
        #expect(identity.id.hasPrefix(".config-"))
    }

    @Test("Canonical aliases produce the same identity and git wins over a nested package")
    func canonicalIdentity() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let repo = root.appendingPathComponent("repo")
        let nested = repo.appendingPathComponent("nested")
        let alias = root.appendingPathComponent("alias")
        try FileManager.default.createDirectory(at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data().write(to: nested.appendingPathComponent("Package.swift"))
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: repo)
        #expect(try WorkspaceResolver.resolve(workingDirectory: alias) == WorkspaceResolver.resolve(workingDirectory: nested))
    }

    @Test("Malformed git pointers and missing working directories throw typed errors")
    func resolutionFailure() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("invalid".utf8).write(to: root.appendingPathComponent(".git"))
        #expect(throws: WorkspaceResolutionError.self) { try WorkspaceResolver.resolve(workingDirectory: root) }
        #expect(throws: WorkspaceResolutionError.self) {
            try WorkspaceResolver.resolve(workingDirectory: root.appendingPathComponent("missing"))
        }
    }

    @Test("All six locations use their intended roots and role paths")
    func rolePaths() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = try WorkspaceResolver.resolve(workingDirectory: root)
        let run = RunIdentifier(date: Date(timeIntervalSince1970: 0))
        let layout = StorageLayout(caches: root.appendingPathComponent("cache"),
                                   applicationSupport: root.appendingPathComponent("support"), workspace: workspace, runIdentifier: run)
        let expected = [
            "cache/xc/workspaces/\(workspace.id)/runs/\(run.rawValue)",
            "cache/xc/workspaces/\(workspace.id)/catalog", "cache/xc/workspaces/\(workspace.id)/locks",
            "support/xc/simulator-pools", ".build/xc-probe", ".deriveddata"
        ]
        #expect(layout.locations.map(\.role) == StorageRole.allCases)
        for (location, suffix) in zip(layout.locations, expected) {
            #expect(try location.resolution.get().directory.path == root.appendingPathComponent(suffix).path)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test("Only worktree-local roles sweep the directories they create")
    func directorySweeping() {
        #expect(StorageRole.allCases.filter(\.removesCreatedDirectories) == [.worktreeBuild, .worktreeDerivedData])
    }

    @Test("Production search roots match Foundation without creating directories")
    func productionRoots() throws {
        for directory: FileManager.SearchPathDirectory in [.cachesDirectory, .applicationSupportDirectory] {
            let resolved = try StorageLayout.resolveRoot(directory).get()
            let expected = try FileManager.default.url(for: directory, in: .userDomainMask, appropriateFor: nil, create: false)
            #expect(resolved == expected.resolvingSymlinksInPath())
        }
    }

    @Test("A root error preserves original evidence while independent locations resolve")
    func rootFailure() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = try WorkspaceResolver.resolve(workingDirectory: root)
        let original = NSError(domain: NSCocoaErrorDomain, code: 513, userInfo: [NSLocalizedDescriptionKey: "fixture denied"])
        let failure = StorageResolutionError(path: root, underlyingError: original)
        let layout = StorageLayout(caches: .failure(failure), applicationSupport: .success(root),
                                   workspace: .success(workspace), runIdentifier: RunIdentifier())
        for location in layout.locations.prefix(3) {
            guard case .failure(let error) = location.resolution else { Issue.record("Cache root unexpectedly resolved"); continue }
            #expect(error.underlyingError == original)
            #expect(error.path == root)
        }
        for location in layout.locations.suffix(3) { _ = try location.resolution.get() }
        #expect(throws: StorageResolutionError.self) { try StorageLayout.resolveRoot(.itemReplacementDirectory).get() }
    }

    @Test("Run IDs use UTC seconds and twelve random hexadecimal digits")
    func runIDs() {
        let values = (0..<100).map { _ in RunIdentifier(date: Date(timeIntervalSince1970: 0)).rawValue }
        #expect(Set(values).count == 100)
        #expect(values.allSatisfy { $0.range(of: "^19700101T000000Z-[0-9a-f]{12}$", options: .regularExpression) != nil })
    }

    @Test("Workspace failures leave Application Support independently resolvable")
    func workspaceFailure() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let missing = root.appendingPathComponent("missing")
        let workspace: Result<WorkspaceIdentity, WorkspaceResolutionError>
        do {
            workspace = .success(try WorkspaceResolver.resolve(workingDirectory: missing))
        } catch {
            workspace = .failure(error)
        }
        let layout = StorageLayout(caches: .success(root), applicationSupport: .success(root),
                                   workspace: workspace, runIdentifier: RunIdentifier())
        for location in layout.locations where location.role != .applicationSupport {
            guard case .failure(let error) = location.resolution else { Issue.record("Unexpected resolved location"); continue }
            #expect(error.path?.path == missing.path)
            #expect(error.underlyingError.domain == NSCocoaErrorDomain)
            #expect(error.underlyingError.code == NSFileReadNoSuchFileError)
        }
        let support = try #require(layout.locations.first { $0.role == .applicationSupport })
        #expect(try support.resolution.get().directory.path == root.appendingPathComponent("xc/simulator-pools").path)
    }

    @Test("Plain directory symlinks and their targets have one stable hash")
    func fallbackIdentity() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let target = root.appendingPathComponent("project")
        let alias = root.appendingPathComponent("alias")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: target)
        let identity = try WorkspaceResolver.resolve(workingDirectory: target)
        let aliased = try WorkspaceResolver.resolve(workingDirectory: alias)
        #expect(identity.id == aliased.id)
        let digest = SHA256.hash(data: Data("\n\(target.path)".utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()
        #expect(identity.id == "project-" + digest)
    }

    /// - Returns: A new empty directory owned by the test.
    /// - Throws: A Foundation error if directory creation fails.
    private func temporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}

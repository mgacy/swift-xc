//
//  StorageLayout.swift
//  XCCore
//
//  Created by Mathew Gacy on 9/6/26.
//  Copyright © 2026 Mathew Gacy. All rights reserved.
//

import Foundation

public struct StorageResolutionError: Error, Sendable {
    public let path: URL?
    public let underlyingError: NSError

    public init(path: URL?, underlyingError: NSError) {
        self.path = path
        self.underlyingError = underlyingError
    }
}

public struct StorageLayout: Sendable {
    public struct ResolvedLocation: Sendable {
        public let root: URL
        public let directory: URL
    }

    public struct Location: Sendable {
        public let role: StorageRole
        public let resolution: Result<ResolvedLocation, StorageResolutionError>
    }

    /// Contains all six roles in probe order, including unresolved locations.
    public let locations: [Location]

    /// Constructs locations using injected roots without creating directories.
    ///
    /// - Parameters:
    ///   - caches: The user cache root.
    ///   - applicationSupport: The user Application Support root.
    ///   - workspace: The resolved workspace identity.
    ///   - runIdentifier: The run identity for the retained directory.
    public init(caches: URL, applicationSupport: URL, workspace: WorkspaceIdentity, runIdentifier: RunIdentifier) {
        self.init(caches: .success(caches), applicationSupport: .success(applicationSupport),
                  workspace: .success(workspace), runIdentifier: runIdentifier)
    }

    /// Preserves root failures separately so independent locations remain available.
    ///
    /// - Parameters:
    ///   - caches: The cache root or its resolution failure.
    ///   - applicationSupport: The Application Support root or its resolution failure.
    ///   - workspace: The workspace identity or its resolution failure.
    ///   - runIdentifier: The run identity for the retained directory.
    public init(caches: Result<URL, StorageResolutionError>, applicationSupport: Result<URL, StorageResolutionError>,
                workspace: Result<WorkspaceIdentity, WorkspaceResolutionError>, runIdentifier: RunIdentifier) {
        let identity = workspace.mapError { StorageResolutionError(path: $0.path, underlyingError: $0.underlyingError) }
        locations = StorageRole.allCases.map { role in
            let resolution: Result<ResolvedLocation, StorageResolutionError>
            switch role {
            case .applicationSupport:
                resolution = applicationSupport.map { root in
                    ResolvedLocation(root: root, directory: role.directory(root: root, workspaceID: "", runIdentifier: runIdentifier))
                }
            case .userCacheRun, .userCacheCatalog, .userCacheLocks:
                resolution = caches.flatMap { root in
                    identity.map { workspace in
                        ResolvedLocation(root: root, directory: role.directory(root: root, workspaceID: workspace.id, runIdentifier: runIdentifier))
                    }
                }
            case .worktreeBuild, .worktreeDerivedData:
                resolution = identity.map { workspace in
                    ResolvedLocation(root: workspace.worktreeRoot,
                        directory: role.directory(root: workspace.worktreeRoot, workspaceID: workspace.id, runIdentifier: runIdentifier))
                }
            }
            return Location(role: role, resolution: resolution)
        }
    }

    /// Resolves a user-domain Foundation search directory without creating it.
    ///
    /// - Parameter directory: The Foundation directory to locate.
    /// - Returns: A canonical root or the unmodified Foundation failure with no invented path.
    public static func resolveRoot(_ directory: FileManager.SearchPathDirectory) -> Result<URL, StorageResolutionError> {
        do {
            return .success(try FileManager.default.url(for: directory, in: .userDomainMask,
                appropriateFor: nil, create: false).resolvingSymlinksInPath())
        } catch {
            return .failure(StorageResolutionError(path: nil, underlyingError: error as NSError))
        }
    }
}

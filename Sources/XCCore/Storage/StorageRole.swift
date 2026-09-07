//
//  StorageRole.swift
//  XCCore
//
//  Created by Mathew Gacy on 9/6/26.
//  Copyright © 2026 Mathew Gacy. All rights reserved.
//

import Foundation

public enum StorageRole: String, CaseIterable, Sendable {
    case userCacheRun = "user_cache_run"
    case userCacheCatalog = "user_cache_catalog"
    case userCacheLocks = "user_cache_locks"
    case applicationSupport = "application_support"
    case worktreeBuild = "worktree_build"
    case worktreeDerivedData = "worktree_derived_data"

    /// Constructs the role's directory beneath its resolved root.
    ///
    /// - Parameters:
    ///   - root: The cache, Application Support, or worktree root appropriate to this role.
    ///   - workspaceID: The workspace identity used by cache roles.
    ///   - runIdentifier: The run identity used by the retained artifact directory.
    /// - Returns: The absolute directory for this role.
    public func directory(root: URL, workspaceID: String, runIdentifier: RunIdentifier) -> URL {
        let suffix: String
        switch self {
        case .userCacheRun: suffix = "xc/workspaces/\(workspaceID)/runs/\(runIdentifier.rawValue)"
        case .userCacheCatalog: suffix = "xc/workspaces/\(workspaceID)/catalog"
        case .userCacheLocks: suffix = "xc/workspaces/\(workspaceID)/locks"
        case .applicationSupport: suffix = "xc/simulator-pools"
        case .worktreeBuild: suffix = ".build/xc-probe"
        case .worktreeDerivedData: suffix = ".deriveddata"
        }
        return root.appendingPathComponent(suffix, isDirectory: true)
    }
}

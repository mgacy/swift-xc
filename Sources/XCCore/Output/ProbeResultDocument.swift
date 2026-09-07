//
//  ProbeResultDocument.swift
//  XCCore
//
//  Created by Mathew Gacy on 9/6/26.
//  Copyright © 2026 Mathew Gacy. All rights reserved.
//

import Foundation

public enum ProbeResultDocument {
    // swiftlint:disable:next type_name
    public struct V1: Codable, Sendable {
        public let schemaVersion: Int
        public let toolVersion: String
        public let outcome: RunOutcome
        public let reason: String?
        public let run: Run?
        public let workspace: Workspace?
        public let artifacts: Artifacts?
        public let storage: Storage?

        private enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case toolVersion = "tool_version"
            case outcome, reason, run, workspace, artifacts, storage
        }
    }

    public struct Run: Codable, Sendable {
        public let id: String
        public let startedAt: Date
        public let durationMS: Double

        private enum CodingKeys: String, CodingKey {
            case id
            case startedAt = "started_at"
            case durationMS = "duration_ms"
        }
    }

    public struct Workspace: Codable, Sendable {
        public let id: String
        public let worktreeRoot: String
        public let repositoryRoot: String?
        public let resolution: String

        private enum CodingKeys: String, CodingKey {
            case id, resolution
            case worktreeRoot = "worktree_root"
            case repositoryRoot = "repository_root"
        }
    }

    public struct Artifacts: Codable, Sendable {
        public let result: String?
        public let retained: Bool
        public let write: Operation?
    }

    public struct Storage: Codable, Sendable {
        public let locations: [Location]
    }

    public struct Location: Codable, Sendable {
        public let role: String
        public let path: String?
        public let completed: Bool
        public let preexisting: Bool
        public let operations: [Operation]
    }

    public struct Operation: Codable, Sendable {
        public let kind: String
        public let path: String?
        public let succeeded: Bool
        public let byteCount: Int?
        public let durationMS: Double
        public let error: Failure?

        private enum CodingKeys: String, CodingKey {
            case kind, path, succeeded, error
            case byteCount = "byte_count"
            case durationMS = "duration_ms"
        }
    }

    public struct Failure: Codable, Sendable {
        public let message: String
        public let domain: String
        public let code: Int
    }
}

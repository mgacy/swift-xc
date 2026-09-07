//
//  XC.swift
//  xc
//
//  Created by Mathew Gacy on 9/6/26.
//  Copyright © 2026 Mathew Gacy. All rights reserved.
//

import ArgumentParser

// swiftlint:disable:next type_name
struct XC: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "xc",
        version: Version.number,
        subcommands: [Run.self]
    )
}

//
//  XC.swift
//  xc
//
//  Created by Mathew Gacy on 09/06/26.
//  Copyright © 2026 Mathew Gacy. All rights reserved.
//

import ArgumentParser
import XCCore

@main
struct XC: ParsableCommand {
    func run() throws {
        try XCCore.run()
    }
}

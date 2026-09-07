//
//  Main.swift
//  xc
//
//  Created by Mathew Gacy on 9/6/26.
//  Copyright © 2026 Mathew Gacy. All rights reserved.
//

import Darwin

@main
enum Main {
    static func main() {
        signal(SIGPIPE, SIG_IGN)
        do {
            var command = try XC.parseAsRoot()
            try command.run()
            exit(0)
        } catch {
            exit(Termination.code(for: error))
        }
    }
}

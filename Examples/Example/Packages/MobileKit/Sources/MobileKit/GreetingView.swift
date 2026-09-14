//
//  GreetingView.swift
//  MobileKit
//
//  Created by Mathew Gacy on 9/7/26.
//  Copyright © 2026 Mathew Gacy. All rights reserved.
//

import SharedKit
import UIKit

/// UIKit views for `SharedKit` greetings.
@MainActor
public enum GreetingView {

    /// Returns a label displaying the greeter's greeting.
    ///
    /// - Parameter greeter: The greeter to display.
    /// - Returns: A label containing the greeting text.
    public static func label(for greeter: Greeter) -> UILabel {
        let label = UILabel()
        label.text = greeter.greeting
        return label
    }
}

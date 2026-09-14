//
//  ContentView.swift
//  Example
//
//  Created by Mathew Gacy on 9/7/26.
//  Copyright © 2026 Mathew Gacy. All rights reserved.
//

import MobileKit
import SharedKit
import SwiftUI
import UIKit

struct ContentView: View {
    private let greeter = Greeter(name: "world")

    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            GreetingLabel(greeter: greeter)
        }
        .padding()
    }
}

/// The `MobileKit` greeting label, bridged into SwiftUI.
private struct GreetingLabel: UIViewRepresentable {
    let greeter: Greeter

    func makeUIView(context: Context) -> UILabel {
        GreetingView.label(for: greeter)
    }

    func updateUIView(_ label: UILabel, context: Context) {
        label.text = greeter.greeting
    }
}

#Preview {
    ContentView()
}

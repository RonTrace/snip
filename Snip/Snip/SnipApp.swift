//
//  SnipApp.swift
//  Snip
//
//  Created by Ron Kurti on 1/12/25.
//

import SwiftUI

@main
struct SnipApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

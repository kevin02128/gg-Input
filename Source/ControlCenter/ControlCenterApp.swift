// Copyright © 2026 wtf. All rights reserved.
// ControlCenterApp.swift — gg 控制台應用程式入口

import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first {
            window.title = "gg 輸入法控制台"
            window.center()
            window.makeKeyAndOrderFront(nil)
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

@main
struct ControlCenterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var manager = ControlCenterManager.shared
    
    var body: some Scene {
        WindowGroup {
            ControlCenterView(manager: manager)
                .onAppear {
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

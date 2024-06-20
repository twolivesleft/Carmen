//
//  CarmenApp.swift
//  Carmen
//
//  Created by Sim Saens on 12/10/2023.
//

import SwiftUI
import AppKit

@main
struct CarmenApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    
    @State private var translationStores: [String: TranslationStore] = [:]
    
    var body: some Scene {
        WindowGroup {
            ContentView(translationStores: $translationStores)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open...") {
                    openFile()
                }
                .keyboardShortcut("o", modifiers: [.command])
                
                Divider()
                
                ForEach(NSDocumentController.shared.recentDocumentURLs, id: \.self) { url in
                    Button(url.lastPathComponent) {
                        NSDocumentController.shared.noteNewRecentDocumentURL(url)
                        loadTranslationStores(from: url)
                    }
                }
            }
        }
    }
    
    func openFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.begin { (response) in
            if response == .OK, let url = panel.urls.first {
                loadTranslationStores(from: url)
            }
        }
    }

    private func loadTranslationStores(from url: URL) {
        translationStores = Carmen.loadTranslationStores(for: url)
    }
}

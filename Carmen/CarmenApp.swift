//
//  CarmenApp.swift
//  Carmen
//
//  Created by Sim Saens on 12/10/2023.
//

import SwiftUI
import AppKit
import OpenAI

@main
struct CarmenApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    
    @Environment(\.openWindow) private var openWindow
    
    @State private var translationStores: [String: TranslationStore] = [:]
    
    @AppStorage("OpenAIKey") static var openAIKey: String = ""
    static var openAI: OpenAI = OpenAI(apiToken: openAIKey)
    
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
                
                Button("Configure OpenAI") {
                    openWindow(id: "key-entry")
                }
                
                Divider()
                
                ForEach(NSDocumentController.shared.recentDocumentURLs, id: \.self) { url in
                    Button(url.lastPathComponent) {
                        NSDocumentController.shared.noteNewRecentDocumentURL(url)
                        loadTranslationStores(from: url)
                    }
                }
            }
        }
        
        Window("OpenAI Key", id: "key-entry") {
            KeyEntryView()
                .frame(minWidth: 400, minHeight: 100)
                .frame(maxWidth: 400, maxHeight: 100)
        }
        .defaultPosition(.topTrailing)
        .defaultSize(width: 400, height: 100)
        .onChange(of: Self.openAIKey) { oldValue, newValue in
            Self.openAI = OpenAI(apiToken: newValue)
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

struct KeyEntryView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Form {
            Section {
                TextField("OpenAI Key", text: CarmenApp.$openAIKey)
                
                Button("Close") {
                    dismiss()
                }
            }
        }
        .padding()
    }
}

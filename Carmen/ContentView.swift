//
//  ContentView.swift
//  Carmen
//
//  Created by Sim Saens on 12/10/2023.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import Foundation
import OpenAI

extension String: Identifiable {
    public var id: String {
        self
    }
}

struct ContentView: View {
    @Binding private var translationStores: [String: TranslationStore]
    @State private var selectedFile: String = ""
    @State private var selectedLanguage: String = ""
    @State private var selectedKey: String?
    @State private var translationProgress: (Double, Double)?
    
    init(translationStores: Binding<[String: TranslationStore]>) {
        self._translationStores = translationStores
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                if selectedFile != "" {
                    Picker("Select File", selection: $selectedFile) {
                        ForEach(translationStores.keys.sorted(), id: \.self) { file in
                            Text(file)
                                .tag(file)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 300)
                    .disabled(translationStores.keys.isEmpty)
                }
                
                // Only display the language picker if a file is selected
                if let store = translationStores[selectedFile], selectedLanguage != "" {
                    Picker("Select Language", selection: $selectedLanguage) {
                        ForEach(store.otherTranslations.keys.sorted(), id: \.self) { language in
                            Text(language)
                                .tag(language)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 300)
                    .disabled(store.otherTranslations.keys.isEmpty)
                    
                    Button("Translate Missing") {
                        Task { @MainActor in
                            await store.translateAllMissingStrings(to: selectedLanguage) { done, remaining in
                                if remaining > 0 {
                                    translationProgress = (done, remaining)
                                } else {
                                    translationProgress = nil
                                }
                            }
                        }
                    }
                    
                    Button("Copy to Clipboard") {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(store.stringsForLanguage(language: selectedLanguage), forType: .string)
                    }
                }
                
                if let translationProgress {
                    ProgressView(value: translationProgress.0, total: translationProgress.1)
                }
            }
            .padding([.leading,.trailing,.top])
            
            if let store = translationStores[selectedFile] {
                Table(store.englishStrings.keys.sorted(), selection: $selectedKey) {
                    TableColumn("Key") { key in
                        Text(key)
                    }
                    
                    TableColumn("English") { key in
                        Text(store.englishStrings[key] ?? "")
                    }
                    
                    TableColumn("Translation") { key in
                        if selectedLanguage.isEmpty {
                            EmptyView()
                        } else if let translations = store.otherTranslations[selectedLanguage] {
                            if let translation = translations[key] {
                                Text(translation)
                                    .contextMenu {
                                        Button("Copy") {
                                            let pasteboard = NSPasteboard.general
                                            pasteboard.clearContents()
                                            pasteboard.setString("\"\(key)\" = \"\(translation)\";", forType: .string)
                                        }
                                        
                                        Button("Remove Translation") {
                                            store.removeTranslation(for: key, language: selectedLanguage)
                                        }
                                    }
                            } else {
                                Text("Missing Translation")
                                    .bold()
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }
                .frame(minWidth: 800, maxWidth: .infinity)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers -> Bool in
            providers.first?.loadDataRepresentation(forTypeIdentifier: "public.file-url", completionHandler: { (data, error) in
                if let data = data, let urlString = String(data: data, encoding: .utf8), let url = URL(string: urlString) {
                    // Load translation stores using the new function
                    translationStores = loadTranslationStores(for: url)
                    selectedFile = translationStores.keys.sorted().first ?? ""
                    selectedLanguage = translationStores[selectedFile]?.otherTranslations.keys.sorted().first ?? ""
                }
            })
            return true
        }
    }
}

//#Preview {
//    ContentView()
//}
extension TranslationStore {
    func removeTranslation(for key: String, language: String) {
        otherTranslations[language]?[key] = nil
    }
}

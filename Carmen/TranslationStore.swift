//
//  TranslationStore.swift
//  Carmen
//
//  Created by Sim Saens on 24/10/2023.
//

import SwiftUI
import OpenAI

func loadTranslationStores(for directoryURL: URL) -> [String: TranslationStore] {
    let fileManager = FileManager.default
    var translationStores: [String: TranslationStore] = [:]

    do {
        let languageFolders = try fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        for folder in languageFolders where folder.pathExtension == "lproj" {
            let stringsFiles = try fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            for file in stringsFiles where file.pathExtension == "strings" {
                let fileName = file.lastPathComponent

                // Create a new TranslationStore for each unique .strings file
                if translationStores[fileName] == nil {
                    let newStore = TranslationStore(name: fileName)
                    newStore.loadData(from: directoryURL)
                    translationStores[fileName] = newStore
                }
            }
        }
    } catch {
        print("Error reading directory contents: \(error)")
    }

    return translationStores
}

func reloadTranslationStore(for directoryURL: URL, translationStore: TranslationStore, language: String) {
    translationStore.loadData(from: directoryURL, language: language)
}

func saveTranslationStore(for directoryURL: URL, translationStore: TranslationStore, language: String) {
    translationStore.saveData(to: directoryURL, language: language)
}

@Observable
final class TranslationStore {
    let BOMs: [String.Encoding : [UInt8]] = [
        .utf8: [0xEF, 0xBB, 0xBF],
        .utf16BigEndian: [0xFE, 0xFF],
        .utf16LittleEndian: [0xFF, 0xFE]
    ]
    
    let fileName: String
    var keyOrder: [String] = []
    var englishStrings: [String: String] = [:]
    var otherTranslations: [String: [String: String]] = [:]
    var encoding: String.Encoding = .utf8
    var hasBOM: Bool = false
    
    init(name: String) {
        fileName = name
    }
    
    static var preamble: [ChatQuery.ChatCompletionMessageParam] {
        [
            .system(.init(content: "You are a professional iOS app translator. You specialize in apps for graphic design and programming. You will be provided with a string, its associated localization key, and target language code. You are to simply reply with the translation of the string into that target language — NO OTHER TEXT")),
            .system(.init(content: "Some brand names within the app should not be translated, such as 'Air Code', 'Codea'")),
            .system(.init(content: "DO NOT translate text within `backticks` as this refers to code")),
            .system(.init(content: "DO NOT translate stuff that looks like Lua code (but string variables within the code text may be translated)")),
            .user(.init(content: .string("Key: \"IMPORT_PROJECT_ALERT_ERROR_MESSAGE\", String: \"An error occurred during import. %@\", Language: ja"))),
            .assistant(.init(content: "インポート中にエラーが発生しました。%@")),
            .user(.init(content: .string("Key: \"PROJECT_USER_DID_COPY_INFO\", String: \"The contents of project '%@' have been copied to the clipboard\", Language: de"))),
            .assistant(.init(content: "Die Inhalte des Projekts \"%@\" wurden in die Zwischenablage kopiert")),
        ]
    }
    
    func translateAllMissingStrings(to language: String, progress: @escaping (Double, Double)->Void) async throws {
        guard let otherLanguageStrings = otherTranslations[language] else {
            return
        }
        
        // Get the missing keys
        let missingKeys = englishStrings.keys.sorted().filter { key in
            return otherLanguageStrings[key] == nil
        }
        
        progress(0, Double(missingKeys.count))

        for (index, key) in missingKeys.enumerated() {
            let translatedValue = try await translate(key: key, to: language)
            
            if let value = translatedValue {
                otherTranslations[language]?[key] = value
                                    
                if (index + 1) < missingKeys.count {
                    progress(Double(index + 1), Double(missingKeys.count))
                } else {
                    progress(0,0)
                }
            }
        }
    }
    
    func translate(key: String, to language: String) async throws -> String? {
        guard let english = englishStrings[key] else { return nil }
        
        let query = ChatQuery(messages: Self.preamble + [
            .user(.init(content: .string("Key: \"\(key)\", String: \"\(english)\", Language: \(language)")))
        ], model: .gpt4_o)
        
        let result = try await CarmenApp.openAI.chats(query: query)
        
        return result.choices.first?.message.content?.string
    }
    
    func stringsForLanguage(language: String) -> String {
        guard let otherLanguageStrings = otherTranslations[language] else {
            return ""
        }
        
        return keyOrder.map {
            "\"\($0)\" = \"\(otherLanguageStrings[$0]!)\";"
        }.joined(separator: "\n")
    }
    
    func loadData(from path: URL, language: String? = nil) {
        let fileManager = FileManager.default
        
        do {
            let folders = try fileManager.contentsOfDirectory(at: path, includingPropertiesForKeys: nil)
            for folder in folders {
                if folder.pathExtension == "lproj" {
                    let lang = folder.lastPathComponent.replacingOccurrences(of: ".lproj", with: "")
                    let stringsPath =
                    folder.appending(component: fileName)
                    
                    if (lang == "en" || lang == "Base") && language == nil {
                        let content = loadFile(url: stringsPath)
                        englishStrings = parseStrings(content: content)
                        keyOrder = parseStringsKeys(content: content)
                    } else {
                        if language == nil || language == lang {
                            otherTranslations[lang] = parseStrings(content: loadFile(url: stringsPath))
                        }
                    }
                }
            }
        } catch {
            print("Error reading directory contents: \(error)")
        }
    }
    
    func exportStrings(_ strings: [String: String]) -> String {
        var output = ""
        let sortedKeys = strings.keys.sorted()
        for key in sortedKeys {
            if let value = strings[key] {
                output += "\"\(key)\" = \"\(value)\";\n"
            }
        }
        return output
    }
    
    func saveData(to path: URL, language: String) {
        let fileManager = FileManager.default
        do {
            let folders = try fileManager.contentsOfDirectory(at: path, includingPropertiesForKeys: nil)
            for folder in folders {
                if folder.pathExtension == "lproj" {
                    let lang = folder.lastPathComponent.replacingOccurrences(of: ".lproj", with: "")
                    let stringsPath =
                    folder.appending(component: fileName)
                    
                    if lang == language, let strings = otherTranslations[lang] {
                        let content = exportStrings(strings)
                        saveFile(url: stringsPath, content: content)
                    }
                }
            }
        } catch {
            print("Error writing directory contents: \(error)")
        }
    }
    
    func detectBOM(data: Data) {
        if let BOM = BOMs[encoding] {
            hasBOM = data.starts(with: BOM)
        }
    }
    
    func loadFile(url: URL) -> String {
        let fileManager = FileManager.default
        guard let data = fileManager.contents(atPath: url.path) else {
            return ""
        }

        // Heuristic approach: Check for the presence of null bytes which might indicate UTF-16
        let likelyUTF16 = data.contains(0x00)
        
        // Attempt to decode as UTF-16 if likely UTF-16, otherwise, default to UTF-8
        if likelyUTF16 {
            if let contentUTF16LE = String(data: data, encoding: .utf16LittleEndian) {
                encoding = .utf16LittleEndian
                detectBOM(data: data)
                return contentUTF16LE
            } else if let contentUTF16BE = String(data: data, encoding: .utf16BigEndian) {
                encoding = .utf16BigEndian
                detectBOM(data: data)
                return contentUTF16BE
            }
        }
        
        // Fallback or default to UTF-8
        detectBOM(data: data)
        return String(data: data, encoding: .utf8) ?? "Unable to decode the file."
    }
    
    func saveFile(url: URL, content: String) {
        do {
            var data = Data()
            
            if hasBOM, let BOM = BOMs[encoding] {
                data.append(contentsOf: BOM)
            }
            
            if let encoded = content.data(using: encoding) {
                data.append(encoded)
            }
            
            try data.write(to: url)
        } catch {
            print("Error writing file contents: \(error)")
        }
    }
    
    func parseStrings(content: String) -> [String: String] {
        // Regex pattern to match lines with key-value pairs and ignore comments and other non-pair content
        let regexPattern = #""([^"\n]*)"[\s]*=[\s]*"((?:[^"]|"(?!\s*;))*?)"[\s]*;"#
        let regex = try! NSRegularExpression(pattern: regexPattern)

        var stringsDict: [String: String] = [:]

        let matches = regex.matches(in: content, options: [], range: NSRange(location: 0, length: content.utf16.count))
        for match in matches {
            if let keyRange = Range(match.range(at: 1), in: content),
               let valueRange = Range(match.range(at: 2), in: content) {
                let key = String(content[keyRange])
                let value = String(content[valueRange])
                stringsDict[key] = value
            }
        }

        return stringsDict
    }

    
    func parseStringsKeys(content: String) -> [String] {
        let regexPattern = #""([^"\n]*)"[\s]*=[\s]*"((?:[^"]|"(?!\s*;))*?)"[\s]*;"#
        let regex = try! NSRegularExpression(pattern: regexPattern)

        let matches = regex.matches(in: content, options: [], range: NSRange(location: 0, length: content.utf16.count))
                
        return matches.compactMap { match in
            if let keyRange = Range(match.range(at: 1), in: content) {
                return String(content[keyRange])
            }
            return nil
        }
    }
}

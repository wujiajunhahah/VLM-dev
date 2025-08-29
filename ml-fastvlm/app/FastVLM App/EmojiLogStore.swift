//
// For licensing see accompanying LICENSE file.
// Copyright (C) 2025 Apple Inc. All Rights Reserved.
//

import Foundation

struct EmojiEntry: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    let timestamp: Date
    let emoji: String
}

@Observable
final class EmojiLogStore {
    private(set) var entries: [EmojiEntry] = []

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("emoji_log.json")
    }()

    init() {
        load()
    }

    func add(entry: EmojiEntry) {
        entries.append(entry)
        save()
    }

    func groupedByHour(for date: Date = Date()) -> [(hour: Int, emojis: [String])]{
        let cal = Calendar.current
        let sameDay = entries.filter { cal.isDate($0.timestamp, inSameDayAs: date) }
        var map: [Int: [String]] = [:]
        for e in sameDay {
            let h = cal.component(.hour, from: e.timestamp)
            map[h, default: []].append(e.emoji)
        }
        return (0..<24).map { h in (h, map[h] ?? []) }
    }

    func save() {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("EmojiLogStore save error: \(error)")
        }
    }

    func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode([EmojiEntry].self, from: data)
            entries = decoded
        } catch {
            print("EmojiLogStore load error: \(error)")
        }
    }
}







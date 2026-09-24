import Foundation
import Testing

@testable import Tatami

@MainActor
struct ConfigWatcherTests {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "tatami-watch-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Polls until `condition` holds or about two seconds pass.
    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<40 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    @Test func noticesAtomicSavesAndCoalescesBursts() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var changes = 0
        let watcher = ConfigWatcher(directory: directory, debounce: .milliseconds(100)) { changes += 1 }
        #expect(watcher.start())

        // Editors save by writing elsewhere and renaming over the file; several writes in a burst.
        for index in 0..<3 {
            try Data("{\"n\": \(index)}".utf8).write(to: directory.appending(path: "config.json"), options: .atomic)
        }
        #expect(await eventually { changes >= 1 })
        try? await Task.sleep(for: .milliseconds(300))
        #expect(changes == 1)
        watcher.stop()
    }

    @Test func missingDirectoryCannotBeWatched() {
        let watcher = ConfigWatcher(directory: URL(filePath: "/nonexistent-\(UUID())")) {}
        #expect(!watcher.start())
    }
}

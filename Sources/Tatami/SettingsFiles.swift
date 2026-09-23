import Foundation
import TatamiCore

/// Reads and writes `config.json` and `state.json` in Tatami's config directory.
struct SettingsFiles {
    let directory: URL

    static let standard = SettingsFiles(
        directory: FileManager.default.homeDirectoryForCurrentUser.appending(
            path: ".config/tatami", directoryHint: .isDirectory))

    var configURL: URL { directory.appending(path: "config.json") }
    var stateURL: URL { directory.appending(path: "state.json") }

    /// Loads the config, first writing the defaults if the file does not exist.
    func loadConfig() -> Result<Config, ConfigError> {
        do {
            try writeDefaultConfigIfMissing()
            let data = try Data(contentsOf: configURL)
            return Result { () throws(ConfigError) in try Config.decode(from: data) }
        } catch let error as ConfigError {
            return .failure(error)
        } catch {
            return .failure(.invalidValue("cannot read \(configURL.path): \(error.localizedDescription)"))
        }
    }

    func writeDefaultConfigIfMissing() throws {
        guard !FileManager.default.fileExists(atPath: configURL.path) else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Config.defaultFileContents().write(to: configURL, options: .atomic)
    }

    /// Returns empty state if the file is missing or unreadable.
    func loadState() -> GridState {
        guard let data = try? Data(contentsOf: stateURL) else { return GridState() }
        return (try? JSONDecoder().decode(GridState.self, from: data)) ?? GridState()
    }

    func saveState(_ state: GridState) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: stateURL, options: .atomic)
    }
}

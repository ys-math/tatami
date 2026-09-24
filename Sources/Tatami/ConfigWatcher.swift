import Foundation

/// Calls `onChange` shortly after anything in a directory changes.
///
/// Watches the directory rather than the file because editors often save by
/// writing a new file and renaming it over the old one, which would orphan a
/// watch on the file itself. Bursts of events are coalesced.
@MainActor
final class ConfigWatcher {
    private let directory: URL
    private let debounce: Duration
    private let onChange: @MainActor () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var pending: Task<Void, Never>?

    init(directory: URL, debounce: Duration = .milliseconds(200), onChange: @escaping @MainActor () -> Void) {
        self.directory = directory
        self.debounce = debounce
        self.onChange = onChange
    }

    /// Returns `false` if the directory cannot be watched (e.g. it does not exist).
    @discardableResult
    func start() -> Bool {
        guard source == nil else { return true }
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return false }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: [.write, .rename, .delete, .extend], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.scheduleChange()
            }
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        self.source = source
        return true
    }

    func stop() {
        pending?.cancel()
        source?.cancel()
        source = nil
    }

    private func scheduleChange() {
        pending?.cancel()
        pending = Task { @MainActor [weak self, debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            self?.onChange()
        }
    }
}

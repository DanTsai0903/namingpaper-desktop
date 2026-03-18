import Foundation

/// Watches the papers directory for external filesystem changes using FSEvents.
/// When changes are detected, triggers a debounced callback (used to auto-sync).
class DirectoryMonitor {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.namingpaper.directorymonitor", qos: .utility)
    private var debounceWork: DispatchWorkItem?
    private let debounceInterval: TimeInterval = 1.5

    var onChange: (() -> Void)?

    func start(path: String) {
        stop()

        guard FileManager.default.fileExists(atPath: path) else { return }

        let pathCF = path as CFString
        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        guard let stream = FSEventStreamCreate(
            nil,
            DirectoryMonitor.callback,
            &context,
            [pathCF] as CFArray,
            FSEventsGetCurrentEventId(),
            0.5,  // latency in seconds — FSEvents batches events within this window
            UInt32(
                kFSEventStreamCreateFlagUseCFTypes |
                kFSEventStreamCreateFlagFileEvents |
                kFSEventStreamCreateFlagIgnoreSelf
            )
        ) else { return }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    func stop() {
        debounceWork?.cancel()
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
    }

    deinit {
        stop()
    }

    // MARK: - FSEvents Callback

    private static let callback: FSEventStreamCallback = {
        _, info, _, _, _, _ in
        guard let info else { return }
        let monitor = Unmanaged<DirectoryMonitor>.fromOpaque(info).takeUnretainedValue()
        monitor.handleEvent()
    }

    private func handleEvent() {
        // Debounce: cancel previous pending work, schedule new one.
        // This collapses rapid bursts (e.g. batch file moves) into a single sync.
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.onChange?()
        }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }
}

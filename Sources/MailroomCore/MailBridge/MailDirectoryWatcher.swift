import CoreServices
import Foundation

/// 监听 `~/Library/Mail/V*/MailData`（捕获 `Envelope Index-wal` 更新），防抖后通知上层增量同步。
public final class MailDirectoryWatcher: @unchecked Sendable {
    private let watchedPath: String
    private let debounceInterval: TimeInterval
    private let onChange: @Sendable () -> Void

    private let queue = DispatchQueue(label: "dev.mailroom.deck.fsevents", qos: .utility)
    private var stream: FSEventStreamRef?
    private var pendingWorkItem: DispatchWorkItem?
    private var fallbackTimer: DispatchSourceTimer?

    public init(
        watchedPath: String,
        debounceInterval: TimeInterval = 0.32,
        onChange: @escaping @Sendable () -> Void
    ) {
        self.watchedPath = watchedPath
        self.debounceInterval = debounceInterval
        self.onChange = onChange
    }

    public func start() {
        queue.async { [weak self] in
            self?.setupOnQueue()
        }
    }

    public func stop() {
        queue.sync {
            pendingWorkItem?.cancel()
            pendingWorkItem = nil
            fallbackTimer?.cancel()
            fallbackTimer = nil
            if let stream {
                FSEventStreamStop(stream)
                FSEventStreamInvalidate(stream)
                FSEventStreamRelease(stream)
                self.stream = nil
            }
        }
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        fallbackTimer?.cancel()
    }

    private func setupOnQueue() {
        guard stream == nil else { return }

        let unmanagedSelf = Unmanaged.passUnretained(self)
        var context = FSEventStreamContext(
            version: 0,
            info: unmanagedSelf.toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<MailDirectoryWatcher>.fromOpaque(info).takeUnretainedValue()
            guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else {
                watcher.scheduleDebouncedTrigger()
                return
            }
            let relevant = (0..<min(numEvents, paths.count)).contains { idx in
                let p = paths[idx]
                return p.contains("Envelope Index") || p.hasSuffix(".emlx") || p.contains("ExternalUpdates")
            }
            if relevant {
                watcher.scheduleDebouncedTrigger()
            }
        }

        let pathsToWatch = [watchedPath] as CFArray
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes
            | kFSEventStreamCreateFlagFileEvents
            | kFSEventStreamCreateFlagNoDefer
        )

        if let created = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.25,
            flags
        ) {
            self.stream = created
            FSEventStreamSetDispatchQueue(created, queue)
            FSEventStreamStart(created)
        }

        // 10s 极轻量兜底心跳，防止偶发原地页写未触发文件级事件
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 10.0, repeating: 10.0, leeway: .seconds(2))
        timer.setEventHandler { [weak self] in
            self?.onChange()
        }
        timer.resume()
        self.fallbackTimer = timer
    }

    private func scheduleDebouncedTrigger() {
        pendingWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.onChange()
        }
        pendingWorkItem = item
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: item)
    }
}

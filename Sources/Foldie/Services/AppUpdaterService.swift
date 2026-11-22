import AppKit
import Foundation

struct AvailableRelease: Sendable, Equatable {
    let version: String
    let tagName: String
    let downloadURL: URL
    let releasePageURL: URL
    let notes: String
    let assetSizeBytes: Int64
}

enum UpdateState: Equatable, Sendable {
    case idle
    case checking
    case upToDate(lastChecked: Date)
    case available(AvailableRelease)
    case downloading(version: String, progress: Double)
    case installing(version: String)
    case error(String)

    var availableRelease: AvailableRelease? {
        if case .available(let release) = self { return release }
        return nil
    }

    var isBusy: Bool {
        switch self {
        case .checking, .downloading, .installing:
            return true
        default:
            return false
        }
    }
}

private struct GitHubReleaseDTO: Decodable, Sendable {
    let tag_name: String
    let html_url: String
    let body: String?
    let draft: Bool?
    let prerelease: Bool?
    let assets: [GitHubAssetDTO]
}

private struct GitHubAssetDTO: Decodable, Sendable {
    let name: String
    let browser_download_url: String
    let size: Int64
}

/// Native zero-dependency GitHub Releases updater for Foldie.
/// Checks `temakubik/foldie` latest release, downloads the `.zip` with live progress,
/// validates the app bundle, atomically swaps `Foldie.app`, and relaunches.
@MainActor
final class AppUpdaterService: ObservableObject {
    static let repoSlug = "temakubik/foldie"
    static let latestReleaseAPI = URL(string: "https://api.github.com/repos/temakubik/foldie/releases/latest")!
    static let releasesPageURL = URL(string: "https://github.com/temakubik/foldie/releases/latest")!

    @Published private(set) var state: UpdateState = .idle
    @Published private(set) var lastCheckedDate: Date? = nil

    private var periodicTimer: Timer?
    private var activeTask: Task<Void, Never>?

    var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
    }

    func startAutoCheck(enabled: Bool) {
        stopAutoCheck()
        guard enabled else { return }

        // Check silently shortly after launch, then every 12 hours.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard let self else { return }
            self.checkForUpdates(userInitiated: false)
        }

        periodicTimer = Timer.scheduledTimer(withTimeInterval: 12 * 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.checkForUpdates(userInitiated: false)
            }
        }
    }

    func stopAutoCheck() {
        periodicTimer?.invalidate()
        periodicTimer = nil
    }

    func checkForUpdates(userInitiated: Bool) {
        if state.isBusy { return }
        if userInitiated {
            state = .checking
        }

        activeTask?.cancel()
        activeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                var request = URLRequest(url: Self.latestReleaseAPI)
                request.timeoutInterval = 15
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.setValue("Foldie/\(self.currentVersion)", forHTTPHeaderField: "User-Agent")

                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw NSError(domain: "FoldieUpdater", code: 1, userInfo: [NSLocalizedDescriptionKey: "Некорректный ответ сервера."])
                }
                guard (200..<300).contains(http.statusCode) else {
                    throw NSError(domain: "FoldieUpdater", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "GitHub вернул код \(http.statusCode)."])
                }

                let dto = try JSONDecoder().decode(GitHubReleaseDTO.self, from: data)
                let now = Date()
                self.lastCheckedDate = now

                if dto.draft == true || dto.prerelease == true {
                    self.state = .upToDate(lastChecked: now)
                    return
                }

                let remoteVersion = Self.normalizedVersion(dto.tag_name)
                if Self.compareVersions(remoteVersion, self.currentVersion) > 0,
                   let zipAsset = Self.selectZipAsset(from: dto.assets),
                   let downloadURL = URL(string: zipAsset.browser_download_url) {
                    let release = AvailableRelease(
                        version: remoteVersion,
                        tagName: dto.tag_name,
                        downloadURL: downloadURL,
                        releasePageURL: URL(string: dto.html_url) ?? Self.releasesPageURL,
                        notes: dto.body ?? "",
                        assetSizeBytes: zipAsset.size
                    )
                    self.state = .available(release)
                } else {
                    self.state = .upToDate(lastChecked: now)
                }
            } catch {
                if userInitiated {
                    self.state = .error("Не удалось проверить обновления: \(error.localizedDescription)")
                }
            }
        }
    }

    func installAvailableUpdate() {
        guard let release = state.availableRelease else { return }
        if case .downloading = state { return }
        if case .installing = state { return }

        state = .downloading(version: release.version, progress: 0)

        activeTask?.cancel()
        activeTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let stagingDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("foldie-update-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)

                let zipURL = stagingDir.appendingPathComponent("Foldie-\(release.version).zip")

                // Stream download with real progress updates
                var request = URLRequest(url: release.downloadURL)
                request.timeoutInterval = 120
                request.setValue("Foldie/\(self.currentVersion)", forHTTPHeaderField: "User-Agent")

                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    throw NSError(domain: "FoldieUpdater", code: 2, userInfo: [NSLocalizedDescriptionKey: "Не удалось скачать архив обновления."])
                }

                let expectedBytes = http.expectedContentLength > 0 ? http.expectedContentLength : max(release.assetSizeBytes, 1)
                FileManager.default.createFile(atPath: zipURL.path, contents: nil)
                let handle = try FileHandle(forWritingTo: zipURL)
                defer { try? handle.close() }

                var buffer = Data()
                buffer.reserveCapacity(65_536)
                var receivedBytes: Int64 = 0
                var lastProgressUpdate = Date.distantPast

                for try await byte in bytes {
                    buffer.append(byte)
                    if buffer.count >= 65_536 {
                        try handle.write(contentsOf: buffer)
                        receivedBytes += Int64(buffer.count)
                        buffer.removeAll(keepingCapacity: true)
                        let now = Date()
                        if now.timeIntervalSince(lastProgressUpdate) >= 0.08 {
                            lastProgressUpdate = now
                            let progress = min(0.99, Double(receivedBytes) / Double(expectedBytes))
                            self.state = .downloading(version: release.version, progress: progress)
                        }
                    }
                }
                if !buffer.isEmpty {
                    try handle.write(contentsOf: buffer)
                    receivedBytes += Int64(buffer.count)
                }
                try handle.close()

                self.state = .installing(version: release.version)

                // Extract zip off the main actor using macOS ditto
                let extractDir = stagingDir.appendingPathComponent("extracted", isDirectory: true)
                try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)

                let dittoExit = try await Self.runProcess(
                    executable: "/usr/bin/ditto",
                    arguments: ["-x", "-k", zipURL.path, extractDir.path]
                )
                guard dittoExit == 0 else {
                    throw NSError(domain: "FoldieUpdater", code: 3, userInfo: [NSLocalizedDescriptionKey: "Ошибка распаковки архива (код \(dittoExit))."])
                }

                // Locate and validate extracted Foldie.app
                let newAppURL = extractDir.appendingPathComponent("Foldie.app", isDirectory: true)
                let newBinaryURL = newAppURL.appendingPathComponent("Contents/MacOS/Foldie")
                guard FileManager.default.isExecutableFile(atPath: newBinaryURL.path),
                      let infoBundle = Bundle(url: newAppURL),
                      infoBundle.bundleIdentifier == "com.foldie.app" else {
                    throw NSError(domain: "FoldieUpdater", code: 4, userInfo: [NSLocalizedDescriptionKey: "Архив не содержит корректного Foldie.app."])
                }

                // Determine target destination (if running from a mounted DMG volume, install into /Applications)
                let currentBundleURL = Bundle.main.bundleURL
                let targetAppURL: URL
                if currentBundleURL.path.hasPrefix("/Volumes/") || !currentBundleURL.path.hasSuffix(".app") {
                    targetAppURL = URL(fileURLWithPath: "/Applications/Foldie.app", isDirectory: true)
                } else {
                    targetAppURL = currentBundleURL
                }

                let targetParent = targetAppURL.deletingLastPathComponent()
                guard FileManager.default.isWritableFile(atPath: targetParent.path) else {
                    throw NSError(
                        domain: "FoldieUpdater",
                        code: 5,
                        userInfo: [NSLocalizedDescriptionKey: "Нет прав на запись в \(targetParent.path). Перенесите Foldie.app в /Applications и повторите."]
                    )
                }

                // Launch a safe detached helper script that waits for our PID to exit, swaps atomically with backup rollback, and relaunches.
                let pid = ProcessInfo.processInfo.processIdentifier
                let helperScript = """
                PID="$1"
                SRC_APP="$2"
                DST_APP="$3"
                STAGE_DIR="$4"
                BACKUP_APP="${DST_APP}.foldie-backup"

                i=0
                while kill -0 "$PID" 2>/dev/null && [ $i -lt 60 ]; do
                    sleep 0.1
                    i=$((i + 1))
                done

                rm -rf "$BACKUP_APP"
                if [ -e "$DST_APP" ]; then
                    mv "$DST_APP" "$BACKUP_APP" || exit 1
                fi

                if mv "$SRC_APP" "$DST_APP"; then
                    rm -rf "$BACKUP_APP"
                    rm -rf "$STAGE_DIR"
                    open "$DST_APP"
                else
                    if [ -e "$BACKUP_APP" ]; then
                        mv "$BACKUP_APP" "$DST_APP"
                    fi
                    rm -rf "$STAGE_DIR"
                    exit 1
                fi
                """

                let swapProc = Process()
                swapProc.executableURL = URL(fileURLWithPath: "/bin/sh")
                swapProc.arguments = [
                    "-c",
                    helperScript,
                    "foldie-updater",
                    String(pid),
                    newAppURL.path,
                    targetAppURL.path,
                    stagingDir.path
                ]
                swapProc.standardOutput = FileHandle.nullDevice
                swapProc.standardError = FileHandle.nullDevice
                try swapProc.run()

                // Terminate current Foldie instance cleanly so helper completes swap & relaunches new version
                try? await Task.sleep(nanoseconds: 150_000_000)
                NSApp.terminate(nil)
            } catch {
                self.state = .error("Ошибка обновления: \(error.localizedDescription)")
            }
        }
    }

    func openReleasePage() {
        let url = state.availableRelease?.releasePageURL ?? Self.releasesPageURL
        NSWorkspace.shared.open(url)
    }

    // MARK: - Helpers

    private static func selectZipAsset(from assets: [GitHubAssetDTO]) -> GitHubAssetDTO? {
        #if arch(arm64)
        let preferredArch = "arm64"
        #else
        let preferredArch = "x86_64"
        #endif

        if let exact = assets.first(where: { $0.name.lowercased().hasSuffix(".zip") && $0.name.lowercased().contains(preferredArch) }) {
            return exact
        }
        return assets.first(where: { $0.name.lowercased().hasSuffix(".zip") && $0.name.lowercased().contains("foldie") })
            ?? assets.first(where: { $0.name.lowercased().hasSuffix(".zip") })
    }

    static func normalizedVersion(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "^[vV]", with: "", options: .regularExpression)
    }

    static func compareVersions(_ lhs: String, _ rhs: String) -> Int {
        let lParts = normalizedVersion(lhs).split(separator: ".").map { Int($0) ?? 0 }
        let rParts = normalizedVersion(rhs).split(separator: ".").map { Int($0) ?? 0 }
        let count = max(lParts.count, rParts.count)
        for idx in 0..<count {
            let l = idx < lParts.count ? lParts[idx] : 0
            let r = idx < rParts.count ? rParts[idx] : 0
            if l != r { return l < r ? -1 : 1 }
        }
        return 0
    }

    private static func runProcess(executable: String, arguments: [String]) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: executable)
                proc.arguments = arguments
                do {
                    try proc.run()
                    proc.waitUntilExit()
                    continuation.resume(returning: proc.terminationStatus)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

//
//  UpgradeChecker.swift
//  Deboogey
//
//  Created by Théo De Roy on 30/01/2026.
//

import Foundation; import AppKit; import Combine

class UpgradeChecker: ObservableObject {
    static let shared = UpgradeChecker()
    let manualCheck = PassthroughSubject<Void,Never>()
    let auxiliaryArchiveCompleted = PassthroughSubject<String,Never>()
    @Published var upgradeAvailable: Bool = false
    @Published var isUpdating: Bool = false
    @Published var updateProgress: Double = 0
    @Published var updateStep: String = ""
    @Published var latestVersion: String = ""
    @Published var pendingUpdateURL: URL?
    private var downloadProgressObservation: NSKeyValueObservation?
    private init() {}

    struct AppVersion: Comparable, CustomStringConvertible {
        enum Channel: String { case release = "Release"; case `internal` = "Internal"; case unknown = "Unknown" }
        let channel: Channel; let major: Int; let minor: Int; let patch: Int; let buildNumber: Int; let originalString: String
        var description: String { return originalString }
        static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
            if lhs.channel != rhs.channel { return true }
            switch lhs.channel {
            case .internal: return lhs.buildNumber < rhs.buildNumber
            case .release:
                if lhs.major != rhs.major { return lhs.major < rhs.major }
                if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
                if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }
                return lhs.buildNumber < rhs.buildNumber
            default: return false
            }
        }
        static func parse(from string: String) -> AppVersion {
            let clean = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if clean.lowercased().starts(with: "internal") || clean.lowercased().starts(with: "int-") {
                let components = clean.components(separatedBy: CharacterSet.decimalDigits.inverted)
                let numStr = components.first(where: { !$0.isEmpty }) ?? "0"
                return AppVersion(channel: .internal, major: 0, minor: 0, patch: 0, buildNumber: Int(numStr) ?? 0, originalString: clean)
            }
            var verStr = clean; let lower = verStr.lowercased()
            if lower.hasPrefix("release") { verStr = String(verStr.dropFirst(7)) }
            else if lower.hasPrefix("rel-") { verStr = String(verStr.dropFirst(4)) }
            else if lower.hasPrefix("v") { verStr = String(verStr.dropFirst(1)) }
            verStr = verStr.trimmingCharacters(in: .whitespaces)
            let parts = verStr.split(separator: ".")
            let maj = parts.count > 0 ? Int(parts[0]) ?? 0 : 0
            let min = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
            let pat = parts.count > 2 ? Int(parts[2]) ?? 0 : 0
            return AppVersion(channel: .release, major: maj, minor: min, patch: pat, buildNumber: 0, originalString: clean)
        }
    }

    private var currentAppVersion: AppVersion {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        if short == "Release" { return AppVersion.parse(from: "Release \(build)") }
        if short == "Internal" { return AppVersion.parse(from: "Internal \(build)") }
        return AppVersion.parse(from: short)
    }

    func requestManualCheck() { manualCheck.send() }
    
    func checkForUpdates(force: Bool = false, clearIfNone: Bool = false, completion: ((Bool)->Void)? = nil) {
        guard NetworkMonitor.shared.isConnected else {
            DispatchQueue.main.async {
                if clearIfNone {
                    self.latestVersion = ""
                    self.pendingUpdateURL = nil
                    self.upgradeAvailable = false
                }
                completion?(false)
            }
            return
        }
        
        if !force && UserDefaults.standard.bool(forKey: "hideUpgradeAlerts") { DispatchQueue.main.async { completion?(false) }; return }
        
        let local = currentAppVersion
        let desiredChannelRaw = UserDefaults.standard.string(forKey: "upgradeChannel")
        var targetChannel = local.channel
        if let raw = desiredChannelRaw {
            if raw.caseInsensitiveCompare("Internal") == .orderedSame { targetChannel = .internal }
            else if raw.caseInsensitiveCompare("Release") == .orderedSame { targetChannel = .release }
        }
        
        guard let url = URL(string: "https://api.github.com/repos/theoderoy/Deboogey/releases") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self, let data = data, error == nil else {
                DispatchQueue.main.async {
                    if clearIfNone { self?.latestVersion = ""; self?.pendingUpdateURL = nil; self?.upgradeAvailable = false }
                    completion?(false)
                }
                return
            }
            do {
                if let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                    
                    let releases = jsonArray.compactMap { r -> (AppVersion, [String: Any])? in
                        guard let t = r["tag_name"] as? String else { return nil }
                        let v = AppVersion.parse(from: t)
                        return v.channel == targetChannel ? (v, r) : nil
                    }

                    if let (latest, json) = releases.sorted(by: { $0.0 < $1.0 }).last, latest > local {
                        DispatchQueue.main.async {
                            self.latestVersion = latest.originalString
                            if let assets = json["assets"] as? [[String: Any]],
                               let asset = assets.first(where: { ($0["name"] as? String) == "Deboogey.aar" }),
                               let dlStr = asset["browser_download_url"] as? String, let dlUrl = URL(string: dlStr) {
                                self.pendingUpdateURL = dlUrl; self.upgradeAvailable = true; completion?(true)
                            } else {
                                if clearIfNone { self.latestVersion = ""; self.pendingUpdateURL = nil; self.upgradeAvailable = false }
                                completion?(false)
                            }
                        }
                    } else {
                        DispatchQueue.main.async {
                            if clearIfNone { self.latestVersion = ""; self.pendingUpdateURL = nil; self.upgradeAvailable = false }
                            completion?(false)
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        if clearIfNone { self.latestVersion = ""; self.pendingUpdateURL = nil; self.upgradeAvailable = false }
                        completion?(false)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    if clearIfNone { self.latestVersion = ""; self.pendingUpdateURL = nil; self.upgradeAvailable = false }
                    completion?(false)
                }
                print("Check failed: \(error)")
            }
        }.resume()
    }

    func proceedWithUpdate() {
        guard let url = pendingUpdateURL else { return }
        let version = latestVersion
        isUpdating = true
        beginUpdateStep("Preparing upgrade")
        downloadAndInstall(from: url, version: version)
    }
    var formattedLatestVersion: String {
        let v = AppVersion.parse(from: latestVersion)
        switch v.channel {
        case .release:
            var str = "\(v.major)"
            if v.minor > 0 || v.patch > 0 {
                str += ".\(v.minor)"
            }
            if v.patch > 0 {
                str += ".\(v.patch)"
            }
            return L10n.f("Release %@", str)
        case .internal:
            return L10n.f("Internal %@", "\(v.buildNumber)")
        default:
            return latestVersion
        }
    }

    func cleanUpOldApp() {
        if !UserDefaults.standard.bool(forKey: "deleteBackupOnStartup") { return }
        let oldPath = Bundle.main.bundlePath + ".old"
        if FileManager.default.fileExists(atPath: oldPath) {
            try? FileManager.default.removeItem(atPath: oldPath)
            print("Cleaned up old app backup.")
        }
    }

    private func downloadAndInstall(from url: URL, version: String) {
        print("Downloading: \(url)")
        beginUpdateStep("Downloading upgrade")
        let task = URLSession.shared.downloadTask(with: url) { localUrl, _, error in
            DispatchQueue.main.async {
                self.downloadProgressObservation = nil
            }
            guard let localUrl = localUrl, error == nil else { self.finishUpdateFlow(); return }
            self.completeUpdateStep()
            do {
                if DebugVariables.auxiliaryUpgrades {
                    self.beginUpdateStep("Archiving upgrade")
                    let archiveName = try self.archiveDownloadedUpdate(at: localUrl, version: version)
                    self.completeUpdateStep()
                    DispatchQueue.main.async {
                        self.auxiliaryArchiveCompleted.send(archiveName)
                    }
                    self.finishUpdateFlow()
                    return
                }

                self.beginUpdateStep("Preparing upgrade")
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                let archivePath = tempDir.appendingPathComponent("Deboogey.aar")
                try FileManager.default.moveItem(at: localUrl, to: archivePath)
                self.completeUpdateStep()
                self.beginUpdateStep("Extracting upgrade")
                if self.extractArchive(at: archivePath, to: tempDir) {
                    self.completeUpdateStep()
                    self.installUpdate(from: tempDir)
                } else {
                    self.finishUpdateFlow()
                }
            } catch { self.finishUpdateFlow(); print("Update failed: \(error)") }
        }
        downloadProgressObservation = task.progress.observe(\.fractionCompleted, options: [.new]) { [weak self] progress, _ in
            DispatchQueue.main.async {
                self?.updateProgress = progress.fractionCompleted
            }
        }
        task.resume()
    }

    private func archiveDownloadedUpdate(at localUrl: URL, version: String) throws -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "dd_MM_yy"

        let archiveName = auxiliaryArchiveName(version: version, date: dateFormatter.string(from: Date()))
        let destination = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent(archiveName)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: localUrl, to: destination)
        print("Auxiliary upgrade package: \(destination.path)")
        return archiveName
    }

    private func auxiliaryArchiveName(version: String, date: String) -> String {
        let parsedVersion = AppVersion.parse(from: version)
        let name: String
        switch parsedVersion.channel {
        case .internal:
            name = "DEBOOGEY_INTERNAL_\(parsedVersion.buildNumber)-\(date)"
        case .release:
            let releaseVersion = [parsedVersion.major, parsedVersion.minor, parsedVersion.patch]
                .map(String.init)
                .joined(separator: "_")
            name = "DEBOOGEY_RELEASE_\(releaseVersion)-\(date)"
        default:
            name = "DEBOOGEY_\(version.uppercased())-\(date)"
        }
        return "\(sanitizedArchiveName(name)).aar"
    }

    private func sanitizedArchiveName(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:")
            .union(.newlines)
            .union(.controlCharacters)
            .union(.whitespaces)
        return name.components(separatedBy: invalidCharacters).filter { !$0.isEmpty }.joined(separator: "_")
    }

    private func extractArchive(at archiveUrl: URL, to destination: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/aa")
        process.arguments = ["extract", "-i", archiveUrl.path, "-d", destination.path]
        do { try process.run(); process.waitUntilExit(); return process.terminationStatus == 0 }
        catch { print("Extraction failed: \(error)"); return false }
    }

    private func installUpdate(from sourceDir: URL) {
        let appName = "Deboogey.app"; let newPath = sourceDir.appendingPathComponent(appName)
        guard FileManager.default.fileExists(atPath: newPath.path) else {
            finishUpdateFlow()
            print("AppName not found")
            return
        }
        let currentPath = Bundle.main.bundlePath; let oldPath = currentPath + ".old"
        do {
            beginUpdateStep("Installing upgrade")
            if FileManager.default.fileExists(atPath: oldPath) { try FileManager.default.removeItem(atPath: oldPath) }
            try FileManager.default.moveItem(atPath: currentPath, toPath: oldPath)
            try FileManager.default.moveItem(at: newPath, to: URL(fileURLWithPath: currentPath))
            completeUpdateStep()
            DispatchQueue.main.async { NSApp.terminate(nil) }
        } catch { finishUpdateFlow(); print("Install failed: \(error)") }
    }

    private func beginUpdateStep(_ step: String) {
        DispatchQueue.main.async {
            self.updateStep = step
            self.updateProgress = 0
        }
    }

    private func completeUpdateStep() {
        DispatchQueue.main.async {
            self.updateProgress = 1
        }
    }

    private func finishUpdateFlow() {
        DispatchQueue.main.async {
            self.isUpdating = false
            self.updateProgress = 0
            self.updateStep = ""
            self.downloadProgressObservation = nil
        }
    }
}

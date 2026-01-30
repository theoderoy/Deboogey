
import Foundation
import AppKit
import Combine

class UpgradeChecker: ObservableObject {
    static let shared = UpgradeChecker()
    @Published var upgradeAvailable: Bool = false
    @Published var latestVersion: String = ""
    
    @Published var pendingUpdateURL: URL?
    
    private init() {}
    
    func checkForUpdates() {
        if UserDefaults.standard.bool(forKey: "hideUpgradeAlerts") { return }
        
        // Default to "Release"
        let channel = UserDefaults.standard.string(forKey: "upgradeChannel") ?? "Release"
        let isInternal = channel == "Internal"
        
        let endpoint = isInternal ? "releases" : "releases/latest"
        guard let url = URL(string: "https://api.github.com/repos/theoderoy/Deboogey/\(endpoint)") else { return }
        
        URLSession.shared.dataTask(with: url) { data, _, error in
            guard let data = data, error == nil else { return }
            
            do {
                var targetRelease: [String: Any]?
                
                if isInternal {
                    if let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                       let first = jsonArray.first {
                        targetRelease = first
                    }
                } else {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        targetRelease = json
                    }
                }
                
                if let json = targetRelease,
                   let tagName = json["tag_name"] as? String {
                    
                    let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
                    
                    if self.isNewer(tagName: tagName, currentVersion: currentVersion) {
                        DispatchQueue.main.async {
                            self.latestVersion = tagName
                            // Serve up our yummy dish
                            if let assets = json["assets"] as? [[String: Any]],
                               let asset = assets.first(where: { ($0["name"] as? String) == "Deboogey.aar" }),
                               let downloadUrlString = asset["browser_download_url"] as? String,
                               let downloadUrl = URL(string: downloadUrlString) {
                                
                                self.pendingUpdateURL = downloadUrl
                                self.upgradeAvailable = true
                            }
                        }
                    }
                }
            } catch {
                print("Update check failed: \(error)")
            }
        }.resume()
    }
    
    private func isNewer(tagName: String, currentVersion: String) -> Bool {
        let cleanTag = tagName.replacingOccurrences(of: "Release ", with: "")
                              .replacingOccurrences(of: "Internal ", with: "")
                              .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return cleanTag.compare(currentVersion, options: .numeric) == .orderedDescending
    }
    
    func proceedWithUpdate() {
        guard let url = pendingUpdateURL else { return }
        downloadAndInstall(from: url)
    }
    
    var formattedLatestVersion: String {
        let v = latestVersion
        if v.lowercased().hasPrefix("rel-") {
            return "Release " + v.dropFirst(4)
        } else if v.lowercased().hasPrefix("int-") {
            return "Internal " + v.dropFirst(4)
        } else if v.hasPrefix("Release ") || v.hasPrefix("Internal ") {
            return v
        }
        return v
    }
    
    func cleanUpOldApp() {
        if !UserDefaults.standard.bool(forKey: "deleteBackupOnStartup") { return }
        
        let currentAppPath = Bundle.main.bundlePath
        let oldAppPath = currentAppPath + ".old"
        if FileManager.default.fileExists(atPath: oldAppPath) {
            do {
                try FileManager.default.removeItem(atPath: oldAppPath)
                print("Cleaned up old app backup.")
            } catch {
                print("Failed to clean up old app: \(error)")
            }
        }
    }
    
    private func downloadAndInstall(from url: URL) {
        print("Downloading upgrade from: \(url)")
        let task = URLSession.shared.downloadTask(with: url) { localUrl, response, error in
            guard let localUrl = localUrl, error == nil else { return }
            
            do {
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                
                let archivePath = tempDir.appendingPathComponent("Deboogey.aar")
                try FileManager.default.moveItem(at: localUrl, to: archivePath)

                if self.extractArchive(at: archivePath, to: tempDir) {
                    self.installUpdate(from: tempDir)
                }
            } catch {
                print("Update failed: \(error)")
            }
        }
        task.resume()
    }
    
    private func extractArchive(at archiveUrl: URL, to destination: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/aa")
        process.arguments = ["extract", "-i", archiveUrl.path, "-d", destination.path]
        
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            print("Extraction failed: \(error)")
            return false
        }
    }
    
    private func installUpdate(from sourceDir: URL) {
        let appName = "Deboogey.app"
        let potentialAppPath = sourceDir.appendingPathComponent(appName)
        
        guard FileManager.default.fileExists(atPath: potentialAppPath.path) else {
            print("Could not find \(appName) in upgrade archive")
            return
        }
        
        let currentAppPath = Bundle.main.bundlePath
        let oldAppPath = currentAppPath + ".old"
        
        do {
            if FileManager.default.fileExists(atPath: oldAppPath) {
                try FileManager.default.removeItem(atPath: oldAppPath)
            }
            try FileManager.default.moveItem(atPath: currentAppPath, toPath: oldAppPath)
            try FileManager.default.moveItem(at: potentialAppPath, to: URL(fileURLWithPath: currentAppPath))
            
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        } catch {
            print("Installation failed: \(error)")
        }
    }
}

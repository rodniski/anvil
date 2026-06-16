import Foundation

/// Um simulador iOS ou emulador Android disponível na máquina.
public struct Device: Codable, Sendable, Hashable, Identifiable {
    public var platform: Platform
    public var name: String
    /// UDID (iOS) ou nome do AVD (Android) — identificador estável pro build.
    public var identifier: String
    /// "iOS 18.2", "API 35" — runtime/versão, quando conhecido.
    public var runtime: String?
    public var isBooted: Bool

    public var id: String { identifier }

    public init(platform: Platform, name: String, identifier: String, runtime: String? = nil, isBooted: Bool = false) {
        self.platform = platform
        self.name = name
        self.identifier = identifier
        self.runtime = runtime
        self.isBooted = isBooted
    }
}

/// Uma instalação de Xcode encontrada na máquina.
public struct XcodeInstall: Sendable, Hashable, Identifiable {
    public var version: String   // "16.2"
    public var path: String      // "/Applications/Xcode.app"
    public var id: String { path }

    public init(version: String, path: String) {
        self.version = version
        self.path = path
    }
}

/// Inventaria o que existe na máquina: simuladores, emuladores, Xcodes, SDKs.
/// O Anvil *seleciona* versões — não as instala — então precisa saber o que há.
public struct DeviceCatalog: Sendable {
    private let runner: ProcessRunner
    private var fileManager: FileManager { .default }

    public init(runner: ProcessRunner = ProcessRunner()) {
        self.runner = runner
    }

    // MARK: iOS simulators

    /// `xcrun simctl list devices -j` → simuladores disponíveis.
    public func iosSimulators() async throws -> [Device] {
        let result = try await runner.run("xcrun", arguments: ["simctl", "list", "devices", "available", "-j"])
        guard result.succeeded,
              let data = result.output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let byRuntime = json["devices"] as? [String: [[String: Any]]]
        else { return [] }

        var devices: [Device] = []
        for (runtimeKey, list) in byRuntime {
            let runtime = Self.prettyRuntime(runtimeKey)
            for entry in list {
                guard let name = entry["name"] as? String,
                      let udid = entry["udid"] as? String,
                      (entry["isAvailable"] as? Bool) ?? true
                else { continue }
                let booted = (entry["state"] as? String) == "Booted"
                devices.append(Device(platform: .ios, name: name, identifier: udid, runtime: runtime, isBooted: booted))
            }
        }
        return devices.sorted { ($0.runtime ?? "", $0.name) > ($1.runtime ?? "", $1.name) }
    }

    /// "com.apple.CoreSimulator.SimRuntime.iOS-18-2" → "iOS 18.2".
    static func prettyRuntime(_ key: String) -> String {
        guard let tail = key.split(separator: ".").last else { return key }
        let parts = tail.split(separator: "-")  // ["iOS", "18", "2"]
        guard parts.count >= 2 else { return String(tail) }
        let os = parts[0]
        let version = parts.dropFirst().joined(separator: ".")
        return "\(os) \(version)"
    }

    // MARK: Android emulators

    /// `emulator -list-avds` → AVDs. Procura o `emulator` via ANDROID_HOME.
    public func androidEmulators() async throws -> [Device] {
        guard let emulatorPath = androidEmulatorBinary() else { return [] }
        let result = try await runner.run(emulatorPath, arguments: ["-list-avds"])
        guard result.succeeded else { return [] }
        return result.output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("INFO") }
            .map { Device(platform: .android, name: $0, identifier: $0) }
    }

    private func androidEmulatorBinary() -> String? {
        let env = ProcessInfo.processInfo.environment
        let home = env["ANDROID_HOME"] ?? env["ANDROID_SDK_ROOT"]
            ?? (env["HOME"].map { "\($0)/Library/Android/sdk" })
        guard let home else { return nil }
        let path = "\(home)/emulator/emulator"
        return fileManager.isExecutableFile(atPath: path) ? path : nil
    }

    // MARK: Xcode versions

    /// Varre `/Applications` por `Xcode*.app` e lê a versão de cada um.
    public func xcodeInstalls() async throws -> [XcodeInstall] {
        let apps = (try? fileManager.contentsOfDirectory(atPath: "/Applications")) ?? []
        let xcodeApps = apps.filter { $0.hasPrefix("Xcode") && $0.hasSuffix(".app") }
        var installs: [XcodeInstall] = []
        for app in xcodeApps {
            let path = "/Applications/\(app)"
            let plist = "\(path)/Contents/version.plist"
            if let version = Self.readShortVersion(plistPath: plist) {
                installs.append(XcodeInstall(version: version, path: path))
            } else {
                installs.append(XcodeInstall(version: app, path: path))
            }
        }
        return installs.sorted { $0.version > $1.version }
    }

    private static func readShortVersion(plistPath: String) -> String? {
        guard let data = FileManager.default.contents(atPath: plistPath),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return plist["CFBundleShortVersionString"] as? String
    }
}

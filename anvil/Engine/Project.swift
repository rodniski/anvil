import Foundation

/// Tipo de um componente buildável.
public enum Platform: String, Codable, Sendable, CaseIterable {
    case ios
    case android
    case bun       // JS/TS service (bun ou npm, detectado pelo lockfile)
    case docker

    /// Rótulo do bloco.
    public var label: String {
        switch self {
        case .ios: "swift · iOS"
        case .android: "kotlin · Android"
        case .bun: "node · service"
        case .docker: "docker · container"
        }
    }

    /// Asset do logo (template branco).
    public var logoAsset: String {
        switch self {
        case .ios: "AppleLogo"
        case .android: "AndroidLogo"
        case .bun: "BunLogo"
        case .docker: "DockerLogo"
        }
    }
}

/// O que a pasta de um projeto contém.
public enum ProjectKind: String, Codable, Sendable {
    case ios
    case android
    case both

    public var platforms: [Platform] {
        switch self {
        case .ios: [.ios]
        case .android: [.android]
        case .both: [.ios, .android]
        }
    }

    public func includes(_ platform: Platform) -> Bool {
        platforms.contains(platform)
    }
}

/// Um scheme do Xcode (`.xcodeproj`/`.xcworkspace`).
public struct Scheme: Codable, Sendable, Hashable, Identifiable {
    public var name: String
    public var id: String { name }

    public init(name: String) {
        self.name = name
    }
}

/// Uma combinação flavor × buildType do Gradle (ex.: `prodDebug`).
public struct Flavor: Codable, Sendable, Hashable, Identifiable {
    /// Product flavor (pode ser vazio em projetos sem flavors).
    public var flavor: String
    /// Build type (`debug`, `release`, …).
    public var buildType: String
    public var id: String { displayName }

    public init(flavor: String, buildType: String) {
        self.flavor = flavor
        self.buildType = buildType
    }

    /// Nome legível: `prod · debug` ou só `debug` quando não há flavor.
    public var displayName: String {
        flavor.isEmpty ? buildType : "\(flavor) · \(buildType)"
    }

    /// Sufixo da task Gradle: `ProdDebug` ou `Debug`.
    public var gradleSuffix: String {
        (flavor.capitalizedFirst) + buildType.capitalizedFirst
    }
}

/// A última seleção feita pelo usuário, lembrada por projeto.
public struct Selection: Codable, Sendable, Hashable {
    public var iosScheme: String?
    public var iosSimulator: String?
    public var iosXcode: String?
    public var iosEnvironment: String?

    public var androidFlavor: String?
    public var androidEmulator: String?
    public var androidSDK: String?
    public var androidEnvironment: String?

    // Bun/npm e Docker: tarefa (script/serviço) + ambiente.
    public var task: String?
    public var environment: String?

    public init() {}
}

/// Um projeto plugado no Anvil.
/// Um componente buildável de um projeto — uma pasta de uma plataforma
/// (Swift/iOS, Kotlin/Android, e futuramente Bun, Docker…).
public struct Component: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public var name: String
    public var path: URL
    public var platform: Platform
    public var iosTargets: [Scheme]
    public var androidTargets: [Flavor]
    public var tasks: [String]          // bun: scripts · docker: serviços
    public var selection: Selection

    public init(
        id: UUID = UUID(),
        name: String,
        path: URL,
        platform: Platform,
        iosTargets: [Scheme] = [],
        androidTargets: [Flavor] = [],
        tasks: [String] = [],
        selection: Selection = Selection()
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.platform = platform
        self.iosTargets = iosTargets
        self.androidTargets = androidTargets
        self.tasks = tasks
        self.selection = selection
    }
}

/// Um projeto é um container nomeado de componentes (ex.: `m4doc`).
public struct Project: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public var name: String
    public var components: [Component]

    public init(id: UUID = UUID(), name: String, components: [Component] = []) {
        self.id = id
        self.name = name
        self.components = components
    }
}

extension String {
    /// Primeira letra maiúscula, resto intacto (`prod` → `Prod`).
    var capitalizedFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}

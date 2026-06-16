import Foundation
import Testing
@testable import Anvil

// MARK: - ProjectDetector

@Suite("ProjectDetector")
struct ProjectDetectorTests {
    func makeTempDir(_ entries: [String]) throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("anvil-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for entry in entries {
            if entry.hasSuffix(".xcodeproj") || entry.hasSuffix(".xcworkspace") {
                try FileManager.default.createDirectory(at: dir.appendingPathComponent(entry), withIntermediateDirectories: true)
            } else {
                try Data().write(to: dir.appendingPathComponent(entry))
            }
        }
        return dir
    }

    @Test("detecta iOS por .xcodeproj")
    func detectsIOS() throws {
        let dir = try makeTempDir(["App.xcodeproj", "README.md"])
        #expect(try ProjectDetector().detect(at: dir) == [.ios])
    }

    @Test("detecta Android por settings.gradle.kts")
    func detectsAndroid() throws {
        let dir = try makeTempDir(["settings.gradle.kts", "gradlew"])
        #expect(try ProjectDetector().detect(at: dir) == [.android])
    }

    @Test("detecta iOS + Android juntos")
    func detectsBoth() throws {
        let dir = try makeTempDir(["App.xcworkspace", "settings.gradle"])
        #expect(try ProjectDetector().detect(at: dir) == [.ios, .android])
    }

    @Test("detecta Bun por package.json")
    func detectsBun() throws {
        let dir = try makeTempDir(["package.json"])
        #expect(try ProjectDetector().detect(at: dir) == [.bun])
    }

    @Test("detecta Docker por Dockerfile")
    func detectsDocker() throws {
        let dir = try makeTempDir(["Dockerfile"])
        #expect(try ProjectDetector().detect(at: dir) == [.docker])
    }

    @Test("lança quando não há nada reconhecido")
    func throwsWhenEmpty() throws {
        let dir = try makeTempDir(["README.md"])
        #expect(throws: ProjectDetector.DetectionError.self) {
            try ProjectDetector().detect(at: dir)
        }
    }
}

// MARK: - SchemeDiscovery (parsing puro)

@Suite("SchemeDiscovery.parseFlavors")
struct FlavorParsingTests {
    @Test("separa flavor de buildType")
    func splitsFlavorAndBuildType() {
        let output = """
        assembleProdDebug - Assembles main output.
        app:assembleProdRelease
        assembleDebug - Assembles main output for variant debug.
        compileDebugSources
        clean - Deletes the build directory.
        """
        let flavors = SchemeDiscovery.parseFlavors(fromGradleTasks: output)
        #expect(flavors.contains(Flavor(flavor: "prod", buildType: "debug")))
        #expect(flavors.contains(Flavor(flavor: "prod", buildType: "release")))
        #expect(flavors.contains(Flavor(flavor: "", buildType: "debug")))
    }

    @Test("ignora tasks que não são assemble")
    func ignoresNonAssemble() {
        let flavors = SchemeDiscovery.parseFlavors(fromGradleTasks: "compileDebugKotlin\nlint\ntest")
        #expect(flavors.isEmpty)
    }

    @Test("displayName e gradleSuffix")
    func flavorNaming() {
        #expect(Flavor(flavor: "prod", buildType: "debug").displayName == "prod · debug")
        #expect(Flavor(flavor: "", buildType: "debug").displayName == "debug")
        #expect(Flavor(flavor: "prod", buildType: "debug").gradleSuffix == "ProdDebug")
        #expect(Flavor(flavor: "", buildType: "release").gradleSuffix == "Release")
    }
}

// MARK: - DeviceCatalog (parsing puro)

@Suite("DeviceCatalog.prettyRuntime")
struct RuntimeParsingTests {
    @Test("formata runtime do simctl")
    func formatsRuntime() {
        #expect(DeviceCatalog.prettyRuntime("com.apple.CoreSimulator.SimRuntime.iOS-18-2") == "iOS 18.2")
        #expect(DeviceCatalog.prettyRuntime("com.apple.CoreSimulator.SimRuntime.iOS-17-0") == "iOS 17.0")
    }
}

// MARK: - BuildRunner (montagem de comando)

@Suite("BuildRunner.command")
struct BuildCommandTests {
    func iosComponent() -> Component {
        var sel = Selection()
        sel.iosScheme = "App"
        sel.iosSimulator = "ABC-123"
        sel.iosXcode = "/Applications/Xcode.app"
        return Component(name: "swift", path: URL(fileURLWithPath: "/tmp/demo"), platform: .ios,
                         iosTargets: [Scheme(name: "App")], selection: sel)
    }

    @Test("monta xcodebuild — sem container lança erro controlado")
    func buildsIOSCommand() throws {
        // /tmp/demo não tem .xcodeproj → erro esperado.
        #expect(throws: BuildRunner.BuildError.self) {
            _ = try BuildRunner().command(for: iosComponent(), mode: .build)
        }
    }

    @Test("monta gradlew assemble pra Android")
    func buildsAndroidAssemble() throws {
        let flavor = Flavor(flavor: "prod", buildType: "debug")
        var sel = Selection()
        sel.androidFlavor = flavor.id
        let component = Component(name: "kotlin", path: URL(fileURLWithPath: "/tmp/demo"), platform: .android,
                                  androidTargets: [flavor], selection: sel)
        let cmd = try BuildRunner().command(for: component, mode: .build)
        #expect(cmd.executable == "./gradlew")
        #expect(cmd.arguments == ["assembleProdDebug"])
    }

    @Test("run usa install no Android")
    func buildsAndroidInstall() throws {
        let flavor = Flavor(flavor: "", buildType: "debug")
        var sel = Selection()
        sel.androidFlavor = flavor.id
        let component = Component(name: "kotlin", path: URL(fileURLWithPath: "/tmp/demo"), platform: .android,
                                  androidTargets: [flavor], selection: sel)
        let cmd = try BuildRunner().command(for: component, mode: .run)
        #expect(cmd.arguments == ["installDebug"])
    }

    @Test("lança quando falta seleção")
    func throwsOnMissingSelection() {
        let component = Component(name: "kotlin", path: URL(fileURLWithPath: "/tmp/demo"), platform: .android)
        #expect(throws: BuildRunner.BuildError.self) {
            _ = try BuildRunner().command(for: component, mode: .build)
        }
    }
}

// MARK: - ProjectStore (round-trip)

@Suite("ProjectStore")
struct ProjectStoreTests {
    @Test("salva e recarrega projetos com componentes")
    func roundTrip() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("anvil-store-\(UUID().uuidString)")
            .appendingPathComponent("projects.json")
        let store = ProjectStore(fileURL: tmp)

        #expect(try store.load().isEmpty)

        var sel = Selection()
        sel.iosScheme = "App"
        let ios = Component(name: "swift", path: URL(fileURLWithPath: "/tmp/clinico/swift"), platform: .ios,
                            iosTargets: [Scheme(name: "App")], selection: sel)
        let android = Component(name: "kotlin", path: URL(fileURLWithPath: "/tmp/clinico/kotlin"), platform: .android,
                                androidTargets: [Flavor(flavor: "prod", buildType: "debug")])
        let project = Project(name: "Clínico", components: [ios, android])
        try store.save([project])

        let loaded = try store.load()
        #expect(loaded.count == 1)
        #expect(loaded.first?.name == "Clínico")
        #expect(loaded.first?.components.count == 2)
        #expect(loaded.first?.components.first?.selection.iosScheme == "App")
    }
}

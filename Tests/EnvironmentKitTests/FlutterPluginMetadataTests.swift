import Core
@testable import EnvironmentKit
import Foundation
import TestSupport
import Testing

@Suite("Flutter plugin preparation evidence")
struct FlutterPluginMetadataTests {
    @Test("an app with no reachable plugins accepts the official absence of plugin metadata")
    func noPlugins() async throws {
        let f = try FlutterFixture()
        try FileManager.default.removeItem(at: f.repo.url(".flutter-plugins-dependencies"))
        let plan = try await f.inspect(f.runner())
        expectGenerated(plan, reuse: true)
    }

    @Test("plugin metadata must include every reachable platform implementation", arguments: ["absent", "empty", "subset", "complete"])
    func requiredPlugins(_ mode: String) async throws {
        let f = try FlutterFixture()
        try configure(f, plugins: ["foo", "bar"])
        let selected = mode == "complete" ? ["foo", "bar"] : mode == "subset" ? ["foo"] : []
        if mode == "absent" { try FileManager.default.removeItem(at: f.repo.url(".flutter-plugins-dependencies")) }
        else { try metadata(f, plugins: selected) }
        let plan = try await f.inspect(f.runner())
        expectGenerated(plan, reuse: mode == "complete")
    }

    @Test("missing or inconsistent resolved package evidence stays manual", arguments: ["manifest", "yaml", "name", "graph", "edge", "config"])
    func incompleteEvidence(_ mode: String) async throws {
        let f = try FlutterFixture()
        try configure(f, plugins: ["foo"])
        try metadata(f, plugins: ["foo"])
        switch mode {
        case "manifest": try FileManager.default.removeItem(at: f.repo.url("packages/foo/pubspec.yaml"))
        case "yaml": try f.repo.write("packages/foo/pubspec.yaml", "name: [invalid\n")
        case "name": try f.repo.write("packages/foo/pubspec.yaml", "name: another\n")
        case "graph": try FileManager.default.removeItem(at: f.repo.url(".dart_tool/package_graph.json"))
        case "edge": try f.repo.write("pubspec.yaml", manifest(dependencies: ["flutter", "missing"]))
        default: try f.repo.write(".dart_tool/package_config.json", "{\"configVersion\":1,\"packages\":[]}")
        }
        let plan = try await f.inspect(f.runner())
        expectGenerated(plan, reuse: false)
    }

    @Test("a plugin used only by another workspace app does not make this app a plugin app")
    func unrelatedWorkspacePlugin() async throws {
        let f = try FlutterFixture()
        try configure(f, plugins: ["foo"], reachable: false)
        try FileManager.default.removeItem(at: f.repo.url(".flutter-plugins-dependencies"))
        let workspace = try JSONSerialization.data(withJSONObject: ["packages": [
            ["name": "example", "path": f.repo.root.path], ["name": "other", "path": f.repo.url("other").path]
        ]])
        let plan = try await f.inspect(f.runner(workspace: String(decoding: workspace, as: UTF8.self)))
        expectGenerated(plan, reuse: true)
    }

    @Test("plugin traversal follows transitive and app dev edges but excludes dependency dev edges", arguments: ["transitive", "appDev", "dependencyDev"])
    func selectedClosure(_ mode: String) async throws {
        let f = try FlutterFixture()
        try configure(f, plugins: ["foo", "bar"])
        try f.repo.write("pubspec.yaml", manifest(dependencies: mode == "appDev" ? ["flutter"] : ["flutter", "foo"])
            + (mode == "appDev" ? "dev_dependencies:\n  foo: any\n" : ""))
        var graph = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: f.repo.url(".dart_tool/package_graph.json"))) as? [String: Any])
        var packages = try #require(graph["packages"] as? [[String: Any]])
        for index in packages.indices {
            if packages[index]["name"] as? String == "example" {
                packages[index]["dependencies"] = mode == "appDev" ? ["flutter"] : ["flutter", "foo"]
                packages[index]["devDependencies"] = mode == "appDev" ? ["foo"] : []
            }
            if packages[index]["name"] as? String == "foo" {
                packages[index]["dependencies"] = mode == "transitive" ? ["bar"] : []
                packages[index]["devDependencies"] = mode == "dependencyDev" ? ["bar"] : []
            }
        }
        graph["packages"] = packages
        try JSONSerialization.data(withJSONObject: graph).write(to: f.repo.url(".dart_tool/package_graph.json"))
        let foo = try String(contentsOf: f.repo.url("packages/foo/pubspec.yaml"), encoding: .utf8)
        if mode != "appDev" {
            try f.repo.write("packages/foo/pubspec.yaml", foo + (mode == "transitive" ? "dependencies" : "dev_dependencies") + ":\n  bar: any\n")
        }
        try metadata(f, plugins: mode == "appDev" ? [] : ["foo"])
        let before = try await f.inspect(f.runner())
        expectGenerated(before, reuse: mode == "dependencyDev")
        try metadata(f, plugins: mode == "transitive" ? ["foo", "bar"] : ["foo"])
        let complete = try await f.inspect(f.runner())
        expectGenerated(complete, reuse: true)
    }

    @Test("legacy and federated declarations report a manual resolver boundary", arguments: ["legacy", "default", "implements"])
    func unresolvedPlugin(_ mode: String) async throws {
        let f = try FlutterFixture()
        try configure(f, plugins: ["foo"])
        try metadata(f, plugins: ["foo"])
        let declaration = mode == "legacy" ? "    pluginClass: FixturePlugin\n"
            : mode == "default" ? "    platforms:\n      ios:\n        default_package: foo_ios\n"
            : "    implements: foo_interface\n    platforms:\n      ios:\n        pluginClass: FixturePlugin\n"
        try f.repo.write("packages/foo/pubspec.yaml", "name: foo\nflutter:\n  plugin:\n" + declaration)
        let plan = try await f.inspect(f.runner())
        expectGenerated(plan, reuse: false)
        #expect(plan.checks.contains { $0.id == "ios.flutter.generated" && $0.observed?.contains("legacy or federated") == true })
        let manual = try await f.inspect(f.runner(), preparedDependencies: true)
        expectGenerated(manual, reuse: true)
        #expect(manual.iosPluginDirectories == ["foo": f.repo.url("packages/foo")])
        #expect(manual.iosPluginMetadata == .bytes(try Data(contentsOf: f.repo.url(".flutter-plugins-dependencies"))))
    }

    @Test("manual resolver reuse still rejects unsafe or missing generated evidence", arguments: ["absent", "version", "path", "duplicate", "native-number", "shared-number", "graph"])
    func manualEvidence(_ fault: String) async throws {
        let f = try FlutterFixture()
        try configure(f, plugins: ["foo"])
        try f.repo.write("packages/foo/pubspec.yaml", "name: foo\nflutter:\n  plugin:\n    pluginClass: FixturePlugin\n")
        var row: [String: Any] = ["name": "foo", "path": f.repo.url("packages/foo").path, "native_build": true]
        if fault == "path" { row["path"] = f.repo.url("another-package").path }
        if fault == "native-number" { row["native_build"] = 1 }
        if fault == "shared-number" { row["shared_darwin_source"] = 0 }
        let rows = fault == "duplicate" ? [row, row] : [row]
        try JSONSerialization.data(withJSONObject: ["version": fault == "version" ? "0.0.0" : "3.41.9",
            "plugins": ["ios": rows, "android": rows]]).write(to: f.repo.url(".flutter-plugins-dependencies"))
        if fault == "absent" { try FileManager.default.removeItem(at: f.repo.url(".flutter-plugins-dependencies")) }
        if fault == "graph" { try FileManager.default.removeItem(at: f.repo.url(".dart_tool/package_graph.json")) }
        let plan = try await f.inspect(f.runner(), preparedDependencies: true)
        expectGenerated(plan, reuse: false)
        #expect(plan.iosPluginMetadata == nil)
    }

    @Test("manual reuse binds generated native directories without claiming resolver completeness")
    func manualResolverResponsibility() async throws {
        let f = try FlutterFixture()
        try configure(f, plugins: ["foo", "bar"])
        try metadata(f, plugins: ["foo"])
        let automatic = try await f.inspect(f.runner())
        expectGenerated(automatic, reuse: false)
        let manual = try await f.inspect(f.runner(), preparedDependencies: true)
        expectGenerated(manual, reuse: true)
        #expect(manual.iosPluginDirectories == ["foo": f.repo.url("packages/foo")])
    }

    @Test("manual selected implementations retain package identity without requiring app reachability",
          arguments: ["valid", "missing-graph", "manifest-name", "dependency-mismatch"])
    func manualSelectedPackageIdentity(_ mode: String) async throws {
        let f = try FlutterFixture()
        try configure(f, plugins: ["foo", "bar"])
        try f.repo.write("pubspec.yaml", manifest(dependencies: ["flutter", "foo"]))
        try f.repo.write("packages/bar/pubspec.yaml", "name: \(mode == "manifest-name" ? "other" : "bar")\nflutter:\n  plugin:\n    implements: foo\n    platforms:\n      ios:\n        pluginClass: BarPlugin\n")
        let graphFile = f.repo.url(".dart_tool/package_graph.json")
        var graph = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: graphFile)) as? [String: Any])
        var packages = try #require(graph["packages"] as? [[String: Any]])
        for index in packages.indices {
            if packages[index]["name"] as? String == "example" { packages[index]["dependencies"] = ["flutter", "foo"] }
            if packages[index]["name"] as? String == "bar", mode == "dependency-mismatch" {
                packages[index]["dependencies"] = ["foo"]
            }
        }
        if mode == "missing-graph" { packages.removeAll { $0["name"] as? String == "bar" } }
        graph["packages"] = packages
        try JSONSerialization.data(withJSONObject: graph).write(to: graphFile)
        try metadata(f, plugins: ["bar"])
        let plan = try await f.inspect(f.runner(), preparedDependencies: true)
        expectGenerated(plan, reuse: mode == "valid")
        if mode == "valid" {
            #expect(plan.iosPluginDirectories == ["bar": f.repo.url("packages/bar")])
            #expect(plan.iosPluginMetadata == .bytes(try Data(contentsOf: f.repo.url(".flutter-plugins-dependencies"))))
        } else {
            #expect(plan.iosPluginDirectories.isEmpty)
            #expect(plan.iosPluginMetadata == nil)
        }
    }

    @Test("manual selected implementations validate their runtime closure without requiring dependency dev packages",
          arguments: ["valid", "cycle", "missing-child", "child-name", "child-edges", "dependency-dev"])
    func manualSelectedRuntimeClosure(_ mode: String) async throws {
        let f = try FlutterFixture()
        try configure(f, plugins: ["foo", "bar", "child"])
        try f.repo.write("pubspec.yaml", manifest(dependencies: ["flutter", "foo"]))
        let dependency = mode == "missing-child" ? "missing" : "child"
        try f.repo.write("packages/bar/pubspec.yaml", "name: bar\ndependencies:\n  \(dependency): any\nflutter:\n  plugin:\n    implements: foo\n    platforms:\n      ios:\n        pluginClass: BarPlugin\n")
        try f.repo.write("packages/child/pubspec.yaml", "name: \(mode == "child-name" ? "other" : "child")\n"
            + (mode == "cycle" ? "dependencies:\n  bar: any\n" : "")
            + (mode == "dependency-dev" ? "dev_dependencies:\n  missing: any\n" : ""))
        let graphFile = f.repo.url(".dart_tool/package_graph.json")
        var graph = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: graphFile)) as? [String: Any])
        var packages = try #require(graph["packages"] as? [[String: Any]])
        for index in packages.indices {
            switch packages[index]["name"] as? String {
            case "example": packages[index]["dependencies"] = ["flutter", "foo"]
            case "bar": packages[index]["dependencies"] = [dependency]
            case "child":
                packages[index]["dependencies"] = mode == "cycle" ? ["bar"] : mode == "child-edges" ? ["foo"] : []
                packages[index]["devDependencies"] = mode == "dependency-dev" ? ["missing"] : []
            default: break
            }
        }
        graph["packages"] = packages
        try JSONSerialization.data(withJSONObject: graph).write(to: graphFile)
        try metadata(f, plugins: ["bar"])
        let plan = try await f.inspect(f.runner(), preparedDependencies: true)
        let valid = ["valid", "cycle", "dependency-dev"].contains(mode)
        expectGenerated(plan, reuse: valid)
        #expect(plan.iosPluginDirectories == (valid ? ["bar": f.repo.url("packages/bar")] : [:]))
        #expect(plan.iosPluginMetadata == (valid ? .bytes(try Data(contentsOf: f.repo.url(".flutter-plugins-dependencies"))) : nil))
    }

    @Test("plugin rows preserve exact identity and native build evidence", arguments: ["native", "path", "duplicate"])
    func staleRows(_ mode: String) async throws {
        let f = try FlutterFixture()
        try configure(f, plugins: ["foo"])
        var row: [String: Any] = ["name": "foo", "path": f.repo.url("packages/foo").path, "native_build": true]
        if mode == "native" { row["native_build"] = false }
        if mode == "path" { row["path"] = f.repo.url("another-package").path }
        let rows = mode == "duplicate" ? [row, row] : [row]
        try JSONSerialization.data(withJSONObject: ["version": "3.41.9", "plugins": ["ios": rows, "android": rows]]).write(to: f.repo.url(".flutter-plugins-dependencies"))
        let plan = try await f.inspect(f.runner())
        expectGenerated(plan, reuse: false)
    }

    private func expectGenerated(_ plan: FlutterPreparation, reuse: Bool) {
        for platform in ["ios", "android"] {
            #expect(plan.checks.contains { $0.id == "\(platform).flutter.generated" && ($0.kind == "reuse") == reuse }, Comment(rawValue: plan.checks.first { $0.id == "\(platform).flutter.generated" }?.observed ?? "missing generated check"))
        }
    }

    private func manifest(dependencies: [String]) -> String {
        "name: example\nenvironment:\n  sdk: '>=3.6.0 <4.0.0'\n  flutter: '>=3.24.0'\ndependencies:\n" + dependencies.map {
            $0 == "flutter" ? "  flutter:\n    sdk: flutter\n" : "  \($0): any\n"
        }.joined()
    }

    private func configure(_ f: FlutterFixture, plugins: [String], reachable: Bool = true) throws {
        try f.repo.write("pubspec.yaml", manifest(dependencies: ["flutter"] + (reachable ? plugins : [])))
        var packages: [[String: Any]] = [["name": "example", "rootUri": f.repo.root.absoluteString],
            ["name": "flutter", "rootUri": f.repo.url("sdk/packages/flutter").absoluteString]]
        var graph: [[String: Any]] = [["name": "example", "dependencies": ["flutter"] + (reachable ? plugins : []), "devDependencies": []],
            ["name": "flutter", "dependencies": [], "devDependencies": []]]
        for name in plugins {
            try f.repo.write("packages/\(name)/pubspec.yaml", "name: \(name)\nflutter:\n  plugin:\n    platforms:\n      ios:\n        pluginClass: FixturePlugin\n      android:\n        package: dev.fixture\n        pluginClass: FixturePlugin\n")
            packages.append(["name": name, "rootUri": f.repo.url("packages/\(name)").absoluteString])
            graph.append(["name": name, "dependencies": [], "devDependencies": []])
        }
        if !reachable {
            try f.repo.write("pubspec.yaml", manifest(dependencies: ["flutter"]) + "workspace:\n  - other\n")
            try f.repo.write("other/pubspec.yaml", manifest(dependencies: ["flutter"] + plugins).replacingOccurrences(of: "name: example", with: "name: other") + "resolution: workspace\n")
            packages.append(["name": "other", "rootUri": f.repo.url("other").absoluteString])
            graph.append(["name": "other", "dependencies": ["flutter"] + plugins, "devDependencies": []])
        }
        try JSONSerialization.data(withJSONObject: ["configVersion": 2, "packages": packages]).write(to: f.repo.url(".dart_tool/package_config.json"))
        try JSONSerialization.data(withJSONObject: ["configVersion": 1, "roots": reachable ? ["example"] : ["example", "other"], "packages": graph]).write(to: f.repo.url(".dart_tool/package_graph.json"))
    }

    private func metadata(_ f: FlutterFixture, plugins: [String]) throws {
        let rows = plugins.map { ["name": $0, "path": f.repo.url("packages/\($0)").path + "/", "native_build": true] as [String: Any] }
        try JSONSerialization.data(withJSONObject: ["version": "3.41.9", "plugins": ["ios": rows, "android": rows]]).write(to: f.repo.url(".flutter-plugins-dependencies"))
    }
}

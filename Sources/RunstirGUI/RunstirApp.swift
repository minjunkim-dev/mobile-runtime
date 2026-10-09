#if os(macOS)
import AppKit
import Core
import EnvironmentKit
import SwiftUI

@main
struct RunstirApp {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windows: [FolderIdentity: NSWindow] = [:]
    private var welcome: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "프로젝트 열기…", action: #selector(openProject), keyEquivalent: "o").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Runstir 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let item = NSMenuItem()
        item.submenu = appMenu
        menu.addItem(item)
        NSApplication.shared.mainMenu = menu
        let window = makeWindow(title: "Runstir")
        window.contentView = NSHostingView(rootView: VStack(spacing: 16) {
            Text("Runstir").font(.largeTitle)
            Text("React Native 프로젝트의 환경을 확인하세요.")
            Button("프로젝트 열기…") { self.openProject() }.keyboardShortcut("o")
        }.padding(40).frame(maxWidth: .infinity, maxHeight: .infinity))
        welcome = window
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @objc func openProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        do {
            let identity = try FolderIdentity(directory: directory)
            if let existing = windows[identity] { existing.makeKeyAndOrderFront(nil); return }
            let window = makeWindow(title: "Runstir — \(directory.lastPathComponent)")
            window.contentView = NSHostingView(rootView: InspectionView(directory: URL(fileURLWithPath: identity.path)))
            windows[identity] = window
            window.makeKeyAndOrderFront(nil)
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    private func makeWindow(title: String) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 840, height: 640),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = title
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}

struct InspectionView: View {
    let directory: URL
    @State private var app = ""
    @State private var platform = ""
    @State private var result: EnvironmentInspection?
    @State private var error: String?
    @State private var checking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(directory.path).font(.headline).textSelection(.enabled)
            HStack {
                Picker("앱", selection: $app) {
                    Text("자동 선택").tag("")
                    ForEach(result?.selection.candidates ?? [], id: \.id) { candidate in
                        Text(candidate.id).tag(candidate.id)
                    }
                }.disabled(checking)
                Picker("플랫폼", selection: $platform) {
                    Text("자동 선택").tag("")
                    Text("iOS").tag("ios")
                    Text("Android").tag("android")
                }.disabled(checking)
                Button("환경 확인") { inspect() }.keyboardShortcut("r").disabled(checking)
            }
            if checking { ProgressView("환경 확인 중") }
            if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            if let result {
                if let selected = result.selection.selected {
                    Text("검사 대상: \(selected.id) / \(result.selection.platform?.rawValue ?? "플랫폼 선택 필요")")
                }
                if let selectionError = result.selection.error { Text(selectionError).foregroundStyle(.red) }
                if !result.selection.requiredInput.isEmpty {
                    Text("선택 필요: \(result.selection.requiredInput.joined(separator: ", "))")
                }
                if result.selection.candidates.isEmpty { Text("프로젝트를 찾지 못했습니다. 호스트 검사만 표시합니다.") }
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(result.report.checks, id: \.id) { check in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("[\(check.status.rawValue)] \(check.title)").font(.headline)
                                Text(check.id).font(.caption)
                                if let observed = check.outcome.observed { Text(observed) }
                                if let reason = check.outcome.reason { Text(reason) }
                                if let remediation = check.outcome.remediation {
                                    Text(remediation.summary)
                                    if let command = remediation.command { Text(command).font(.system(.body, design: .monospaced)) }
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }.textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
        }.padding(20).task { inspect() }
    }

    @MainActor private func inspect() {
        guard !checking else { return }
        checking = true
        error = nil
        let environment = ProcessInfo.processInfo.environment
        let input = ProjectInspectionInput(directory: directory, environment: environment,
                                           app: app.isEmpty ? nil : app, platform: ProjectPlatform(rawValue: platform))
        Task {
            defer { checking = false }
            do { result = try await EnvironmentInspection.run(input: input) }
            catch { self.error = error.localizedDescription }
        }
    }
}
#else
@main struct RunstirApp {
    static func main() { print("Runstir GUI requires macOS.") }
}
#endif

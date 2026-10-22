#if os(macOS)
import AppKit
import Core
import EnvironmentKit
import SwiftUI

@main
struct RunstirApp {
    @MainActor static func main() {
        FlutterAndroidChildClient.runIfRequested()
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var windows: [FolderIdentity: NSWindow] = [:]
    private var fileWindows: [String: NSWindow] = [:]
    private var sessions: [ObjectIdentifier: GUIOperationSession] = [:]
    private var terminating = false
    private var welcome: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "프로젝트 열기…", action: #selector(openProject), keyEquivalent: "o").target = self
        appMenu.addItem(withTitle: "앱 파일 열기…", action: #selector(openAppFile), keyEquivalent: "O").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Runstir 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let item = NSMenuItem()
        item.submenu = appMenu
        menu.addItem(item)
        NSApplication.shared.mainMenu = menu
        let window = makeWindow(title: "Runstir")
        window.contentView = NSHostingView(rootView: VStack(spacing: 16) {
            Text("Runstir").font(.largeTitle)
            Text("프로젝트의 iOS·Android 환경을 확인하세요.")
            Button("프로젝트 열기…") { self.openProject() }.keyboardShortcut("o")
            Button("앱 파일 열기…") { self.openAppFile() }
        }.padding(40).frame(maxWidth: .infinity, maxHeight: .infinity))
        welcome = window
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @objc func openProject() {
        guard !terminating else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        do {
            let identity = try FolderIdentity(directory: directory)
            if let existing = windows[identity] { existing.makeKeyAndOrderFront(nil); return }
            let window = makeWindow(title: "Runstir — \(directory.lastPathComponent)")
            let session = GUIOperationSession()
            sessions[ObjectIdentifier(window)] = session
            window.delegate = self
            window.contentView = NSHostingView(rootView: InspectionView(directory: URL(fileURLWithPath: identity.path), session: session))
            windows[identity] = window
            window.makeKeyAndOrderFront(nil)
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    @objc func openAppFile() {
        guard !terminating else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Simulator .app 또는 단일 APK를 선택하세요. 파일 선택으로 설치하지 않습니다."
        guard panel.runModal() == .OK, let file = panel.url else { return }
        do {
            let identity = try AppFileIdentity(url: file)
            // Re-read each window's selected path: an atomic replacement must not
            // leave a stale inode mapping that merges two now-distinct files.
            if let existing = fileWindows[identity.path] ?? fileWindows.first(where: {
                (try? AppFileIdentity(url: URL(fileURLWithPath: $0.key))) == identity
            })?.value { existing.makeKeyAndOrderFront(nil); return }
            let window = makeWindow(title: "Runstir — \(file.lastPathComponent)")
            let session = GUIOperationSession()
            sessions[ObjectIdentifier(window)] = session
            window.delegate = self
            window.contentView = NSHostingView(rootView: AppFileView(file: URL(fileURLWithPath: identity.path), session: session))
            fileWindows[identity.path] = window
            window.makeKeyAndOrderFront(nil)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let session = sessions[ObjectIdentifier(sender)], session.task != nil else { return true }
        guard sender.attachedSheet == nil else { return false }
        let alert = NSAlert()
        alert.messageText = "이 창에서 작업이 진행 중입니다."
        alert.informativeText = "작업을 계속하거나 취소가 완료된 뒤 창을 닫으세요. 완료한 설치와 기존 앱 데이터는 보존합니다."
        alert.addButton(withTitle: "작업 계속")
        alert.addButton(withTitle: "취소 후 닫기")
        alert.beginSheetModal(for: sender) { response in
            Task { @MainActor in
                if response == .alertSecondButtonReturn { session.cancel { sender.close() } }
            }
        }
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if terminating { return .terminateLater }
        let active = sessions.values.filter { $0.task != nil }
        guard !active.isEmpty else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "\(active.count)개 작업이 진행 중입니다."
        let titles = sender.windows.filter { sessions[ObjectIdentifier($0)]?.task != nil }.map(\.title)
        alert.informativeText = titles.joined(separator: "\n") + "\n모든 작업의 취소와 보존 처리가 끝난 뒤 종료합니다. 실행을 마친 모바일 앱과 기기는 종료하지 않습니다."
        alert.addButton(withTitle: "작업 계속")
        alert.addButton(withTitle: "모두 취소 후 종료")
        guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        terminating = true
        sessions.values.forEach { $0.stopAcceptingNewOperations() }
        Task { @MainActor in
            await withTaskGroup(of: Void.self) { group in
                for session in active { group.addTask { await session.cancelAndWait() } }
                await group.waitForAll()
            }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
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
    let session: GUIOperationSession
    @State private var app = ""
    @State private var platform = ""
    @State private var result: EnvironmentInspection?
    @State private var error: String?
    @State private var checking = false
    @State private var device = ""
    @State private var scheme = ""
    @State private var configuration = ""
    @State private var module = ""
    @State private var variant = ""
    @State private var entrypoint = ""
    @State private var port = ""
    @State private var workflow: WorkflowResult?
    private var running: Task<Void, Never>? { session.task }
    @State private var currentStage = ""
    @State private var events: [WorkflowEvent] = []
    private var cancelling: Bool { session.cancelling }
    @State private var executionID: UUID?
    @State private var devices: [RuntimeDeviceCandidate] = []
    @State private var preparation: PreparationResult?
    @State private var repositoryTrusted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(directory.path).font(.headline).textSelection(.enabled)
            HStack {
                Picker("앱", selection: $app) {
                    Text("자동 선택").tag("")
                    ForEach(result?.selection.candidates ?? [], id: \.id) { candidate in
                        Text("\(candidate.id) · \(candidate.framework.displayName)").tag(candidate.id)
                    }
                }.disabled(checking || running != nil)
                Picker("플랫폼", selection: $platform) {
                    Text("자동 선택").tag("")
                    Text("iOS").tag("ios")
                    Text("Android").tag("android")
                }.disabled(checking || running != nil)
                Button("환경 확인") { inspect() }.keyboardShortcut("r").disabled(checking || running != nil)
            }
            HStack {
                Picker("기기", selection: $device) {
                    Text("설정 또는 단일 후보").tag("")
                    ForEach(devices, id: \.id) { candidate in
                        Text("\(candidate.name) / \(candidate.detail)").tag(candidate.id)
                    }
                }
                if platform == "android" || (platform.isEmpty && result?.selection.platform == .android) {
                    TextField("Module (설정 또는 단일 후보)", text: $module)
                    TextField("Variant (설정 또는 debug)", text: $variant)
                } else {
                    TextField("Scheme (설정 또는 단일 후보)", text: $scheme)
                    TextField("Configuration (Debug)", text: $configuration)
                }
            }.disabled(checking || running != nil)
            if result?.selection.selected?.framework == .reactNative {
                TextField("Metro port (8081)", text: $port).disabled(checking || running != nil)
            } else if result?.selection.selected?.framework == .flutter {
                HStack {
                    TextField("Entrypoint (lib/main.dart)", text: $entrypoint)
                    TextField("VM service port (자동 선택)", text: $port)
                }.disabled(checking || running != nil)
            }
            HStack {
                Button("준비 계획 확인") { prepare() }.disabled(checking || running != nil)
                Toggle("저장소 스크립트 신뢰", isOn: $repositoryTrusted)
                    .help("준비 승인과 별개입니다. 라이선스 동의와 관리자 권한을 대신하지 않습니다.")
                    .disabled(checking || running != nil)
                Button("현재 계획 승인·준비") { prepare(approvedPlanID: preparation?.plan?.id) }
                    .disabled(checking || running != nil || preparation?.plan == nil)
            }
            if let preparation {
                VStack(alignment: .leading, spacing: 4) {
                    Text("setup: \(preparation.operation.state) / exit \(preparation.exitCode)").font(.headline)
                    if let plan = preparation.plan {
                        Text("승인 대상 plan-id: \(plan.id)").font(.caption)
                        Text("\(plan.projectKind) 준비 대상: \(plan.platforms.map { $0.platform.rawValue }.joined(separator: ", "))")
                        ScrollView {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(plan.inspectionLines, id: \.self) { Text($0) }
                                ForEach(plan.steps, id: \.id) { step in
                                    Text("\(step.id) [\(step.kind)] → \(step.target)")
                                    if let required = step.required { Text("요구: \(required)") }
                                    if let command = step.command { Text("명령: \(command)") }
                                    if let advice = step.remediation { Text(advice.summary) }
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(height: 150)
                        Text(plan.platforms.map { "\($0.platform.rawValue): \($0.state)" }.joined(separator: " / "))
                    }
                    if let error = preparation.operation.error { Text(error).foregroundStyle(.red) }
                    if !preparation.operation.completed.isEmpty { Text("완료한 변경: \(preparation.operation.completed.joined(separator: ", "))") }
                    if !preparation.operation.remaining.isEmpty { Text("남은 작업: \(preparation.operation.remaining.joined(separator: ", "))") }
                    ForEach(preparation.operation.changedFiles, id: \.self) { Text("변경 파일: \($0)") }
                    if let next = preparation.operation.nextAction { Text("다음 행동: \(next)") }
                    if let log = preparation.operation.log { Text("설치 로그: \(log)") }
                }.textSelection(.enabled)
            }
            HStack {
                Button("빌드") { execute(.build) }.disabled(checking || running != nil)
                Button("실행") { execute(.up) }.disabled(checking || running != nil)
                Button("종료") { execute(.down) }.disabled(checking || running != nil)
                if running != nil {
                    ProgressView().controlSize(.small)
                    Text(cancelling ? "취소 중" : currentStage)
                    Button("작업 취소") { session.cancel() }.disabled(cancelling)
                }
            }
            if let workflow {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(workflow.operation.kind.rawValue): \(workflow.operation.state) / exit \(workflow.exitCode)").font(.headline)
                    if let message = workflow.up?.failure?.message ?? workflow.down?.failure?.message { Text(message).foregroundStyle(.red) }
                    ForEach(workflow.down?.toolFailures ?? [], id: \.self) { Text($0).foregroundStyle(.red) }
                    ForEach(workflow.down?.items ?? [], id: \.id) { item in
                        Text("\(item.id): \(item.status.rawValue)\(item.detail.map { " — \($0)" } ?? "")")
                    }
                    if !workflow.operation.requiredInput.isEmpty { Text("선택 필요: \(workflow.operation.requiredInput.joined(separator: ", "))") }
                    if !workflow.operation.schemes.isEmpty { Text("Scheme 후보: \(workflow.operation.schemes.joined(separator: ", "))") }
                    if !workflow.operation.configurations.isEmpty { Text("Configuration 후보: \(workflow.operation.configurations.joined(separator: ", "))") }
                    if !workflow.operation.modules.isEmpty { Text("Module 후보: \(workflow.operation.modules.joined(separator: ", "))") }
                    if !workflow.operation.variants.isEmpty { Text("Variant 후보: \(workflow.operation.variants.joined(separator: ", "))") }
                    if let next = workflow.operation.nextAction { Text("다음 행동: \(next)") }
                    ForEach(workflow.operation.remaining, id: \.self) { Text("남은 작업: \($0)") }
                    if let uri = workflow.operation.developmentServiceURI { Text("Flutter VM service: \(uri)") }
                    if let log = workflow.up?.context.buildLog { Text("빌드 로그: \(log)") }
                }.textSelection(.enabled)
            }
            if !events.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(events, id: \.sequence) { event in
                            Text("\(event.stageId ?? event.kind): \(event.state)\(event.detail.map { " — \($0)" } ?? "")")
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                }.frame(maxHeight: 130)
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
            .onChange(of: platform) { _, _ in
                device = ""; devices = []; workflow = nil
                scheme = ""; configuration = ""; module = ""; variant = ""
                port = ""
            }
            .onChange(of: app) { _, _ in
                device = ""; devices = []; workflow = nil
                preparation = nil; repositoryTrusted = false
                scheme = ""; configuration = ""; module = ""; variant = ""
                entrypoint = ""; port = ""
            }
            .onDisappear { session.cancel() }
    }

    @MainActor private func inspect() {
        guard !checking, running == nil else { return }
        checking = true
        error = nil
        let environment = ProcessInfo.processInfo.environment
        let input = ProjectInspectionInput(directory: directory, environment: environment,
                                           app: app.isEmpty ? nil : app, platform: ProjectPlatform(rawValue: platform),
                                           entrypoint: entrypoint.isEmpty ? nil : entrypoint)
        session.start {
            defer { checking = false }
            do { result = try await EnvironmentInspection.run(input: input,
                scheme: scheme.isEmpty ? nil : scheme, configuration: configuration.isEmpty ? nil : configuration) }
            catch { self.error = error.localizedDescription }
        }
    }

    @MainActor private func execute(_ kind: WorkflowKind) {
        guard !checking, running == nil else { return }
        let selectedPlatform = ProjectPlatform(rawValue: platform) ?? result?.selection.platform
        let usesPort = kind == .up || (kind == .build && result?.selection.selected?.framework == .reactNative)
        if usesPort, !port.isEmpty, Int(port).map({ (1...65535).contains($0) }) != true {
            error = "포트는 1부터 65535까지의 정수로 입력하세요."
            return
        }
        error = nil
        workflow = nil
        events = []
        currentStage = "선택과 환경 확인"
        let generation = UUID()
        executionID = generation
        let input = WorkflowInput(project: ProjectInspectionInput(directory: directory,
            environment: ProcessInfo.processInfo.environment, app: app.isEmpty ? nil : app,
            platform: ProjectPlatform(rawValue: platform), entrypoint: entrypoint.isEmpty ? nil : entrypoint),
            device: (kind == .up || (kind == .build && selectedPlatform == .ios)) && !device.isEmpty ? device : nil,
            scheme: kind != .down && !scheme.isEmpty ? scheme : nil,
            configuration: kind != .down && !configuration.isEmpty ? configuration : nil,
            module: kind != .down && !module.isEmpty ? module : nil,
            variant: kind != .down && !variant.isEmpty ? variant : nil,
            port: usesPort && !port.isEmpty ? Int(port) : nil)
        session.start {
            let output = await WorkflowExecution.run(kind, input: input) { event in
                Task { @MainActor in
                    guard executionID == generation else { return }
                    events.append(event)
                    if events.count > 30 { events.removeFirst(events.count - 30) }
                    if let stage = event.stageId { currentStage = "\(stage): \(event.state)" }
                }
            }
            workflow = output
            if !output.operation.devices.isEmpty { devices = output.operation.devices }
        }
    }

    @MainActor private func prepare(approvedPlanID: String? = nil) {
        guard !checking, running == nil else { return }
        let input = ProjectInspectionInput(directory: directory, environment: ProcessInfo.processInfo.environment,
            app: app.isEmpty ? nil : app, platform: ProjectPlatform(rawValue: platform),
                                           entrypoint: entrypoint.isEmpty ? nil : entrypoint)
        let trust = repositoryTrusted
        let generation = UUID()
        executionID = generation
        events = []; currentStage = "준비 조건 확인"
        session.start {
            let output = await PreparationExecution.run(input: input, planOnly: approvedPlanID == nil,
                approvedPlanID: approvedPlanID, trustRepository: trust) { event in
                Task { @MainActor in
                    guard executionID == generation else { return }
                    events.append(event)
                    if events.count > 30 { events.removeFirst(events.count - 30) }
                    currentStage = "\(event.stageId ?? event.kind): \(event.state)"
                }
            }
            guard executionID == generation else { return }
            preparation = output
        }
    }
}
#else
@main struct RunstirApp {
    static func main() { print("Runstir GUI requires macOS.") }
}
#endif

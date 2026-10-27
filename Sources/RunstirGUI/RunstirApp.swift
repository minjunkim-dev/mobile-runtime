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
        // The key window receives performClose, so Cmd-W reaches the same close sheet as the title bar.
        appMenu.addItem(withTitle: "창 닫기", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
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
        panel.message = "Simulator .app, 실기기 Development·Ad Hoc .app·.ipa 또는 단일 APK를 선택하세요. 파일 선택으로 설치하지 않습니다."
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
        // A requested cancellation cannot be withdrawn, so a second close only waits for it.
        if session.cancelling {
            session.cancel { sender.close() }
            announce("취소가 끝나면 창을 닫습니다. \(session.statusText)")
            return false
        }
        let alert = NSAlert()
        alert.messageText = "이 창에서 작업이 진행 중입니다."
        alert.informativeText = """
            현재 상태: \(session.statusText)
            작업 계속은 창과 작업을 그대로 둡니다. 취소 후 닫기는 새 단계를 막고 실행 중인 도구가 반환된 뒤 창을 닫습니다.
            완료한 설치, 실행한 모바일 앱과 기기는 창을 닫아도 종료하지 않습니다. 프로젝트 앱은 프로젝트 창의 종료(down)로만 종료합니다.
            """
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
        let lines = sender.windows.compactMap { window in
            sessions[ObjectIdentifier(window)].flatMap { $0.task == nil ? nil : "\(window.title) — \($0.statusText)" }
        }
        alert.informativeText = lines.joined(separator: "\n")
            + "\n작업 계속은 Runstir와 모든 작업을 유지합니다. 모두 취소 후 종료는 새 단계를 막고 모든 도구가 반환될 때까지 창을 유지한 뒤 종료합니다. 실행을 마친 모바일 앱과 기기는 종료하지 않습니다."
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

extension GUIOperationSession {
    /// Cancellation names the step still returning instead of claiming a stop it cannot force.
    var statusText: String {
        guard cancelling else { return progress }
        return "취소하는 중입니다. 실행 중인 도구가 끝날 때까지 기다려 주세요."
            + (progress.isEmpty ? "" : " 현재 단계: \(progress)")
    }
}

/// Cancellation and missing input are not labeled as failures.
func outcomeLabel(_ state: String) -> String {
    switch state {
    case "cancelled": "취소됨"
    case "needs-selection": "선택 필요"
    case "needs-approval": "승인 필요"
    case "waiting-manual": "직접 준비 필요"
    default: "실패"
    }
}

/// VoiceOver hears results and state changes without moving the keyboard focus.
@MainActor func announce(_ text: String) {
    AccessibilityNotification.Announcement(text).post()
}

struct InspectionView: View {
    private enum Field: Hashable { case app, platform, device, scheme, configuration, module, variant, entrypoint, port, trust, recheck, plan, approve, preparedDependencies }
    private enum Region: Hashable { case inspection, preparation, workflow }
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
    @State private var preparedDependencies = false
    @State private var targets: WorkflowOperation?
    @State private var workflow: WorkflowResult?
    private var running: Task<Void, Never>? { session.task }
    @State private var events: [WorkflowEvent] = []
    private var cancelling: Bool { session.cancelling }
    @State private var executionID: UUID?
    @State private var devices: [RuntimeDeviceCandidate] = []
    @State private var preparation: PreparationResult?
    @State private var repositoryTrusted = false
    @FocusState private var focus: Field?
    /// Controls stay disabled until the session ends, so focus moves only once the window is idle.
    @State private var nextFocus: Field?
    @AccessibilityFocusState private var resultFocus: Region?
    private var busy: Bool { checking || running != nil || !session.acceptsNewOperations }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(directory.path).font(.headline).textSelection(.enabled)
            HStack {
                Picker("앱", selection: $app) {
                    Text("자동 선택").tag("")
                    ForEach(result?.selection.candidates ?? [], id: \.id) { candidate in
                        Text("\(candidate.id) · \(candidate.framework.displayName)").tag(candidate.id)
                    }
                }.disabled(busy).focused($focus, equals: .app)
                Picker("플랫폼", selection: $platform) {
                    Text("자동 선택").tag("")
                    ForEach(selectedCandidate?.platforms ?? [], id: \.rawValue) { candidate in
                        Text(candidate == .ios ? "iOS" : "Android").tag(candidate.rawValue)
                    }
                }.disabled(busy || selectedCandidate == nil).focused($focus, equals: .platform)
                Button(result == nil ? "환경 확인" : "환경 다시 확인") { inspect() }.keyboardShortcut("r").disabled(busy)
                    .focused($focus, equals: .recheck)
                    .accessibilityHint("선택한 앱과 플랫폼의 현재 상태를 다시 확인합니다. 변경하지 않습니다.")
            }
            HStack {
                Picker("기기", selection: $device) {
                    Text("기기를 선택하세요").tag("")
                    ForEach(devices, id: \.id) { candidate in
                        Text("\(candidate.name) / \(candidate.detail)\(candidate.origin.map { " / " + $0.displayName } ?? "")\(candidate.avdDirectory.map { " / " + $0 } ?? "")").tag(candidate.id)
                    }
                }.disabled(devices.isEmpty).focused($focus, equals: .device)
                if platform == "android" || (platform.isEmpty && result?.selection.platform == .android) {
                    choicePicker("모듈", selection: $module, options: targets?.modules ?? [], defaultValue: targets?.module, field: .module)
                    choicePicker("빌드 변형", selection: $variant, options: targets?.variants ?? [], defaultValue: targets?.variant, field: .variant)
                } else {
                    choicePicker("Scheme", selection: $scheme, options: targets?.schemes ?? [], defaultValue: targets?.scheme, field: .scheme)
                    choicePicker("빌드 구성", selection: $configuration, options: targets?.configurations ?? [], defaultValue: targets?.configuration, field: .configuration)
                }
            }.disabled(busy)
            if let action = targets?.nextAction { Text("선택 항목을 확인하지 못했습니다: \(action)").foregroundStyle(.secondary) }

            if result?.selection.selected?.framework == .reactNative {
                TextField("Metro 포트 (기본값: 8081)", text: $port).disabled(busy).focused($focus, equals: .port)
                    .accessibilityLabel("Metro 포트").help("1부터 65535까지 입력하세요. 비워 두면 8081을 사용합니다.")
            } else if result?.selection.selected?.framework == .flutter {
                HStack {
                    TextField("실행 파일 경로 (기본값: lib/main.dart)", text: $entrypoint)
                        .focused($focus, equals: .entrypoint).accessibilityLabel("Flutter 실행 파일 경로")
                        .help("선택한 Flutter 앱 안에 있는 Dart 파일의 상대 경로를 입력하세요.")
                    TextField("VM 서비스 포트 (자동 할당)", text: $port).focused($focus, equals: .port)
                        .accessibilityLabel("Flutter VM 서비스 포트").help("1부터 65535까지 입력하세요. 비워 두면 사용 가능한 포트를 할당합니다.")
                }.disabled(busy)
            }
            if result?.selection.selected?.framework == .reactNative || result?.selection.selected?.framework == .flutter {
                Toggle("미리 준비한 의존성 사용", isOn: $preparedDependencies)
                    .disabled(busy).focused($focus, equals: .preparedDependencies)
                    .accessibilityIdentifier("project.prepared-dependencies")
                    .accessibilityHint("RN·Flutter의 빌드와 실행, Flutter 환경 확인에 적용합니다. 의존성 재설치와 lock 정렬·Flutter 플러그인 정합성 재검증을 생략합니다. Flutter 파일 링크는 Git에 기록된 프로젝트 내부 소스만 허용합니다.")
                Text("의존성 재설치와 lock 정렬·Flutter 플러그인 정합성 재검증을 생략합니다. Flutter는 환경 확인에도 적용합니다. 준비 상태를 직접 확인한 경우에 선택하세요. Flutter 파일 링크는 Git에 기록된 프로젝트 내부 소스만 허용합니다.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Button("준비 계획 확인") { prepare() }.disabled(busy).focused($focus, equals: .plan)
                Toggle("저장소 스크립트 실행 허용", isOn: $repositoryTrusted)
                    .help("이 저장소의 준비 스크립트 실행을 허용합니다. 변경 계획의 승인과 라이선스 동의·관리자 권한은 각각 필요합니다.")
                    .disabled(busy).focused($focus, equals: .trust)
                Button("계획 승인하고 준비") { prepare(approvedPlanID: preparation?.plan?.id) }
                    .disabled(busy || preparation?.plan == nil).focused($focus, equals: .approve)
                    .accessibilityHint(preparation?.plan.map { "plan-id \($0.id)만 승인합니다. 저장소 스크립트 실행 허용은 별도입니다." } ?? "먼저 준비 계획을 확인하세요.")
            }
            if let preparation {
                VStack(alignment: .leading, spacing: 4) {
                    Text("환경 준비: \(GUIText.state(preparation.operation.state))").help("종료 코드: \(preparation.exitCode)").font(.headline)
                        .accessibilityAddTraits(.isHeader).accessibilityFocused($resultFocus, equals: .preparation)
                    if preparation.operation.state == "waiting-manual" {
                        Text("아래 단계를 직접 마친 뒤 환경과 준비 계획을 다시 확인하세요.")
                    }
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
                        Text(plan.platforms.map { "\($0.platform.rawValue): \(GUIText.state($0.state))" }.joined(separator: " / "))
                    }
                    if let error = preparation.operation.error { Text("\(outcomeLabel(preparation.operation.state)): \(error)").foregroundStyle(.red) }
                    if !preparation.operation.completed.isEmpty { Text("완료한 변경: \(preparation.operation.completed.joined(separator: ", "))") }
                    if !preparation.operation.remaining.isEmpty { Text("남은 작업: \(preparation.operation.remaining.joined(separator: ", "))") }
                    ForEach(preparation.operation.changedFiles, id: \.self) { Text("변경 파일: \($0)") }
                    if let next = preparation.operation.nextAction { Text("다음 단계: \(next)") }
                    if let log = preparation.operation.log { Text("설치 로그: \(log)") }
                }.textSelection(.enabled)
            }
            HStack {
                Button("빌드") { execute(.build) }.disabled(busy)
                Button("실행") { execute(.up) }.disabled(busy)
                Button("종료") { execute(.down) }.disabled(busy)
                    .accessibilityHint("이 프로젝트가 실행한 앱과 개발 서버를 종료합니다. 다른 프로젝트의 자원은 유지합니다.")
                if running != nil {
                    ProgressView().controlSize(.small).accessibilityHidden(true)
                    // Before the growing status text, so the button does not move while it is aimed at.
                    Button("작업 취소") { cancel() }.disabled(cancelling)
                        .accessibilityHint("이 창의 작업에서 새 단계를 시작하지 않습니다. 완료한 변경과 다른 창의 작업은 유지합니다.")
                    Text(session.statusText).accessibilityLabel("작업 상태").accessibilityValue(session.statusText)
                }
            }
            if let workflow {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(GUIText.operation(workflow.operation.kind)): \(GUIText.state(workflow.operation.state))").help("종료 코드: \(workflow.exitCode)").font(.headline)
                        .accessibilityAddTraits(.isHeader).accessibilityFocused($resultFocus, equals: .workflow)
                    if let message = workflow.up?.failure?.message ?? workflow.down?.failure?.message { Text("\(outcomeLabel(workflow.operation.state)): \(message)").foregroundStyle(.red) }
                    ForEach(workflow.down?.toolFailures ?? [], id: \.self) { Text($0).foregroundStyle(.red) }
                    ForEach(workflow.down?.items ?? [], id: \.id) { item in
                        Text("\(item.id): \(item.status.rawValue)\(item.detail.map { " — \($0)" } ?? "")")
                    }
                    if !workflow.operation.requiredInput.isEmpty { Text("선택 필요: \(workflow.operation.requiredInput.map(GUIText.field).joined(separator: ", "))") }
                    if !workflow.operation.schemes.isEmpty { Text("Scheme 선택지: \(workflow.operation.schemes.joined(separator: ", "))") }
                    if !workflow.operation.configurations.isEmpty { Text("빌드 구성 선택지: \(workflow.operation.configurations.joined(separator: ", "))") }
                    if !workflow.operation.modules.isEmpty { Text("모듈 선택지: \(workflow.operation.modules.joined(separator: ", "))") }
                    if !workflow.operation.variants.isEmpty { Text("빌드 변형 선택지: \(workflow.operation.variants.joined(separator: ", "))") }
                    if let next = workflow.operation.nextAction { Text("다음 단계: \(next)") }
                    ForEach(workflow.operation.remaining, id: \.self) { Text("남은 작업: \($0)") }
                    if let uri = workflow.operation.developmentServiceURI { Text("Flutter VM 서비스: \(uri)") }
                    if workflow.operation.preparedDependencies == true { Text("미리 준비한 의존성 사용: 재설치·lock 정렬·Flutter 플러그인 정합성 재검증을 생략했습니다") }
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
            if let error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            if let result {
                Text(inspectionSummary(result)).font(.headline)
                    .accessibilityAddTraits(.isHeader).accessibilityFocused($resultFocus, equals: .inspection)
                if let selected = result.selection.selected {
                    Text("검사 대상: \(selected.id) / \(result.selection.platform?.rawValue ?? "플랫폼 선택 필요")")
                }
                if let selectionError = result.selection.error { Text("실패: \(selectionError)").foregroundStyle(.red) }
                if !result.selection.requiredInput.isEmpty {
                    Text("선택 필요: \(result.selection.requiredInput.map(GUIText.field).joined(separator: ", "))")
                }
                if result.selection.candidates.isEmpty { Text("프로젝트를 찾지 못했습니다. 호스트 검사만 표시합니다.") }
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(result.report.checks, id: \.id) { check in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("[\(GUIText.state(check.status.rawValue))] \(check.title)").font(.headline)
                                Text(check.id).font(.caption)
                                if let observed = check.outcome.observed { Text(observed) }
                                if let reason = check.outcome.reason { Text(reason) }
                                if let remediation = check.outcome.remediation {
                                    Text(remediation.summary)
                                    if let command = remediation.command { Text(command).font(.system(.body, design: .monospaced)) }
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading).accessibilityElement(children: .combine)
                        }
                    }.textSelection(.enabled)
                }
            }
            Spacer(minLength: 0)
        }.padding(20).task { inspect() }
            .onChange(of: platform) { _, _ in
                device = ""; devices = []; targets = nil; workflow = nil
                preparation = nil; repositoryTrusted = false
                scheme = ""; configuration = ""; module = ""; variant = ""
                port = ""
                preparedDependencies = false
                inspect()
            }
            .onChange(of: app) { _, _ in
                platform = ""
                device = ""; devices = []; targets = nil; workflow = nil
                preparation = nil; repositoryTrusted = false
                scheme = ""; configuration = ""; module = ""; variant = ""
                entrypoint = ""; port = ""
                preparedDependencies = false
                inspect()
            }
            .onChange(of: scheme) { _, _ in configuration = ""; refreshTargets() }
            .onChange(of: module) { _, _ in variant = ""; refreshTargets() }
            .onChange(of: configuration) { _, _ in refreshTargets() }
            .onChange(of: variant) { _, _ in refreshTargets() }
            .onChange(of: preparedDependencies) { _, _ in
                // Only Flutter inspection depends on this choice; RN keeps its selected device.
                if result?.selection.selected?.framework == .flutter { refreshTargets() }
            }
            .onChange(of: busy) { _, busy in
                if !busy, let nextFocus { focus = nextFocus; self.nextFocus = nil }
            }
            .onDisappear { session.cancel() }
    }

    private var selectedCandidate: ProjectCandidate? {
        app.isEmpty ? result?.selection.selected : result?.selection.candidates.first { $0.id == app }
    }

    private func choicePicker(_ title: String, selection: Binding<String>, options: [String], defaultValue: String?, field: Field) -> some View {
        Picker(title, selection: selection) {
            Text(defaultValue.map { "기본값: \($0)" } ?? (options.isEmpty ? "환경 확인이 필요합니다" : "선택하세요")).tag("")
            ForEach(options, id: \.self) { Text($0).tag($0) }
        }.disabled(options.isEmpty).focused($focus, equals: field)
            .accessibilityHint("프로젝트에서 확인한 항목 중에서 선택하세요.")
    }

    private func refreshTargets() {
        device = ""; devices = []; targets = nil; workflow = nil
        inspect()
    }

    @MainActor private func inspect() {
        guard !busy else { return }
        checking = true
        error = nil
        let environment = ProcessInfo.processInfo.environment
        let input = ProjectInspectionInput(directory: directory, environment: environment,
                                           app: app.isEmpty ? nil : app, platform: ProjectPlatform(rawValue: platform),
                                           entrypoint: entrypoint.isEmpty ? nil : entrypoint)
        // Inspect the same Flutter inputs that build/up will accept with this toggle.
        let prepared = result?.selection.selected?.framework == .flutter && preparedDependencies
        let generation = UUID()
        executionID = generation
        session.progress = "환경 확인 중"
        session.start {
            defer { checking = false }
            do {
                let inspection = try await EnvironmentInspection.run(input: input,
                    scheme: scheme.isEmpty ? nil : scheme, configuration: configuration.isEmpty ? nil : configuration,
                    module: module.isEmpty ? nil : module, variant: variant.isEmpty ? nil : variant, includeTargets: true,
                    preparedDependencies: prepared) { detail in
                    Task { @MainActor in if executionID == generation, session.task != nil { session.progress = "환경 확인 중 — \(detail)" } }
                }
                result = inspection
                targets = inspection.targets
                devices = inspection.targets?.devices ?? []
                if !device.isEmpty && !devices.contains(where: { $0.id == device }) { device = "" }
                if let targets = inspection.targets {
                    if !scheme.isEmpty && !targets.schemes.contains(scheme) { scheme = "" }
                    if !configuration.isEmpty && !targets.configurations.contains(configuration) { configuration = "" }
                    if !module.isEmpty && !targets.modules.contains(module) { module = "" }
                    if !variant.isEmpty && !targets.variants.contains(variant) { variant = "" }
                }
                nextFocus = field(for: inspection.selection.requiredInput + (inspection.targets?.requiredInput ?? [])) ?? .recheck
                resultFocus = .inspection
                announce(inspectionSummary(inspection))
            } catch is CancellationError {
                self.error = nil
                nextFocus = .recheck
                announce("환경 확인 취소됨. 변경하지 않았습니다.")
            } catch {
                self.error = error.localizedDescription
                nextFocus = .recheck
                announce("환경 확인 실패: \(error.localizedDescription)")
            }
        }
    }

    private func inspectionSummary(_ result: EnvironmentInspection) -> String {
        if result.selection.error != nil { return "환경 확인: 선택 오류" }
        let required = result.selection.requiredInput + (result.targets?.requiredInput ?? [])
        if !required.isEmpty { return "환경 확인: \(required.map(GUIText.field).joined(separator: ", ")) 선택이 필요합니다" }
        let count = { (status: CheckStatus) in result.report.checks.filter { $0.status == status }.count }
        return "환경 확인: 오류 \(count(.error))개 · 주의 \(count(.warning))개 · 확인 불가 \(count(.unknown))개"
    }

    private func field(for input: [String]) -> Field? {
        let fields: [String: Field] = ["--app": .app, "--platform": .platform, "--device": .device, "--scheme": .scheme,
            "--configuration": .configuration, "--entrypoint": .entrypoint, "--port": .port, "--module": .module, "--variant": .variant, "--trust-repository": .trust]
        return input.lazy.compactMap { fields[$0] }.first
    }

    @MainActor private func cancel() {
        session.cancel()
        announce(session.statusText)
    }

    @MainActor private func execute(_ kind: WorkflowKind) {
        guard !busy else { return }
        let selectedPlatform = ProjectPlatform(rawValue: platform) ?? result?.selection.platform
        let usesPort = kind == .up || (kind == .build && result?.selection.selected?.framework == .reactNative)
        if (kind == .up || (kind == .build && selectedPlatform == .ios && selectedCandidate?.framework == .flutter)), device.isEmpty {
            error = "실행할 기기를 선택하세요."
            focus = .device
            return
        }
        if usesPort, !port.isEmpty, Int(port).map({ (1...65535).contains($0) }) != true {
            error = "포트는 1부터 65535까지의 정수로 입력하세요."
            return
        }
        error = nil
        workflow = nil
        events = []
        session.progress = "선택과 환경 확인"
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
            port: usesPort && !port.isEmpty ? Int(port) : nil,
            preparedDependencies: kind != .down && (result?.selection.selected?.framework == .reactNative || result?.selection.selected?.framework == .flutter) && preparedDependencies)
        session.start {
            let output = await WorkflowExecution.run(kind, input: input) { event in
                Task { @MainActor in
                    guard executionID == generation else { return }
                    events.append(event)
                    if events.count > 30 { events.removeFirst(events.count - 30) }
                    session.record(event)
                }
            }
            workflow = output
            if kind != .down { targets = output.operation; devices = output.operation.devices }
            switch output.operation.state {
            case "needs-selection": nextFocus = field(for: output.operation.requiredInput) ?? .recheck
            case "succeeded": break
            default: nextFocus = .recheck
            }
            resultFocus = .workflow
            announce("\(GUIText.operation(output.operation.kind)): \(GUIText.state(output.operation.state))")
        }
    }

    @MainActor private func prepare(approvedPlanID: String? = nil) {
        guard !busy else { return }
        let input = ProjectInspectionInput(directory: directory, environment: ProcessInfo.processInfo.environment,
            app: app.isEmpty ? nil : app, platform: ProjectPlatform(rawValue: platform),
                                           entrypoint: entrypoint.isEmpty ? nil : entrypoint)
        let trust = repositoryTrusted
        let generation = UUID()
        executionID = generation
        events = []; session.progress = "준비 조건 확인"
        session.start {
            let output = await PreparationExecution.run(input: input, planOnly: approvedPlanID == nil,
                approvedPlanID: approvedPlanID, trustRepository: trust) { event in
                Task { @MainActor in
                    guard executionID == generation else { return }
                    events.append(event)
                    if events.count > 30 { events.removeFirst(events.count - 30) }
                    session.record(event)
                }
            }
            guard executionID == generation else { return }
            preparation = output
            switch output.operation.state {
            case "needs-approval": nextFocus = output.plan == nil ? .recheck : .approve
            case "needs-selection": nextFocus = field(for: output.operation.requiredInput) ?? .recheck
            case "waiting-manual": nextFocus = field(for: output.operation.requiredInput) ?? .plan
            case "succeeded": break
            default: nextFocus = .recheck
            }
            resultFocus = .preparation
            announce("환경 준비: \(GUIText.state(output.operation.state))")
        }
    }
}
#else
@main struct RunstirApp {
    static func main() { print("Runstir GUI requires macOS.") }
}
#endif

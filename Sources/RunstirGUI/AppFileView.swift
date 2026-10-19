#if os(macOS)
import Core
import EnvironmentKit
import SwiftUI

struct AppFileView: View {
    let file: URL
    let session: GUIOperationSession
    @State private var result: AppFileResult?
    @State private var device = ""
    @State private var events: [WorkflowEvent] = []
    @State private var executionID: UUID?
    @State private var currentStage = ""
    @State private var downgradeAcknowledged = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(file.path).font(.headline).textSelection(.enabled)
            Text("파일 확인 → 기기 선택 → 변경 계획 승인 → 설치 → 실행 요청")
            Text("소스 빌드와 환경 준비를 자동으로 시작하지 않습니다.").font(.caption)
            HStack {
                Button("파일 다시 확인") { execute(inspectOnly: true) }.keyboardShortcut("r")
                Picker("실행 기기", selection: $device) {
                    Text("기기를 선택하세요").tag("")
                    ForEach(result?.operation.devices ?? [], id: \.id) { candidate in
                        Text("\(candidate.name) / OS \(candidate.os) / \(candidate.ready ? "준비됨" : "수동 준비 필요")").tag(candidate.id)
                    }
                }
                Button("변경 계획 확인") { execute(planOnly: true) }.disabled(device.isEmpty)
            }.disabled(session.task != nil || !session.acceptsNewOperations)
            if let operation = result?.operation {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if let artifact = operation.artifact {
                            Text(artifact.metadata.name ?? "앱 이름 확인 불가").font(.headline)
                            Text("\(artifact.metadata.platform.rawValue) · 앱 ID: \(artifact.metadata.appID)")
                            Text("표시 버전: \(artifact.metadata.version ?? "확인 불가") · 빌드: \(artifact.metadata.build)")
                            Text("architecture: \(artifact.metadata.architectures.joined(separator: ", ")) · 최소 OS: \(artifact.metadata.minimumOS)")
                            Text("출처: 사용자 선택 파일 · 제작자 신뢰와 안전성은 확인하지 않았습니다.")
                            Text("\(artifact.contentIdentityAlgorithm): \(artifact.contentIdentity)").font(.caption)
                            Text(artifact.metadata.signatureCondition)
                            if let signer = artifact.metadata.signingIdentity { Text("signer SHA-256: \(signer)").font(.caption) }
                        }
                        if let plan = operation.plan, plan.device.id == device {
                            Divider()
                            Text("승인 대상: \(plan.device.name) / \(plan.device.id)").font(.headline)
                            Text("기존 앱: \(plan.installed.state) · 표시 버전 \(plan.installed.version ?? "확인 불가") · 빌드 \(plan.installed.build ?? "확인 불가")")
                            Text(plan.replacement ? "같은 앱을 데이터 보존 방식으로 교체합니다. 자동 삭제와 초기화는 하지 않습니다." : "선택한 앱을 설치하고 실행을 요청합니다.")
                            ForEach(plan.warnings, id: \.self) { Text($0) }
                            if plan.requiresRiskApproval {
                                Toggle("이전 또는 비교 불가 빌드의 위험을 확인했습니다. 설치 성공과 데이터 보존은 보장하지 않습니다.", isOn: $downgradeAcknowledged)
                                    .disabled(session.task != nil)
                            }
                            Text("plan-id: \(plan.id)").font(.caption)
                            Button("현재 계획 승인·설치·실행 요청") { execute(approval: plan.approval) }
                                .disabled(session.task != nil || !session.acceptsNewOperations || (plan.requiresRiskApproval && !downgradeAcknowledged))
                            Text("실행 직전에 파일·기기·기존 앱 상태를 다시 확인합니다.").font(.caption)
                        }
                        Divider()
                        Text("작업 상태: \(operation.state)")
                        Text("설치 관측: \(operation.installation)")
                        Text("실행 요청: \(operation.launch)")
                        Text("앱 실행 상태: \(operation.running)")
                        Text("첫 화면 증거: 확인하지 않음")
                        Text("외부 개발 서버 조건: 확인하지 않음. 서버를 시작하거나 연결하지 않았습니다.")
                        if let installed = operation.installed {
                            Text("현재 설치 재관측: \(installed.state) · 빌드 \(installed.build ?? "확인 불가")")
                            if let detail = installed.detail { Text(detail) }
                        }
                        if let error = operation.error { Text(error).foregroundStyle(.red) }
                        if let conflict = operation.conflict {
                            Text("충돌: \(conflict.key.rawValue)")
                            if let owner = conflict.owner { Text("소유 작업: \(owner.command) / \(owner.project)") }
                        }
                        if let next = operation.nextAction { Text("다음 행동: \(next)") }
                        if !operation.completed.isEmpty { Text("완료 단계: \(operation.completed.joined(separator: ", "))") }
                    }.frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                }
            }
            if session.task != nil {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(session.cancelling ? "취소와 보존 처리 중" : currentStage)
                    Button("이 작업 취소") { session.cancel() }.disabled(session.cancelling)
                }
            }
            DisclosureGroup("실행 상세") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(events, id: \.sequence) { event in
                            Text("\(event.stageId ?? event.kind): \(event.state)\(event.detail.map { " — \($0)" } ?? "")")
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                }.frame(maxHeight: 160)
            }
            Spacer(minLength: 0)
        }.padding(20).task { execute(inspectOnly: true) }
            .onChange(of: device) { _, _ in downgradeAcknowledged = false }
    }

    @MainActor private func execute(inspectOnly: Bool = false, planOnly: Bool = false, approval: String? = nil) {
        guard session.task == nil, session.acceptsNewOperations else { return }
        let input = AppFileInput(file: file, environment: ProcessInfo.processInfo.environment,
            device: device.isEmpty ? nil : device)
        let generation = UUID()
        executionID = generation
        events = []
        currentStage = "파일과 기기 확인"
        session.start {
            let output = await AppFileExecution.run(input: input, inspectOnly: inspectOnly,
                planOnly: planOnly, approvedPlanID: approval) { event in
                    Task { @MainActor in
                        guard executionID == generation else { return }
                        events.append(event)
                        if events.count > 100 { events.removeFirst(events.count - 100) }
                        currentStage = "\(event.stageId ?? event.kind): \(event.state)"
                    }
                }
            guard executionID == generation else { return }
            if result?.operation.plan?.id != output.operation.plan?.id { downgradeAcknowledged = false }
            result = output
        }
    }
}
#endif

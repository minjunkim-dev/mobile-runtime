import EnvironmentKit
import Testing

@Suite("GUI status text preserves app observations")
struct GUITextTests {
    @Test("only exact app-state prefixes are translated, keeping diagnostics and future states")
    func appRunning() {
        let detail = "pid 8123 on emulator-5554: running: unchanged"
        #expect(GUIText.appRunning("running: " + detail) == "실행 중: " + detail)
        #expect(GUIText.appRunning("unknown: " + detail) == "확인 불가: " + detail)
        #expect(GUIText.appRunning("running:without-space") == "running:without-space")
        #expect(GUIText.appRunning("future-state: " + detail) == "future-state: " + detail)
        #expect(GUIText.appRunning("stopped") == "종료됨")
    }
}

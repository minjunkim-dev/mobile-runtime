# #206 source75 GUI 실제 준비 증거

source `75baf9d66592bc20e0c5644ff161ec77686a6c6d`의 GUI 준비 작업을 실제로 완료했다.
이 기록은 해당 source75 실행만 다룬다. 이후 통합 head의 CI·merge·release 증거는 별도다.

- source tree: `f1b2a185d3916689a3cc4fa3e75e869498e681e8`.
- 실제 private packaged GUI: 16,276,528 B.
- GUI SHA256: `e9a463cd02272acae3756bf491f5d485804be7b62a2afb1a588a7f8d14a722c5`.
- prepared candidate 28개 입력과 guest 검증·launcher map이 일치한다.
- guest strict codesign 검사 exit는 0이다.
- GUI PID는 4261이다. launcher PID는 4259다. 시작은 2026-10-18T05:28:08Z다.
- 경로는 `$GUI_APP`, `$GUI_HOME`, `$GUI_PROJECT`, `$GUI_DEVICE_SET`로 표현한다.

Root가 hidden in-app browser의 framebuffer를 CUA로 조작했다.
screen09는 View only와 최초 계획을 표시했다.
Root가 Control UI를 켠 뒤 현재 계획 승인 버튼을 한 번 눌렀다.
repository trust는 false였다. screen10은 running을 표시했다.

최초 표시 plan ID는 `a3e2af1a92e3b6880b2cecf0b481a73cb95c85bb5beb9d8f6cc6f26d023239c4`다.
근거는 화면과 승인 전 수기 review다.
`$GUI_REVIEW/ROOT-gui-approval-v1.json`은 serialized raw plan이 아니다.

screen11은 `setup: succeeded / exit 0`을 표시했다.
완료한 변경은 `ios.simulator.create`였다.
runtime은 iOS 27.0 / 24A434 / arm64를 reuse했다.
새 private device는 정확히 1개였다.
UDID는 `E73CDA0C-0B5A-483D-B06F-8551BA403E8E`다.
기기 종류는 iPhone 18 Pro다. native after 상태는 available·Shutdown이다.
실행 전 private deviceSet 관측은 exists=true·entries={}였다. absent라고 기록하지 않는다.

screen11/12의 새 표시 plan ID는 `18b9d5f20f8b9a3565d1509f4bfbc6633ada6729a78f4d0c39ac06066812ad0e`다.
이 값은 화면에서 전사했다.
screen12 재검사 결과는 `setup: needs-approval / exit 0`이다.
runtime과 simulator는 reuse로 표시됐다. 남은 create는 표시되지 않았다.
승인이 불필요한 결과로 표현하지 않는다.
GUI의 원래 계획과 새 계획 JSON은 확보하지 못했다.
GUI의 개별 xcodebuild child exit도 확보하지 못했다.

native after08의 named preservation checks 19개가 모두 true다.
검사 범위는 fixture source/Git, SDK/tools, candidate28, 선택한 PATH/Xcode 설정, 기존 runtime/default device와 역사 입력이다.
선택한 HOME metadata에서는 `Library/Caches` 변화가 있었다.
변화의 actor는 증명하지 못했다.
이 결과는 전체 HOME·cache contents·SDK·VM disk payload의 동일성을 증명하지 않는다.
observer의 PLAN/approve/install/delete/signal 0은 관측 helper의 동작 수다.
제품 GUI의 승인·create 동작 수가 0이라는 뜻이 아니다.

Root가 app-menu Quit를 사용했다.
screen13은 Quit 메뉴를 표시했다. screen14는 GUI가 사라지고 Terminal prompt가 돌아온 모습을 표시했다.
native receipt의 GUI child 실제 exit는 0이다. 종료 시각은 2026-10-18T06:07:20Z다.
GUI PID와 이전에 관측한 descendants는 사라졌다.
관측하지 못한 child나 reparented child 전체의 부재까지 증명하지 않는다.

`$BRIDGE_REPORTS/ROOT-ACTUAL-v1.md`가 별도 native lifecycle을 기록한다.
단일 VNC connection은 client EOF로 끝났다.
Tart proxy 실제 exit는 0이다. 강제 종료는 없었다.
guest relay는 input EOF를 기록했다. 별도 native ps 검사는 guest relay 부재를 확인했다.
server와 relay의 native session도 각각 실제 exit 0으로 수집됐다.
정상 VM stop의 실제 exit는 0이다. 이후 Tart VM 5개가 모두 stopped로 관측됐다.
보호한 VM 4개의 map은 6개 시점에서 같았다.
map은 small metadata SHA와 disk stat을 다룬다. 전체 disk payload hash는 아니다.
최초 Tart boot 명령의 exit는 native handle 유실로 UNKNOWN이다.
나중 정상 stop의 성공으로 이 역사적 미관측 값을 채우지 않는다.

export는 receipt 60개와 embedded INDEX를 포함한 tar regular member 61개다.
독립 Node/fs 분석에서 receipt bytes/SHA와 tar bytes/mode/SHA mismatch는 0개다.
host copy mode를 tar mode 증거로 사용하지 않았다.
tar header checksum과 embedded INDEX bytes/SHA도 확인했다.

- tar: 8,437,760 B, SHA256 `199bdd8f6b913be839712ad6e6768f9253c0b59d0d6e59488eb7f0dec2e2d47f`.
- export INDEX: 10,947 B, SHA256 `e137582dec789dd9092f045f9ebc7be32568a84948da6e346f51375757f42b1c`.

GUI는 기존 runtime을 reuse했다.
전체 network transfer와 downloaded runtime checksum은 증명하지 않았다.
대상 프로젝트의 build/run과 release도 이 준비 성공과 별도다.
이전 d462/6e 측정은 원래 source 식별자를 유지한다.

이 공개 기록는 raw process/environment dump, 원본 screenshots, 실제 private 경로와 credentials를 포함하지 않는다.
민감 session token 파일은 읽거나 해시하거나 INDEX에 넣지 않았다.
세부 evidence logical path와 pin은 짝인 JSON에 있다.

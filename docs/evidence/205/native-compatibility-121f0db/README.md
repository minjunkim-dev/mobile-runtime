# 통합 후보 121f0db의 native 호환성 실패

2026-10-18에 실제 테스트 VM에서 source `121f0db3589fbe4c1d741a791488580469a3c993`를 실행했다.
이 기록은 실패 증거다. 수정 후보의 성공 증거로 사용하지 않는다.
[manifest](manifest.json)는 원본 다섯 파일의 bytes와 SHA256을 고정한다.

## 실제 제품 실행

[제품 결과](product-result.json)는 Simulator 생성 확인 단계의 오류를 기록한다.
[프로세스 결과](product-exit.json)의 실제 exit code는 `1`이다.
실행 시간은 약 12.39초다. 이는 전체 제품 실행 시간이다.
native `create` 한 명령의 실행 시간으로 해석하지 않는다.
관측한 자식 프로세스는 종료했다. 관측하지 못한 프로세스와 CoreSimulatorService의 내부 작업은 별개다.

`operation.completed`와 `operation.changedFiles`는 빈 배열이다.
locked Dart alignment 단계에는 진입하지 않았다.
계획 검사 중의 Dart workspace 조회와 locked alignment 실행을 구분한다.
GUI 제품은 실행하지 않았다.

## 확정 원인

[native runtime 목록](native-runtimes.json)의 iOS `27.1`, build `24A94425`는 available arm64다.
이 runtime의 `supportedDeviceTypes`에는 `iPhone-Duo` 1개만 있다.
기존 선택 로직은 이 목록을 읽지 않았다.
기존 선택 로직은 OS 범위에 맞는 `iPhone-18-Pro`를 제안했다.

기존 실패와 recovery intent를 보존했다.
Root는 동일한 profile·환경·작업 경로에서 수동 native 생성 진단을 한 번 실행했다.
Root는 같은 자원 key 네 개의 lease를 독점했다.
실행 직전 private set에는 기기가 없었다.
[수동 native 결과](manual-native-result.json)는 다음 결과를 기록한다.

- 실제 native exit code는 `147`이다.
- 오류는 `com.apple.CoreSimulator.SimError`, code `403`, `Incompatible device`다.
- 실행 후에도 private set에는 기기가 없다.
- 원래 recovery intent는 같다.

이 진단은 실제 쓰기 명령의 수동 재시도다.
이 진단은 제품의 자동 재시도나 제품 생성 성공이 아니다.
권한 범위를 넓혀야 한다는 근거도 아니다.
이후 자동 재시도와 intent 삭제는 수행하지 않았다.

## 보존 범위와 한계

[보존 결과](preservation-report.json)의 strict 검사는 실패했다.
`defaultInventory`가 다르다. 이 FAIL은 그대로 남긴다.
전체 native JSON을 비교하면 기존 iOS 27.0 기기의 `lastUsedAt` 추가 한 건만 다르다.
기기는 `CB1AD119-E201-4C9E-8E0E-AA5931E8045D`다.
추가 값은 `2026-10-18T08:55:27Z`다. 기존에는 이 key가 없었다.
기기 수, 기기 상태와 나머지 native 필드는 같다.

별도 분해 진단에서 `xcodebuild -list -json -project` 조회만으로 같은 필드 변경을 재현했다.
제품 프로세스 기록에도 정확한 프로젝트 목록 조회가 있다.
변경 시각은 제품의 실제 guest 실행 구간 안에 있다.
이 사실은 단일 필드의 원인 분류다. 전체 global inventory 보존 PASS가 아니다.

source snapshot, SDK, JDK, protected roots, global PATH, launchctl PATH와 선택 Xcode는 같다.
기존 lease 기록은 같다. 새 소유 lease 네 개는 해제 상태다.
generated input 변경은 없다.
`selectedCacheStatSame`은 false다.
전체 HOME/cache 보존은 입증하지 않았다.
원본 VM 다섯 개는 중지 상태다.
원본 VM의 작은 metadata SHA와 disk stat은 같다.
원본 VM 전체 디스크 내용은 hash하지 않았다.

실패 기록을 내보낸 뒤 테스트 VM을 종료했다.
Tart stop과 원래 boot 프로세스의 실제 exit code는 모두 `0`이다.
수정 후보는 기존 intent를 지우지 않는 새 테스트 경로에서 검증해야 한다.

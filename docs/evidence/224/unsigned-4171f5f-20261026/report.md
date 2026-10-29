# alpha.14 unsigned 공동 후보와 고정 입력

GUI 입력 선택과 문구 수정이 병합된 main `4171f5f132a611c73d785f28b424c46e65b7f4d5`에서 새 후보 `0.1.0-alpha.14`를 만들었다. 제품 버전은 `0.1.0`이다. #224의 후보·입력 연결을 기록하며 #225~230의 실제 기능 게이트는 미완료다. AC17의 원본 참조와 실패 이력을 함께 보존한다.

| 항목 | 고정값 |
| --- | --- |
| candidate ID / CANDIDATE.json SHA-256 | `4436d17033b2ed4ebff74769a46b67d9689593c7536e85f5b1433b370df14752` |
| 공통 Core identity | `d9a1840008de9ab69daa7fddc8a5e092fb901df280635b1668b39b4d6ed789aa` |
| CLI archive SHA-256 | `18ec2df90cbd5fde75f2028cab5295ae6aeaa2a682a000b14834b03195f7c616` |
| GUI DMG SHA-256 | `e879c660f1e815364e4e4fa03bae812136c63d625b94793d1a1130f486ec6691` |
| Homebrew formula SHA-256 | `55b49f74e426255f0b18879a7ac8acbd5cc75795e0e93c9adc4dc674ac3c3c5f` |
| 입력 index SHA-256 | `a5f6fac32c411a34c8e3a1d4dd6d0fe9bd8b81723fa55c9534f79c86fbece121` |

한 번의 disposable release build로 CLI·GUI와 Core 객체 47개를 만들었다. 두 배포 파일의 BUILD metadata와 resource bytes가 일치한다. 빌드 폴더를 제거한 뒤 archive의 버전·도움말·필수 리소스 실행을 검사했다. DMG를 읽기 전용으로 마운트해 내용을 대조하고 정상 분리했다. formula는 구문만 검사했으며 실제 Homebrew 설치는 아직 하지 않았다.

Source main CI [40206203263](https://github.com/minjunkim-dev/mobile-runtime/actions/runs/40206203263)와 CodeQL [40206203248](https://github.com/minjunkim-dev/mobile-runtime/actions/runs/40206203248)은 exact SHA·attempt 1의 실제 job 5개씩 모두 성공했다. PR #339의 승인 head `ab424b8fd10a56cc3992d13bda84b338ac090ded`와 source main의 Git tree가 같다. 해당 제품 변경은 1,166개 테스트, 별도 컨텍스트의 Standards·Spec·Security 잔여 P0/P1/P2 0건, 최종 PR CI·CodeQL과 사용자 승인을 거쳐 병합됐다. 이번 증거 문서 commit은 제품 build source와 구분한다.

## 여섯 조합의 입력

| 조합 | 최소 앱 | OSS 앱 | runtime |
| --- | --- | --- | --- |
| RN iOS | 고정 RN 0.87.1 | Mattermost 0.83.9 | iOS 26.0 Simulator |
| RN Android | 고정 RN 0.87.1 | Mattermost 0.83.9 | API 37 arm64 Emulator |
| Flutter iOS | Flutter 기본 앱 | LocalSend | iOS 27.0 Simulator |
| Flutter Android | Flutter 기본 앱 | LocalSend | API 35 arm64 Emulator |
| native iOS | Food Truck | NetNewsWire | iOS 27.0 Simulator |
| native Android | Todo | Now in Android | API 35 arm64 Emulator |

각 행은 서로 다른 최소/OSS 표본과 CLI/GUI별 독립 checkout 네 개를 연결한다. 정확한 source SHA·Xcode/도구 버전·scheme/variant·개발 서명 경로는 tuples.json과 제한 원본에 고정했다. 기존 baseline과 별도인 checkout 24개를 재사용했다. 새 clone이나 cold setup 성공으로 세지 않으며 기존 의존성·빌드 출력이 있을 수 있다.

현재 입력의 추적 항목 26,954개는 원래 값 및 승인된 Mattermost iOS Podfile.lock 두 차이와 일치한다. 파일 bytes·종류·실행 비트와 gitlink OID·디렉터리 내용을 비교하고 현재 index/flags digest를 기록했다. 도구 버전 12개와 선택 SDK 파일 15개의 checksum을 재확인했다. Simulator의 이름·runtime·사용 가능 상태와 AVD config를 조회했으며 기기를 부팅하거나 설치하지 않았다. SDK·HOME·cache 전체 재hash나 새 runtime boot 성공은 주장하지 않는다. API37 최소 RN의 기존 로컬 네트워크 권한 허용 조건도 입력에 명시했으며 다음 부팅 때 실제 상태를 다시 확인해야 한다.

## 판정과 다음 게이트

새 후보 결과는 AC15 후보·입력 연결 한 행만 pass이고 나머지 43행은 unverified다. AC15 전체나 실제 앱 첫 화면·취소·접근성을 통과한 판정은 아니다. 첫 수집 보고서는 AC17 연결 문구 누락으로 검사기에 거부됐다. 첫 실패를 보존하고 문구·문서 checksum을 보완했으며 제품과 검사기는 바꾸지 않았다. 원본은 명시한 제한 보관소에 hash로 연결하며 큰 raw 입력의 참조 무결성과 JSON 의미 검증을 구분한다. 이전 alpha.13의 성공·실패·UNKNOWN은 기존 원본과 연결된 보고서에 보존하고 이번 결과로 이월하지 않았다.

#220의 Ad Hoc은 사용자 결정대로 마지막 유료 계정 단계에 보류한다. Development 경로로 대체하지 않는다. #221의 실제 VoiceOver·키보드·시각 배치 검증은 #230과 함께 남아 있다. 이 미검증 상태로 티켓을 닫거나 전체 출시를 승인하지 않는다. Android 실기기는 AC19의 미검증 범위를 유지한다.

현재 호스트 기본 임시 mobile 경로는 기존 SSD symlink이며 후보가 안전 검사에서 거부한다. 이 작업은 링크와 전역 설정을 변경하지 않았다. 앞선 승인된 임시 실제 폴더 검증을 기본 호스트의 성공으로 일반화하지 않으며 후속 실제 실행 전에 자원 소유권과 임시 복구 범위를 다시 확인한다.

signing=unsigned, notarization=not-requested, distributionReady=false다. 바이너리 업로드·태그·공식 공개는 수행하지 않았다. #225~230 실제 기능 게이트를 마친 뒤 #222 서명·공증 → #231 → #232 → #233 순서를 유지한다. PR #284는 보류다. 후보나 입력이 바뀌면 새 시도와 영향 재검증을 기록하며 같은 버전 파일을 덮어쓰지 않는다.

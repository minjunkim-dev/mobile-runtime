# #212 attempt-09: 내장 볼륨 preflight 후 frozen Bundle 중단

최소 React Native 표본의 새 내장 clone에서 원본 early Metro readiness를 확인했다. 필수 frozen Bundle 명령은 exit 1로 종료했다. 요청한 Bundler 2.5.22 executable을 찾지 못했다. Q5에 따라 후속 실행을 중단했다. 앱 또는 native build 실패로 판정하지 않는다. #212는 OPEN이다. PR #236은 미병합 상태다. 실제 Runstir는 사용하지 않았다.

[공개 manifest](evidence/212/attempt-09/manifest.json)는 비식별 요약이다. 원본 로그와 host 경로는 공개하지 않는다. 해시는 보존한 원본 bytes를 식별한다. 원본 해시는 이 공개 문서 또는 공개 manifest의 해시가 아니다. [전체 baseline 기록](rn-baseline-212.md)과 [attempt-08](rn-baseline-212-attempt-08.md)은 별도 이력이다.

## 고정 입력과 실행 경계

정책 main은 `e323ed43a462b63994debcb22367da111b6ba98c`다. [ADR-0024 원본](https://github.com/minjunkim-dev/mobile-runtime/blob/e323ed43a462b63994debcb22367da111b6ba98c/docs/adr/0024-rn-baseline-internal-volume-preflight.md)을 적용했다. 정책 PR #243의 CI 4개 PASS는 정책 문서 검증이다. CI는 이번 native 실행 또는 첫 화면을 증명하지 않는다.

최소 표본 원본 SHA는 `b62e3a4d5e7cfc05d7d948a5a4e30f0cc6a82bb4`다. 보존한 `minimal-source.bundle`에서 `git clone --no-checkout`을 실행했다. 원본 SHA를 detached checkout했다. 새 clone 경로는 `<INTERNAL_VALIDATION_ROOT>/minimal-baseline`이다. 실제 경로 측정은 canonical path와 내장 Data volume의 일치를 확인했다. 측정한 여유 공간은 37,739,339,776 B다. 이 측정은 이전 권한 오류의 원인을 증명하지 않는다.

명령은 Node 22.23.2와 Ruby 3.4.11을 명시했다. 원본 Gemfile.lock은 Bundler 2.5.22를 요구한다. 중단 후 새 버전 측정은 하지 않았다. 후속 도구 버전은 이번 실행에서 측정하지 않았다. 다른 버전 fallback, 새 Bundler 설치, 과거 vendor 복사를 하지 않았다.

| 원본 lock | SHA-256 |
| --- | --- |
| package-lock.json | `3478830fc86d9d1ae7cd46ae129eec9c4915b0ec4e2df247e2cb62b136caeee0` |
| Gemfile.lock | `3679d60340d049c31b74052580c64ab26b3e6fa611f332c1407121dfc3c791eb` |
| ios/Podfile.lock | `cec099ee896ed83dd780bd8da0a03e840c3ba6a0803f90c0bbfcd04efaf17d56` |

Mattermost `c2fe3beda22befd2178dce431793c09111ed903e`는 계획한 후보 SHA다. 이번 attempt에서 Mattermost clone과 checkout은 시작하지 않았다. 최소 표본에 Mattermost Hermes checksum 또는 generated target 예외를 적용하지 않았다. generated project가 없으므로 generated post audit는 NOT_APPLICABLE이다.

## 실제 단계

다음 시간은 2026-10-11 KST다. manifest에는 원본 result의 전체 timestamp와 비식별 argv를 기록했다.

| 단계 | 시작 → 종료 | 결과 |
| --- | --- | --- |
| 최소 clone | 01:49:55.820657 → 01:49:55.852053 | exit 0 |
| 원본 SHA checkout | 01:49:55.911108 → 01:49:56.015032 | exit 0 |
| 원본 npm ci | 01:49:56.214628 → 01:50:02.962761 | exit 0 |
| early Metro readiness | 01:50:27.951276 관측 | HTTP 200 / readiness PASS |
| frozen Bundle | 01:50:46.851550 → 01:50:46.952039 | exit 1 / 필수 준비 중단 |

원본 early Metro 명령은 다음과 같다.

```sh
env -u BASELINE_APP_ROOT mise exec node@22.23.2 -- npm start
```

원본 config와 Watchman 조건을 유지했다. 실제 HTTP receipt가 있다. `http://127.0.0.1:8081/status`는 HTTP 200을 반환했다. 응답 body는 `packager-status:running`이다. 원본 body SHA-256은 `ed71e52f066b30c279378b7933ec895ee558e0899131124296dec5bec2995cef`다. owner/port 접합, HTTP 전후 생존, process identity, fatal log 없음, source binding을 확인했다. hook redirect는 없었다. 검증한 소유 Metro process group에 TERM을 보냈다. 전역 Watchman을 변경하지 않았다. 이 readiness는 앱 설치, 앱 생존, 첫 화면 또는 권한 원인 증거가 아니다.

실패한 frozen 명령의 원본 argv 구조는 다음과 같다. 경로만 비식별했다.

```sh
env BUNDLE_FROZEN=true BUNDLE_PATH=<INTERNAL_VALIDATION_ROOT>/minimal-baseline/vendor/bundle mise exec ruby@3.4.11 node@22.23.2 -- bundle _2.5.22_ install
```

원본 오류는 다음과 같다.

```text
can't find gem bundler (= 2.5.22) with executable bundle (Gem::GemNotFoundException)
```

요청한 Bundler executable의 bootstrap 단계에서 실패했다. Bundle 의존성 설치와 Pod resolution은 시작하지 않았다. 원본 lock과 요청 버전은 그대로다. Bundle 실패 result SHA-256은 `3d7a78911619804312aed5d08dfd81bf03d366f3c90066f5295d05db52b1064c`다. 원본 log SHA-256은 `96c9e23c500ed6cca838b204b5ab61db396f4b357d3399bcf75a78ffa230e8e4`다.

읽기 진단은 네 경로만 확인했다. 요청한 Ruby의 일반 specifications에는 Bundler gemspec이 없었다. 같은 Ruby의 default specifications에는 Bundler 2.6.9 gemspec이 있었다. 새 내장 clone의 vendor specifications 경로는 없었다. 과거 외장 최소 clone의 vendor specifications에는 Bundler 2.5.22 gemspec이 있었다. 이 진단은 host 전체 탐색이 아니다. Bundler 2.5.22가 host 전체에 없다고 판정하지 않는다. 원본 진단 SHA-256은 `4dc5a4e649e99b57a307c8bf1c1c31f6363bc9c6ca98ec18dc642912035eac46`다.

최소 Pods, native iOS build, install, launch, 첫 화면, Android는 모두 NOT_STARTED다. Mattermost 준비와 양플랫폼 실행도 NOT_STARTED다. 독립 minimum-fresh와 Mattermost-fresh clone 및 준비도 NOT_STARTED다. iOS ZIP, APK, 첫 화면 PNG는 각각 0개다. 과거 attempt의 성공을 이번 결과로 승계하지 않는다.

## 감사와 helper 이력

초기 감사와 npm ci 후 감사는 원본 tracked 55개와 세 lock의 보존을 확인했다. 중단 후 감사도 PASS다. tracked raw bytes, kind, Git 실행 mode, index, flags는 그대로다. tracked 변경은 없다. raw 감사의 `prepared: true`는 감사 조건 통과를 뜻한다. 의존성 준비 또는 baseline 완료를 뜻하지 않는다. 사후 감사 SHA-256은 `44da9a5d7567a2e0d3667938f74199573f425fdceb1a4f8961086c0096c4cd4c`다.

source-only helper v1에는 내장 cache producer와 consumer의 경로 불일치가 있었다. 실제 lease 전에 v2에서 수정했다. v1 파일 31개와 archive index 1개를 보존했다. v2 메모리 검사는 34+35+21+11+130=231개 PASS다. 독립 검토의 material finding은 0개다. 고정한 35개 파일의 해시는 검토 전후 같았다. 메모리 검사 PASS는 실제 native 또는 첫 화면 PASS가 아니다.

root의 prelease 집계는 `returncode` 대신 `exitCode`를 읽어야 했다. 원본 KeyError 이력을 보존했다. 집계 오류는 resource mutation을 만들지 않았다. 이 오류는 실제 Bundle 실패와 다르다. prelease readiness와 seal의 당시 상태도 그대로 보존했다. 실제 grant와 최종 RELEASED receipt는 별도 증거다.

## 정리와 lease 반환

01:51:15.469476 cleanup preflight는 PASS다. 원래 Simulator 2개는 Booted 상태를 유지했다. 전용 iOS 26 Simulator는 Shutdown 상태다. 기존 GUI를 보존했다. 8081 listener, adb device, 실제 native/emulator process는 없었다. 이번 attempt는 앱 설치, Simulator boot, Emulator 시작, Gradle 시작을 하지 않았다. 소유 early Metro만 Bundle 전에 종료했다. 기존 Watchman과 다른 resource owner를 보존했다. 전역 PATH, 도구, SDK, runtime, 권한을 바꾸지 않았다.

최초 `granted` receipt와 `ReturnRequested` receipt를 보존했다. root는 01:52:12에 canonical RELEASED를 확인했다. 새 조건의 실제 실행에는 별도 결정과 새 run이 필요하다. cleanup 원본 SHA-256은 `e1337bf4a22be3f88d172e1f312a576c8751219517e8e31843be0d4b7ab30126`다. root release 원본 SHA-256은 `9a022eaf37e6dc0181bae965e200ee59dbbce574421559bf487ad10e9e7316fd`다.

## 원본 packet 무결성

canonical RELEASED 통지가 초기 core 고정 후 도착했다. 초기 REPORT, manifest, SHA256SUMS를 `pre-root-release-final-core`에 보존했다. 현재 최종 core는 RELEASED receipt를 포함한다. core 갱신 후 실제 실행은 없었다. 초기 core 해시와 최종 core 해시는 서로 다른 bytes를 식별한다.

봉인 inventory는 110개다. top-level 파일 75개는 SHA256SUMS 자체를 포함한다. v1 archive는 32개다. 초기 core 이력은 3개다. 최종 SHA256SUMS의 109 entries를 모두 확인했다. mismatch는 0개다. SHA256SUMS 자체 해시는 별도로 확인했다. 별도 `__pycache__` 파일 5개는 봉인 inventory 밖의 실행 캐시다. 이를 packet 또는 dependency cache로 집계하지 않는다. 이번 packet에는 공식 raw archive cache 사본이 없다.

runner result는 4개다. runner log도 4개다. exit 0은 3개다. Bundle exit 1은 1개다. 전체 `.log`는 early Metro log를 포함해 5개다. 공개 manifest는 110개 원본 파일의 비식별 이름, size, SHA-256, 역할을 기록한다. 원본 로그와 코드 payload는 공개하지 않는다.

| 최종 원본 파일 | SHA-256 |
| --- | --- |
| REPORT.md | `ea1d7f324190f9d8d6cb71ef0f0a55bc8c08432148b3142ddc95eacd92116006` |
| manifest.json | `75bf01cc3a9e86050235ba56e7f6ffbcedaa2bf7a596136a2bf06b4ccdfe3584` |
| SHA256SUMS | `56d361a65a5450b416e504a88100c096bd4f97ab8321ac427a0d7e974bbd4c83` |

필수 frozen 준비가 남았다. 새 최소 양플랫폼 checkpoint와 Mattermost 양플랫폼 checkpoint가 남았다. 두 독립 fresh 준비도 남았다. #212 known-good 또는 완료를 주장하지 않는다. 실제 Runstir gate는 후속 범위다.

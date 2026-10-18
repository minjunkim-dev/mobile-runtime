# Runstir 설치

macOS Apple Silicon(arm64)용 CLI다. CLI 명령어는 `mobile`이다.
실행 파일과 두 `.bundle` 디렉터리를 같은 디렉터리에 유지한다.

## Homebrew 설치

1. 기존 GitHub 저장소를 tap으로 등록한다.

   ```sh
   brew tap minjunkim-dev/runstir https://github.com/minjunkim-dev/mobile-runtime
   ```

2. Runstir를 설치한다.

   ```sh
   brew install minjunkim-dev/runstir/runstir
   mobile --version
   ```

formula는 배포 archive의 SHA-256을 고정한다. 실행 파일과 두 resource bundle을 함께 설치한다.
Node·Ruby·JDK·Xcode·Android SDK는 프로젝트별 버전이 다르므로 formula 의존성으로 설치하지 않는다.
기존 공개 배포는 CLI다. 공동 CLI·GUI 후보는 아래 제한 검증 경로를 사용한다.

## archive 설치

1. GitHub Releases에서 `runstir-<version>-macos-arm64.tar.gz`와 같은 이름의 `.sha256` 파일을 다운로드한다.
2. 다운로드한 디렉터리에서 checksum을 확인한다.

   ```sh
   version=0.1.0-alpha.4
   shasum -a 256 -c "runstir-$version-macos-arm64.tar.gz.sha256"
   ```

3. archive를 풀고 전체 디렉터리를 설치한다. 실행 파일만 옮기지 않는다.

   ```sh
   tar -xzf "runstir-$version-macos-arm64.tar.gz"
   mkdir -p "$HOME/.local/lib/runstir" "$HOME/.local/bin"
   mv "runstir-$version-macos-arm64" "$HOME/.local/lib/runstir/"
   ln -s "$HOME/.local/lib/runstir/runstir-$version-macos-arm64/mobile" "$HOME/.local/bin/mobile"
   ```

4. `PATH`를 설정하고 실행한다.

   ```sh
   export PATH="$HOME/.local/bin:$PATH"
   mobile --version
   mobile --help
   ```

## 환경 확인과 실행

신뢰한 프로젝트에서 원하는 플랫폼을 실행한다.

```sh
mobile doctor --json
mobile up
mobile down
# Android
mobile doctor --platform android --json
mobile up --platform android
mobile down --platform android
```

`mobile`은 프로젝트의 Gradle·package manager·Podfile 코드를 실행한다.
SDK·Simulator·Emulator·Node·Ruby·JDK는 사람이 준비한다.
부족한 환경의 확인과 복구 절차는 [환경 준비 안내](environment-setup.md)를 따른다.
검토하지 않은 프로젝트를 민감한 환경값이 있는 환경에서 실행하지 않는다.

## 버전과 실행 범위

### Draft Release 생성

공개 전 후보 생성은 `.github/workflows/draft-release.yml`로 실행한다.
workflow는 `main`에서 수동 실행한다. 버전은 `v` 없는 alpha 형식이다.
source SHA는 `main`에 포함된 전체 40자리 SHA다. 해당 SHA의 `main` push CI가 성공해야 한다.

```sh
gh workflow run draft-release.yml --repo minjunkim-dev/mobile-runtime --ref main \
  -f version=0.1.0-alpha.5 -f source_sha=<full-40-character-main-SHA>
```

workflow는 잠근 의존성으로 macOS arm64 CLI archive·GUI DMG·checksum·`CANDIDATE.json`을 만들고 검증한다.
현재 workflow는 서명 자격을 준비하거나 서명 입력을 전달하지 않는다. 구조 검증용 unsigned 후보를 만든다.
GitHub에 `draft=true`, `prerelease=true`인 Release만 생성한다.
기존 Release와 태그가 있는 버전은 거절한다. 기존 asset을 덮어쓰지 않는다.
Draft 생성 직전에 입력을 다시 검증한다. 생성 후 같은 태그가 생겼으면 실패로 처리하고 Draft를 공개하지 않는다.
이 검사는 외부 태그 변경을 원자적으로 잠그지 않는다. 실패한 Draft는 검토 후 처리한다.
빌드 job은 읽기 권한만 사용한다. Draft 생성 job만 `contents: write`를 사용한다.
공개 전환과 Homebrew formula 갱신은 실행하지 않는다.
workflow 등록은 권한 확대다. 병합 전에 사람이 최종 head를 승인한다.

Draft를 만들기 전에 [실제 Simulator 스모크](ci-reproducibility.md#실제-simulator-스모크는-수동으로-실행한다)를 같은 SHA에서 수동 실행한다.
결과 URL을 릴리스 티켓에 기록한다.

Draft의 archive를 내려받아 [ADR-0019](adr/0019-first-external-pre-release.md)의 실제 실행 검증을 완료한다.
archive smoke와 CI는 그 실행 검증을 대체하지 않는다. 공개는 별도 승인으로 처리한다.

### 배포 파일의 근거

`BUILD.json`에 release version, source SHA, CLI version, 빌드 도구·의존성·Core object digest를 기록한다.
새 후보는 disposable source의 공유 버전 상수만 입력 버전으로 고정한 뒤 CLI와 GUI를 한 번에 빌드한다.
`sourceRevision`과 `sourceSHA`는 `git archive`의 입력 commit이다. 제품 버전은 복사본의 `Sources/Core/ProductVersion.swift`에 적용한 version stamp 입력이다.
CLI·GUI·Core는 이 입력 commit과 제품 버전을 공유한다. 기존 공개 `0.1.0-alpha.4`의 내부 CLI version은 `0.1.0`이다.

Package.swift의 macOS 최소 버전 선언은 14다. 첫 실행 검증 범위는 macOS 27.0.1 arm64다.
릴리스 노트의 BlueWallet iOS·FreeKiosk Android 검증 조합을 확인한다.
그 결과로 다른 프로젝트·도구 버전의 호환성을 보증하지 않는다.

첫 archive는 Apple Developer ID 서명과 notarization을 제공하지 않는다.
macOS가 다운로드한 실행 파일을 차단하면 checksum을 먼저 확인한다.
macOS의 시스템 설정에서 제공하는 보안 승인 절차를 따른다.
보안 정책을 바꾸거나 quarantine 속성을 일괄 삭제하지 않는다.

### 제한 CLI·GUI 후보

1. 같은 source SHA의 필수 CI를 확인한다. `Draft Release` 또는 로컬 `scripts/package-release.sh <alpha-version> <새-output-directory>`로 후보를 만든다.
2. 이 저장소는 public이다. `Draft Release` run의 `draft-release` Actions artifact는 7일간 보관하지만 제한 후보 배포 위치로 취급하지 않는다. 제한 후보 배포 위치와 검증자 접근 권한은 별도로 확정한다.
3. 후보 디렉터리에서 두 `.sha256` 파일을 확인한다. `scripts/verify-candidate.sh <candidate-directory>`로 archive·DMG의 source/version/Core identity와 resource bundle을 확인한다.
4. 후보 Homebrew formula는 `runstir-candidate.rb`다. 제한 후보 archive URL을 `RUNSTIR_CANDIDATE_URL`에 지정한 뒤 `brew install --formula ./runstir-candidate.rb`를 실행한다. URL의 인증값을 로그나 증거에 넣지 않는다. 후보는 keg-only다. `brew --prefix runstir-candidate` 아래의 `bin/mobile`로 검증한다. 기존 CLI를 link하거나 교체하지 않는다. 로컬 구조 검사는 archive의 절대 `file://` URL을 사용할 수 있다. 이 검사는 AC16의 제한 위치 다운로드·설치 검증을 대체하지 않는다.
5. Developer ID 서명·공증한 DMG만 Gatekeeper 실행 검증에 사용한다. `Runstir.app`을 검증용 Applications 경로로 복사한다. GUI에 제품 버전과 공식 다운로드 링크가 표시된다. 새 DMG의 앱으로 수동 교체한다. GUI bundle에는 `mobile`이 없고 별도 CLI 경로를 변경하지 않는다.

로컬 서명 제작에는 설치된 Developer ID Application 인증서와 기존 `notarytool` keychain profile이 필요하다.
인증서의 identity 이름을 `RUNSTIR_SIGNING_IDENTITY`에 지정한다. profile 이름을 `RUNSTIR_NOTARY_PROFILE`에 지정한다.
private key·비밀번호·공증 credential은 이 명령의 인자나 증거에 넣지 않는다. 현재 Draft workflow는 이 로컬 서명 경로를 실행하지 않는다. runner 서명은 별도의 자격 준비·전달·정리 구현과 검토가 필요하다.
두 입력이 없으면 구조 검증용 unsigned 후보를 만든다. 입력 하나만 있으면 제작을 중단한다.
서명 경로는 CLI와 GUI의 hardened runtime 서명을 검증한다. CLI zip과 GUI DMG의 공증 승인을 확인한다. DMG에는 ticket을 staple하고 검증한다.
실제 자격이 없는 환경에서는 이 서명·공증 경로를 실행 검증했다고 기록하지 않는다.

`CANDIDATE.json`은 artifact SHA-256·source SHA·제품 버전·Core build identity와 서명·공증 상태를 고정한다.
`ciRun`은 후보를 제작한 Actions workflow의 `GITHUB_RUN_ID`다. 로컬 제작에서는 `null`이다.
같은 source의 필수 `CI` run URL과 최종 head는 별도 검증 근거에 기록한다.
PR CI의 source SHA는 합성 merge commit일 수 있다. `CANDIDATE.json`의 `sourceSHA`를 확인한다. PR head와 같다고 추정하지 않는다.
`distributionReady`는 자동으로 참이 되지 않는다. 실제 다운로드·설치·CLI 없는 GUI·Gatekeeper·후보 간 수동 업데이트는 AC16의 별도 실제 검증이다.
CLI·GUI의 실제 실행, 알려진 성공 표본, tuple, 화면 증거를 같은 후보에 연결한다. 기능이 바뀌면 새 버전의 후보와 증거를 만든다.
후보 제작은 공식 제품 공개를 수행하지 않는다.

## 제거

Homebrew 설치는 다음 명령으로 제거한다.

```sh
brew uninstall minjunkim-dev/runstir/runstir
```

archive 설치는 `~/.local/bin/mobile` symlink와 설치한 버전의 Runstir 디렉터리를 제거한다.
프로젝트 파일·SDK·Simulator·Emulator는 유지한다.

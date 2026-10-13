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
현재 배포는 CLI다. DMG 설치는 GUI를 제공할 때 추가한다.

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

workflow는 잠근 의존성으로 macOS arm64 archive와 checksum을 만들고 검증한다.
GitHub에 `draft=true`, `prerelease=true`인 Release만 생성한다.
기존 Release와 태그가 있는 버전은 거절한다. 기존 asset을 덮어쓰지 않는다.
Draft 생성 직전에 입력을 다시 검증한다. 생성 후 같은 태그가 생겼으면 실패로 처리하고 Draft를 공개하지 않는다.
이 검사는 외부 태그 변경을 원자적으로 잠그지 않는다. 실패한 Draft는 검토 후 처리한다.
빌드 job은 읽기 권한만 사용한다. Draft 생성 job만 `contents: write`를 사용한다.
공개 전환과 Homebrew formula 갱신은 실행하지 않는다.
workflow 등록은 권한 확대다. 병합 전에 사람이 최종 head를 승인한다.

Draft의 archive를 내려받아 [ADR-0019](adr/0019-first-external-pre-release.md)의 실제 실행 검증을 완료한다.
archive smoke와 CI는 그 실행 검증을 대체하지 않는다. 공개는 별도 승인으로 처리한다.

### 배포 파일의 근거

`BUILD.json`에 release version, source SHA, 내부 CLI version, 빌드 도구와 의존성을 기록한다.
현재 archive와 formula의 release version은 `0.1.0-alpha.4`다. 내부 CLI version은 `0.1.0`이다.

Package.swift의 macOS 최소 버전 선언은 14다. 첫 실행 검증 범위는 macOS 27.0.1 arm64다.
릴리스 노트의 BlueWallet iOS·FreeKiosk Android 검증 조합을 확인한다.
그 결과로 다른 프로젝트·도구 버전의 호환성을 보증하지 않는다.

첫 archive는 Apple Developer ID 서명과 notarization을 제공하지 않는다.
macOS가 다운로드한 실행 파일을 차단하면 checksum을 먼저 확인한다.
macOS의 시스템 설정에서 제공하는 보안 승인 절차를 따른다.
보안 정책을 바꾸거나 quarantine 속성을 일괄 삭제하지 않는다.

## 제거

Homebrew 설치는 다음 명령으로 제거한다.

```sh
brew uninstall minjunkim-dev/runstir/runstir
```

archive 설치는 `~/.local/bin/mobile` symlink와 설치한 버전의 Runstir 디렉터리를 제거한다.
프로젝트 파일·SDK·Simulator·Emulator는 유지한다.

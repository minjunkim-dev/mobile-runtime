# Runstir 설치

첫 pre-release는 macOS Apple Silicon(arm64)용이다. CLI 명령어는 `mobile`이다.
실행 파일과 두 `.bundle` 디렉터리를 같은 디렉터리에 유지한다.

## 설치 절차

1. GitHub Releases에서 `runstir-<version>-macos-arm64.tar.gz`와 같은 이름의 `.sha256` 파일을 다운로드한다.
2. 다운로드한 디렉터리에서 checksum을 확인한다.

   ```sh
   shasum -a 256 -c runstir-0.1.0-alpha.1-macos-arm64.tar.gz.sha256
   ```

3. archive를 풀고 전체 디렉터리를 설치한다. 실행 파일만 옮기지 않는다.

   ```sh
   tar -xzf runstir-0.1.0-alpha.1-macos-arm64.tar.gz
   mkdir -p "$HOME/.local/lib/runstir" "$HOME/.local/bin"
   mv runstir-0.1.0-alpha.1-macos-arm64 "$HOME/.local/lib/runstir/"
   ln -s "$HOME/.local/lib/runstir/runstir-0.1.0-alpha.1-macos-arm64/mobile" "$HOME/.local/bin/mobile"
   ```

4. `PATH`를 설정하고 실행한다.

   ```sh
   export PATH="$HOME/.local/bin:$PATH"
   mobile --version
   mobile --help
   ```

5. 신뢰한 프로젝트에서 원하는 플랫폼을 실행한다.

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
검토하지 않은 프로젝트를 민감한 환경값이 있는 환경에서 실행하지 않는다.

## 버전과 실행 범위

`BUILD.json`에 release version, source SHA, 내부 CLI version, 빌드 도구와 의존성을 기록한다.
첫 archive의 release version은 `0.1.0-alpha.1`이다. 내부 CLI version은 `0.1.0`이다.

Package.swift의 macOS 최소 버전 선언은 14다. 첫 실행 검증 범위는 macOS 27.0.1 arm64다.
릴리스 노트의 BlueWallet iOS·FreeKiosk Android 검증 조합을 확인한다.
그 결과로 다른 프로젝트·도구 버전의 호환성을 보증하지 않는다.

첫 archive는 Apple Developer ID 서명과 notarization을 제공하지 않는다.
macOS가 다운로드한 실행 파일을 차단하면 checksum을 먼저 확인한다.
macOS의 시스템 설정에서 제공하는 보안 승인 절차를 따른다.
보안 정책을 바꾸거나 quarantine 속성을 일괄 삭제하지 않는다.

## 제거

`~/.local/bin/mobile` symlink와 설치한 버전의 Runstir 디렉터리를 제거한다.
프로젝트 파일·SDK·Simulator·Emulator는 유지한다.

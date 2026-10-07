# ADR-0019: 첫 외부 배포는 macOS arm64 archive로 두 플랫폼을 함께 제공한다

상태: 채택 (2026-10-07)

## 배경

ADR-0018의 iOS Go가 이름 결정과 외부 배포를 허용했다. Android 내부 alpha도 고정
FreeKiosk 조합에서 통과했다. 소스 공개는 바이너리 배포 완료가 아니다. 첫 배포에는
새 archive의 다운로드·설치·실행 증거가 필요하다. #130은 바이너리 배포를 후속 effort로 남겼다.

## 결정

제품명은 Runstir(런스터)다. CLI는 `mobile`을 유지한다. 저장소 이름과 `mobile.yml` 계약은 유지한다.

첫 외부 pre-release는 GitHub Releases에서 macOS Apple Silicon(arm64) archive 하나로
iOS와 Android를 함께 제공한다. 실행 파일과 Core·AndroidKit의 SwiftPM resource bundle을
함께 넣는다. LICENSE·고정 의존성 고지·설치 안내·build metadata·SHA-256 checksum을 제공한다.

필수 CI와 변경 리뷰를 통과한 source SHA를 고정한다. GitHub draft release에 올린 archive를
다운로드한다. 그 archive로 각 플랫폼의 doctor·build·up·첫 화면·down을 검증한다.
성공한 결과와 검증 조합을 기록한 뒤 공개 pre-release로 전환한다. 게시 후 파일과 checksum을
다시 확인한다. 외부 개발자 모집은 완료 조건이 아니다.

실제 실행 주장은 macOS 27.0.1 arm64와 기록된 플랫폼별 검증 조합으로 제한한다.
Package.swift의 macOS 14 하한 선언으로 14~26 실행 검증을 대신하지 않는다.
자동 provisioning이나 앱 환경값 생성 기능을 추가하지 않는다.

## 대안과 결과

Homebrew를 첫 채널로 쓰면 배포·업데이트 계약이 늘어난다. 이번에는 직접 archive를
제공하고 Homebrew를 후속 작업으로 남긴다. Intel·Windows·Linux 호스트 배포도 남긴다.

제품명과 CLI를 함께 바꾸면 기존 명령·remediation·문서·`mobile.yml` 계약을 다시 검증해야 한다.
이번에는 제품명만 확정하고 기존 CLI를 유지한다.

첫 archive는 Developer ID 서명·notarization을 제공하지 않는다. checksum은 파일 동일성을
확인한다. 개발자 신원 서명이나 macOS의 보안 승인을 대신하지 않는다. 설치 안내에서 이 제약을
명시한다. Gatekeeper의 정책을 바꾸는 installer는 제공하지 않는다.

일반 React Native 지원, 다른 검증 조합, 앱 초기 UI 이후의 기능을 보증하지 않는다.
기존 소스 실행 결과와 새 배포 파일 실행 결과를 합산하지 않는다.

추적: [첫 외부 배포 effort #162](https://github.com/minjunkim-dev/mobile-runtime/issues/162).

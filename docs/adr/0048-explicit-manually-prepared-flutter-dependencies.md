---
status: accepted
date: 2026-10-24
---

# ADR-0048: Flutter build/up에도 직접 준비한 의존성 선택을 제공한다

사용자가 2026-10-24에 승인한 공개 계약이다. 최종 head와 영향 범위의 병합 승인은 별도로 받는다.

## 배경

고정 LocalSend 표본은 원래 Android·arm64 iOS 빌드가 성공해도 Runstir의 ADR-0040
legacy·federated plugin resolver 수동 경계에서 멈춘다. 원래 빌드 성공을 Runstir 성공으로
기록하거나 Flutter resolver를 재구현하지 않고, ADR-0047의 명시적 준비 의존성 선택을 확장한다.

## 결정

- Flutter `build/up --prepared-dependencies`와 GUI의 **직접 준비한 의존성 사용**을
  같은 공유 입력으로 연결한다. 기본값은 꺼짐이며 앱·플랫폼 선택 변경 시 해제한다.
  native·down은 계속 거부하며 doctor와 setup의 판정·승인된 정렬은 바꾸지 않는다.
- 선택한 실행에서 의존성 재설치·lock 정렬 재검증과 plugin resolver 정합성 판정을 생략한다.
  legacy·implements·default_package, 선택 플랫폼 plugin 목록의 완전성과 native 속성의
  선언 일치 여부는 사용자가 정확한 SDK로 준비하고 확인한다. 이 결과를 resolver PASS로 부르지 않는다.
- workspace 루트의 읽을 수 있는 pubspec.lock·package_config.json·package_graph.json이 필요하다.
  현재 app·SDK와 graph·package manifest identity 및 dependency 연결 검사는 유지한다.
  생성 metadata는 선택 SDK 버전, package_config에 있는 고유 이름과 canonical 경로,
  실제 JSON boolean인 native_build·shared_darwin_source를 요구한다.
  reachable plugin이 있으면 metadata가 필요하다. plugin이 없는 앱의 공식적인 부재는 계속 허용한다.
- iOS는 생성 metadata byte와 native plugin 디렉터리를 고정하여 alias 예외와 실행 전후 검사에 사용한다.
  Android는 같은 준비 입력 검증과 보호된 SDK private view를 유지한다.
  entrypoint·workspace·도구·target·lease·취소·source/lock snapshot·SDK 보호를 완화하지 않는다.
  Podfile이 있으면 기존 Pods 디렉터리·두 lock의 byte 일치·읽을 수 있는 workspace 한 개가 필요하다.
- CLI 도움말과 GUI에 생략 범위와 사용자의 정합성 책임을 표시한다.
  `dependencies`는 설명을 포함한 `skipped`, JSON은 `operation.preparedDependencies: true`다.
  기본 실행은 optional 필드를 생략하며 기존 검증을 유지한다.

## 검증과 경계

기본 경계 유지, 수동 선택의 양 플랫폼 전달, 누락·오염 입력과 metadata 변경 차단,
workspace와 Pods, installer 미실행, 정상 down을 동작 검사로 확인한다.
실제 LocalSend CLI·GUI 첫 화면·개발 연결·정상 종료와 source·SDK 보존은 별도 검증한다.
fixture·원래 빌드·이전 후보의 성공을 새 unsigned 후보의 실제 게이트로 이전하지 않는다.
서명·공증·배포 순서와 Ad Hoc 보류, 사용자 실기기의 동작별 승인 경계는 유지한다.

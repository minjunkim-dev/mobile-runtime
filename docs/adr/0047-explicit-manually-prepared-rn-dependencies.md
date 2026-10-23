---
status: accepted
date: 2026-10-23
---

# ADR-0047: RN build/up에서 직접 준비한 의존성을 명시적으로 선택할 수 있게 한다

사용자의 후속 진행 요청에 따라 #225에 제안한 명시적 수동 준비 방식을 선택한다.
이 공개 계약 변경의 최종 head와 영향 범위에 대한 병합 승인은 별도로 받는다.

## 배경

고정 후보의 Mattermost iOS 실행은 원본 NPM lifecycle이 Pods를 재생성하면서 사람이 준비한
generated Debug 설정과 lock을 바꿔 native build 전에 실패했다. Android에서는 같은 앱의
macOS preinstall이 system Ruby에 Bundler를 설치하려다 권한 오류로 실패했다.
원본 CI의 의존성 준비와 Doctor 성공은 이 lifecycle의 성공을 보장하지 않았다.

기본 재설치를 조용히 생략하거나 npm wrapper로 generated 설정을 되돌리면 기존 의존성
정렬 계약과 실제 검증 근거가 달라진다. 유료 계정이나 배포 준비를 기다리는 문제도 아니다.

## 결정

- RN `mobile build/up --prepared-dependencies`와 GUI의 **직접 준비한 의존성 사용**을 같은
  공유 실행 입력으로 연결한다. 기본값은 꺼짐이며 앱·플랫폼 선택을 바꾸면 GUI 선택을 해제한다.
- 이 선택에서만 Node·Bundle·Pods 설치와 lock 정렬 재검증을 생략한다. 기본 경로와
  `setup`의 승인된 frozen 정렬, 선언 파일 변경 감지·취소 계약은 유지한다.
- 설치 루트(workspace가 있으면 그 루트)의 node_modules 디렉터리가 있어야 한다.
  `.mobile-install.incomplete`가 남아 있으면 dangling symlink를 포함해 중단한다.
- iOS에서 Podfile이 있으면 Pods 디렉터리, Podfile.lock과 Manifest.lock의 byte 일치,
  읽을 수 있는 CocoaPods workspace 한 개가 필요하다. Android에는 Apple 산출물을 요구하지 않는다.
  이 검사에서 설치기·복구 명령을 실행하거나 파일을 보정하지 않는다.
- 기존 프로젝트·도구·target·기기 선택, Doctor의 실행 전 차단, 자원 lease, 포트·Metro,
  build/install/launch와 down·취소 소유권 검사를 유지한다. Flutter·native·down에서는 이 옵션을 거부한다.
- 선택 전에 의존성 정합성은 사용자가 확인해야 함을 표시한다. `dependencies`는
  재설치·lock 정렬 재검증 생략을 설명하는 `skipped`이며 정렬 PASS로 기록하지 않는다.
  공유 JSON의 `operation.preparedDependencies: true`는 명시적 선택을 나타낸다.
  기본 경로에서는 이 optional 필드를 내보내지 않는다.

## 경계와 검증

기존 파일의 존재와 Pods lock 일치는 dependency 전체의 정합성 증명이 아니다.
도구 설치·저장소 신뢰·라이선스·실기기 변경 승인도 대신하지 않는다.
새 내부 허가 파일, receipt 서비스, source 수정이나 generated 설정 자동 보정은 추가하지 않는다.
ADR-0006의 선언된 설치 경로는 기본 실행과 setup에서 유지한다.

누락·미완료·Pods 불일치 차단, workspace 루트, 기본 정렬 유지, 양 플랫폼 전달,
다른 framework/down 거부, 취소와 파일·자원 보존을 동작 검사로 확인한다.
실제 CLI·GUI 실행과 독립 Standards·Spec·Security, 최종 CI·CodeQL은 별도 근거다.
제품 변경 뒤 새 unsigned 후보와 새 시도로 실제 게이트를 기록하며 과거 후보의 실패를 고치지 않는다.
서명·공증·배포 순서와 유료 Apple 계정의 Ad Hoc 보류는 바꾸지 않는다.

---
status: accepted
---

# ADR-0021: Mattermost의 생성 Pods 준비를 제한한다

2026-10-10 사용자가 공유 이해를 확인하고 이 제한된 준비 예외를 확정했다. 원본 source와 의존성 graph를 유지하면서 생성 project의 Debug 설정만 준비한다. 정책 채택은 baseline 성공이나 실제 Runstir 성공을 뜻하지 않는다.

## 배경

[#212 attempt-04](https://github.com/minjunkim-dev/mobile-runtime/blob/17963043950458c2d9498de289bc64d45f74a2c9/docs/rn-baseline-212-attempt-04.md)는 원본 Hermes 한 값의 제한된 준비와 `pod install --deployment`를 통과했다. iOS Debug build는 Pods resource bundle target 11개의 deployment target 때문에 exit 65로 실패했다. SDK 27의 최소 허용값은 15.0이다. compile action은 0개였다.

[대체 OSS 후보 10개 조사](https://github.com/minjunkim-dev/mobile-runtime/blob/62104cf20ad1cfd2c47d60e3f98a01d027070488/docs/rn-baseline-212-oss-candidates.md)는 바로 실행할 적격 입력을 확정하지 못했다. 원본 source와 graph를 유지하면서 생성 project의 제한된 설정을 사람 준비로 다룬다.

## 허용 범위

대상 source는 Mattermost `c2fe3beda22befd2178dce431793c09111ed903e` 하나다. 원본 [Podfile.properties.json](https://github.com/mattermost/mattermost-mobile/blob/c2fe3beda22befd2178dce431793c09111ed903e/ios/Podfile.properties.json)의 app minimum은 `16.4`다. source SHA와 원본 선언 버전을 유지한다. [ADR-0020](0020-rn-baseline-prepared-input.md)의 기존 Hermes checksum 한 값 예외와 raw checkout/index 감사는 그대로 적용한다. 원본 serialized spec의 provenance는 여전히 unknown이다.

마지막 frozen Pods 설치가 성공한 뒤 `ios/Pods/Pods.xcodeproj/project.pbxproj`에서 다음 11개 resource bundle target의 **Debug** `IPHONEOS_DEPLOYMENT_TARGET` 값만 `16.4`로 바꾸는 사람 준비를 허용한다.

| target | 현재 읽은 원본 Debug 값 | 준비 값 |
|---|---|---|
| `RNSVG-RNSVGFilters` | `12.4` | `16.4` |
| `SDWebImage-SDWebImage` | `9.0` | `16.4` |
| `CocoaLumberjack-CocoaLumberjackPrivacy` | `11.0` | `16.4` |
| `ratex-react-native-RaTeXFonts` | `14.0` | `16.4` |
| `SwiftyJSON-SwiftyJSON` | `12.0` | `16.4` |
| `Starscream-Starscream_Privacy` | `12.0` | `16.4` |
| `RNPermissions-RNPermissionsPrivacyInfo` | `12.4` | `16.4` |
| `SQLite.swift-SQLite.swift` | `12.0` | `16.4` |
| `react-native-cameraroll-RNCameraRollPrivacyInfo` | `9.0` | `16.4` |
| `Alamofire-Alamofire` | `10.0` | `16.4` |
| `react-native-image-picker-RNImagePickerPrivacyInfo` | `9.0` | `16.4` |

이는 현재 생성 project의 읽기 결과다. 과거 build 직전의 project hash를 확보했다는 뜻이 아니다. 11개는 모두 `PBXNativeTarget`의 `com.apple.product-type.bundle`이다. target별 Debug configuration은 공유하지 않는다. 이 configuration의 조건부 deployment override와 연결된 xcconfig의 deployment 설정은 발견하지 못했다. 현재 project에는 PBXProject 1개와 target 186개가 있다. 새 준비에서는 이 사실을 다시 확인한다.

Release 값과 다른 target·configuration·build setting은 유지한다. 앱 project, Podfile, dependency spec, 버전, graph, source 선언, build flag, Xcode 선택은 바꾸지 않는다. helper는 Runstir 제품에 추가하지 않는다. 다른 source나 SDK 조합에 이 예외를 적용하지 않는다.

## 재현과 감사

1. 새 attempt의 baseline과 후속 fresh clone을 독립 준비한다. 원본 source와 lock을 보존한다. 원본 npm/hook, frozen Bundle, ADR-0020의 제한된 Pods 준비를 수행한다. `pod install --deployment`가 성공해야 다음 단계로 간다.
2. 생성 project의 raw hash와 전체 parsed object, target/configuration matrix를 먼저 저장한다. 위 11개 이름·product type·Debug 값이 정확히 일치해야 한다. 중복 이름, 추가 floor 대상, 공유 configuration, 조건부 override, 입력 unknown이 나오면 중단한다.
3. checksum을 고정한 외부 수동 helper로 11개 Debug 값만 바꾼다. 변경 후의 전체 parsed object에서 그 11값만 원래 값으로 되돌렸을 때 변경 전 전체 object와 같아야 한다. array 순서와 모든 다른 설정도 같아야 한다. raw hash와 byte diff도 보존한다. serialization이 다른 의미 변경을 만들면 중단한다.
4. 메모리 self-check로 Release 변경, 추가 target, 다른 build setting, object 삭제·추가를 거부하는지 확인한다. tracked checkout byte/index/flags, lock 전체와 Podfile checksum을 준비 후와 실행 후에 다시 감사한다. 두 clone 사이에 Pods, node_modules, build 산출물을 복사하지 않는다.
5. 실행 lease를 받은 새 run에서 직접 native Debug build와 iOS 26·기존 Android API 37의 install/launch/첫 화면을 검증한다. 추가 필수 실패가 나오면 중단한다. 다른 checksum·source·target·flag·도구 보정으로 확대하지 않는다. 기존 attempt-04와 사용자 자원은 보존한다.

이 준비를 사용한 결과는 **생성 Pods를 보정한 준비 입력의 baseline**으로 기록한다. 원본 무보정 baseline과 합치지 않는다. helper identity, 원본/준비 lock, 생성 project 전후 hash와 semantic delta를 함께 인계한다. Release build와 다른 source·runtime의 성공은 포함하지 않는다.

## 후속 Runstir 실행의 경계

한 번 보정한 generated project가 현재 Runstir `build/up`에서도 유지된다고 보장하지 않는다. 현재 JS stage는 인접 lockfile이 있으면 다시 설치한다. [DependenciesStage.swift](https://github.com/minjunkim-dev/mobile-runtime/blob/a5fb193d8ee79147453d06a0ed338a47d091b74f/Sources/Core/Up/DependenciesStage.swift#L69-L72), [workspaceRoot 판별](https://github.com/minjunkim-dev/mobile-runtime/blob/a5fb193d8ee79147453d06a0ed338a47d091b74f/Sources/Core/Project/ProjectAnchor.swift#L484-L495). Mattermost의 원본 package-lock이 이 조건을 충족한다.

선택 명령은 [`npm ci`](https://github.com/minjunkim-dev/mobile-runtime/blob/a5fb193d8ee79147453d06a0ed338a47d091b74f/Sources/Core/Project/ProjectAnchor.swift#L149-L162)다. 원본 [postinstall](https://github.com/mattermost/mattermost-mobile/blob/c2fe3beda22befd2178dce431793c09111ed903e/package.json#L202-L203)과 [darwin hook](https://github.com/mattermost/mattermost-mobile/blob/c2fe3beda22befd2178dce431793c09111ed903e/scripts/postinstall.sh#L4-L10)은 Pods 설치를 다시 실행한다. CocoaPods 1.16.1의 기본 [project generation](https://github.com/CocoaPods/CocoaPods/blob/1.16.1/lib/cocoapods/installer.rb#L295-L320)은 [resource bundle target을 다시 만든다](https://github.com/CocoaPods/CocoaPods/blob/1.16.1/lib/cocoapods/installer/xcode/pods_project_generator/pod_target_installer.rb#L573-L588). 따라서 수동 보정이 사라질 것으로 판단한다. 이는 source 추론이다. 실제 재생성 실험은 수행하지 않았다.

Runstir의 직접 Pods stage는 [lock/Manifest가 같으면 설치를 건너뛸 수 있다](https://github.com/minjunkim-dev/mobile-runtime/blob/a5fb193d8ee79147453d06a0ed338a47d091b74f/Sources/Core/Up/DependenciesStage.swift#L101-L103). 이 조건만으로 앞선 npm lifecycle의 재생성을 막는다고 판단하면 안 된다. 현재 JS stage에 준비 receipt나 lock stamp 재사용 조건은 없다.

#212는 native baseline과 fresh 준비 입력 인계 범위다. 인계에는 위 재생성 위험을 명시한다. 실제 Runstir gate에서 준비 상태를 유지하거나 재적용하는 문제는 후속 검증에서 별도 결정한다. 이번 정책으로 Runstir의 dependency 실행 정책을 바꾸지 않는다. 실제 Runstir, 공동 1.0.0의 여섯 조합, 일반 RN 지원의 성공을 선언하지 않는다.

## 적용 조건

이 제한된 사람 준비 예외를 #212의 새 baseline/fresh 준비 입력에 적용한다. 정책 반영 후 새 실행의 입력과 실행 lease를 고정한다. [ADR-0020](0020-rn-baseline-prepared-input.md)의 중단 기준은 유지한다.

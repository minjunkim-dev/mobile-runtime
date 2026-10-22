# ADR-0044: Flutter Android도 확인한 개발 연결 URI를 공통 결과에 반환한다

- 상태: 채택
- 날짜: 2026-10-22
- 관련: #209, #199 AC04, ADR-0040, [Flutter iOS](../flutter-ios.md)

## 배경

Flutter `up`은 앱의 Dart VM service를 개발 연결로 제공한다. VM service URI에는 인증 경로가 있다. 이 경로가 없으면 DevTools·디버거가 연결하지 못한다.
Flutter iOS는 `getVM`으로 확인한 URI를 `operation.developmentServiceURI`로 반환하고 CLI·GUI가 표시한다.
Flutter Android는 host·device 포트만 반환했다. 인증 경로는 공개 결과에서 숨겼다. 그래서 같은 `up` 결과로 Android 앱에는 디버거를 연결할 수 없었다. 두 플랫폼이 다른 이유를 기록한 결정은 없었다.
사용자 결정: Android도 iOS처럼 URI를 반환한다.

## 결정

1. Android `android.flutter.service`는 소유한 adb forward의 host 포트로 `getVM`을 조회한다. Dart VM이 답한 URI만 개발 연결로 인정한다.
2. 그 URI(`http://127.0.0.1:<host port>/<인증 경로>/`)를 iOS와 같은 `operation.developmentServiceURI`로 반환한다. CLI와 GUI는 같은 필드를 표시한다.
3. 공개 JSON에서 인증 경로는 이 필드 한 곳에만 둔다. `result.android.flutterConnection`은 포트만 둔다. stage detail·progress event·runner 로그·active-run 기록·오류 문구에는 넣지 않는다. 조회 명령 인자는 계속 가린다.
4. 이 URI의 인증 경로와 원본 로그를 공개 증거에 그대로 게시하지 않는다(iOS와 같다).

## 결과

- 사용자는 Runstir 결과의 URI로 Android 앱에 바로 DevTools·디버거를 연결한다.
- 공개 결과를 보관하거나 공유하는 사용자는 이 필드에 로컬 인증 경로가 있음을 알아야 한다. 주소는 이 컴퓨터의 `127.0.0.1`에서만 열리고, 앱이 종료되면 무효가 된다.
- 이전의 "Android 인증 URI는 공개 JSON에 넣지 않는다"는 코드 주석·테스트 계약을 대체한다.

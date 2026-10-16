# 공개 receipt 읽기

전체 실행 원본은 작업 소유 제한 증거 root에 보존한다.
원본 접근은 작업 조정자에게 요청한다.
공개 저장소 접근권은 원본 접근권을 뜻하지 않는다.
이 폴더는 필요한 입력·명령·관측·실패·감사의 공개 표현을 제공한다.
전체 원본 로그와 기존 사용자 설정·temp snapshot은 공개하지 않는다.

`provenance.json`은 공개 표현과 제한 원본의 SHA-256·byte 수를 구분한다.
`rawSHA256`과 `rawBytes`는 보존한 제한 원본을 식별한다.
`publicSHA256`과 `publicBytes`는 공개 파일을 식별한다.
`publicContentSHA256`은 압축을 해제한 공개 표현을 식별한다.
`representation`은 발췌·별칭 치환·그대로 보존한 비로그 입력을 구분한다.
공개 표현은 원본 byte 감사의 대체물이 아니다.

로그 발췌에는 원본의 행 번호와 선택한 범위가 있다.
명령·오류·단계 판정에 필요한 행만 남겼다.
전체 환경 dump와 반복 compiler 명령은 제외했다.
빈 로그는 출력 부재만 기록한다. 종료 상태는 실행 receipt에서 확인한다.
`.gz`는 공개 표현의 deterministic gzip이다. header mtime은 `0`이다.
압축을 해제해도 전체 원본 로그를 복원할 수 없다.

```text
gzip -dc prepared-localsend-ios-build-final.log.gz > <owned-temp>/build-excerpt.txt
shasum -a 256 <owned-temp>/build-excerpt.txt
```

이 결과는 `publicContentSHA256`과 비교한다. `rawSHA256`과 비교하지 않는다.
`SHA256.json`은 이 폴더의 공개 파일을 열거한다.
상위 `SHA256.json`은 화면·source bundle·문서도 열거한다.
각 manifest는 자기 파일을 제외한다.

경로와 기기 identity는 `provenance.json`의 일관된 별칭을 사용한다.
`<evidence-root>`, `<user-home>`, `<darwin-temp>`, `<owned-simulator>`는 실제 경로·UDID가 아니다.
tuple의 argv도 같은 별칭을 사용한다.
wrapper·guard는 이번 실행의 기록이다. 그대로 실행하지 않는다.
후속 실행은 자신이 소유한 root·기기·포트와 승인한 경계로 다시 작성한다.

`prepared-localsend-ios-final-tuple.json`의 argv는 실제 invocation의 별칭 표현이다.
초안의 설명 label 정정은 `ios-tuple-record-correction.json`에 있다.
정정 전 초안은 제한 경로에 보존했다.
prepared Android 요약의 `COLD`는 실제 launch 로그의 `WARM`으로 정정했다.
`provenance.json`의 `correction`은 변경하지 않은 원본 receipt와 정정한 공개본을 연결한다.
실패·중단·misdirected pub get 이력은 성공 기록과 구분한다.

Emulator 원본 로그에는 저장 전 public key 비식별 필터를 적용한 이력이 있다.
공개본은 그 비식별 로그에서도 필요한 행만 발췌했다.
기존 private key·console token의 내용과 hash는 수집하지 않았다.
기존 Android 파일 비교는 `lstat` metadata만 사용했다.
`final-preservation-audit.json`과 `ios-ephemeral-temp-summary.json`은 제한된 관측 범위를 기록한다.
전체 SDK byte 보존이나 모든 temp 변화의 원인을 증명하지 않는다.

fresh clone receipt는 source·frozen 의존성의 인계 증거다.
그 clone의 native 앱 또는 Runstir CLI·GUI 실행 증거가 아니다.
baseline의 실제 네 실행과 구분한다.

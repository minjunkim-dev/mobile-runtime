# alpha.11 unsigned 후보와 실제 부분 검증

AC15는 후보·입력 연결, AC17은 원본·실패 이력과 미검증 조건을 보존한다. 이 보고서는 #225–230 전체 통과나 공개 배포 승인이 아니다.

Source `01a243d00e97899d62a8a1c3a7cdc78c508083a3`, artifact `0.1.0-alpha.11`, candidate `b5857f6112624c93e16ee9ac7726d5372c37b4e0379c2f254141873ad9cc784c`. Core build identity `66bcf5118016ecfba346507a53cc224bd7074ec87afc9768185f30d269450575`. 한 release build의47개 Core 객체·metadata·resource bytes가 CLI/GUI에 연결되며 별도 archive 실행과 읽기 전용 DMG 검증을 통과했다. CLI SHA256 `77699d7685281cc8e40057167e0e4f48ac410d5739071a9f225e7ec90927a21f`, GUI SHA256 `b35e7c10c4345eb70ae1cf73aaf65898a0f8b76df4b24a8e7bfa8e25306a00a6`.

main CI40040553489와 CodeQL40040553378/attempt1의 실제5개 job씩 completed/success를 확인했다. PR331 SDK37 signer 출력 호환 수정, PR333 확정 native APK 서명 거부 후 예약 복구 수정은 별도 Standards/Spec/Security와 최종 CI/CodeQL 뒤 정확한 head로 병합했다.

## 새 후보 CLI 관측

| 조합 | 최소 앱 | 실제 OSS 앱 |
| --- | --- | --- |
| RN iOS | RN0.87.1/Hermes 화면 | Mattermost 서버 연결 화면 |
| RN Android | RN0.87.1/Hermes 화면 | Mattermost 서버 연결 화면 |
| Flutter iOS | Demo Home Page/카운터0 | LocalSend 미검증 |
| Flutter Android | Demo Home Page/카운터0 | LocalSend 미검증 |
| Native iOS | Food Truck 화면 | NetNewsWire Feeds 화면 |
| Native Android | Todo 정상 빈 목록 | Now in Android 관심 주제 화면 |

10개 실행은 up/down raw0, 추적 source·index·flags 보존, 올바른 기기의 앱 PNG 직접 검토, 소유 자원 정상 정리를 확인했다. iOS Mattermost/NetNewsWire는 표준 알림 권한 팝업 뒤 앱 화면을 확인했고 권한을 고르지 않았다. 정지 이미지의 정상 화면을 이후 기능·로그인·전체 crash 부재로 확대하지 않는다. Android는 소유 AVD를 `-no-window`로 선부팅해 포커스를 보호했으며 이10행은 제품의 cold-boot 검증이 아니다. Flutter 두 플랫폼은 getVM 응답과 down 뒤 개발 전달 포트 부재도 확인했다.

RN iOS 최소/OSS의 doctor pass와 standalone build raw0, install/launch 없는 완료 단계 및 소스 보존도 수집했다. setup은 계획만 확인했고 변경하지 않았다. 격리 HOME에는 Simulator device set이 없어 exact-set native 조회1/default 조회0으로 구분했다. 이 수동 대기를 준비 완료로 바꾸지 않는다. setup은 양플랫폼을 조사하며 Android cache 부족도 별도 수동 단계로 남았다.

## RN redbox의 관측 경계

이전 Watchman 소켓 수정과 실제 최소/OSS 실행 결과를 유지한다. API37 조합의 최소 RN은 compile37/target36이다. 개발 비교에서 ACCESS_LOCAL_NETWORK 거부 상태의 redbox를 관측했고 수동 허용·Reload 후 Metro 번들 처리가 재개됐다. Reload 후 빈 화면은 미해결이다. 허용 상태를 유지한 다음 정상 down/up에서 올바른 첫 화면을 확인했으며 새 후보 최소 RN Android도 그 허용 상태를 재사용했다. 새 최초 허용 UI, 단독 원인, target37 전용 정책 적용, 즉시 Reload 복구 성공을 주장하지 않는다.

## 앱 파일과 복구

APK 정상 설치/첫 화면/교체 표식 보존을 확인했다. 동일 서명 불일치 APK의 두 파일 경로는 각각 native UPDATE_INCOMPATIBLE로 거부됐고 다음 경로는 예약에 막히지 않았다. 데이터 표식·build가 유지됐으며 자동 삭제·재서명·초기화로 우회하지 않았다.

Simulator .app은 꺼진 소유 대상 부팅 뒤 실제 설치 상태에 따른 새 교체 승인을 요구했고, 승인 후 install/launch accepted와 첫 화면·Documents 표식 보존을 확인했다. 변경된 사본의 이전 승인은 inspect만 완료하고 설치/실행을 요청하지 않았다. 원본 tree identity, 표식 정리, 전체 Simulator 부팅 상태 복원을 확인했다. 첫 수집기는 정상 launch=accepted를 requested와 오비교했으며 이 중단은 제품 실패와 분리했다. 원시 실패를 유지하고 정정한 관측은 새 시도로 누적했다.

## 남은 조건과 보존

24개 입력은 이전에 고정한 독립 clone의 재사용이다. 과거 PASS를 새 후보에 승계하지 않았고, 이번 후보 fresh clone 조건을 통과로 세지 않는다. AC05 각10행은 첫 화면/종료 부분 성공과 별개로 남은 필수 조건 때문에 inconclusive다. LocalSend 계약 변경, GUI 재시작/피커/VoiceOver, 대표 iOS 실기기 변경은 별도 응답 대기이며 현재 후보에서 수행하지 않았다. 실기기는 마지막 목록에서 disconnected였다. Ad Hoc은 마지막 유료 계정 단계에 보류한다.

도구 없는 환경·실제 준비 적용·다운로드 실패/취소·조건 변경·GUI12행·병렬/충돌·전체 접근성 등 남은 필수 시나리오는 미검증이다. 전체 #225–230을 닫지 않는다. 설치/거부/교체 표식 관측은 제한된 데이터 표본이며 전체 앱 데이터나 SDK/cache 불변 증명이 아니다. 원시 JSON은 raw bytes로 보존하며 참조 무결성과 별개로 수집기 schema 성공을 주장하지 않는다.

signing=unsigned, notarization=not-requested, distributionReady=false. Runstir 배포 서명·공증·태그·업로드·공개 배포는 수행하지 않았다. 테스트 거부 APK 제작에 사용한 임시 테스트용 서명과 Runstir 배포 서명을 구분한다. 기능·baseline·실제 검증 → unsigned 후보 → #225–230 → #222 서명/공증 → #231 → #232 → #233 순서를 유지한다.

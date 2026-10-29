# #224 unsigned 0.1.0-alpha.10 공동 후보와 새 입력

AC15는 후보·입력 연결을, AC17은 원본 참조와 실패 이력 보존을 명시한다. 전체 실제 출시 게이트 통과 기록은 아니다.

Source `2c8e1f8300f6b5b5c072d82d94cc59bcf037c634`, 제품 버전 `0.1.0`, artifact `0.1.0-alpha.10`. Candidate manifest SHA-256 `71f9d46f01f093c5edf6be66b648930c4ddf07f95b26f5063b65a3a7451f6a0e`, shared Core `11358911b3b20f0e1f025ce66f6eda1c6979297c513418dee1ce5be5ceaebaea`. 한 disposable release build의 Core 47개 객체·BUILD metadata·resource bytes로 CLI와 GUI가 연결된다. 별도 archive 실행과 읽기 전용 DMG 검증을 통과했고 컴파일 fallback은 제거했다. main CI 40011249834와 CodeQL 40011249640의 실제5job씩 성공을 확인했다.

큰 tracked-source map 원문은 명시된 restricted raw capture로 hash 연결하고 compact 입력 요약에서 참조한다. raw 원문은 JSON schema 검증을 주장하지 않으며 참조 무결성만 확인한다.

소유한 도구/cache APFS 사본과 CLI/GUI용 독립 source24개를 연결했다. 이 후보의 입력 재사용 기록이 있으면 미실행 source22개 재사용과 별도 clone2개 교체, 기존 소유 도구·AVD 재사용을 그 기록으로 구분한다. 여섯 known-good tuple의 최소/OSS source pin·tool/runtime/profile·scheme/variant·개발 서명 조건을 유지한다. 기존 native Xcode27.1 baseline은 같은 host/tool/runtime 조건의 선행 근거이며 새 후보 실행 성공으로 바꾸지 않는다. RN Mattermost의 원래 Node/Bundler/Pods 준비 및 승인된 생성물, 최소 RN의 선언된 Bundler bootstrap, NNW의 원래 updateSecrets 준비는 각 fresh root에서 별도로 수행하고 소스·인덱스 보존을 기록했다. node_modules/Pods/native app output을 다른 source에서 복사하지 않았다.

새 API35·API37 AVD의 실제 fingerprint/ABI와 정상 종료를 확인했다. 첫 API37 관측은 Emulator 전용 home에서 생성한 키와 ADB에 지정한 과거 키가 달라 unauthorized로 실패했다. 제품을 실행하기 전의 준비 실패이며 원본을 보존했다. 정확한 자기 Emulator 키를 ADB_VENDOR_KEYS에 연결한 r2는 부팅·fingerprint·정상 종료에 성공했다. private key byte 사본·출력은 없다. 다른 프로세스/기기는 정리하지 않았다. 전체 HOME/cache나 vendor SDK 전체 payload 불변을 주장하지 않는다.

signing=unsigned, notarization=not-requested, distributionReady=false. GUI 실제 실행·Homebrew 설치·Gatekeeper와 #225–230 실제 기능 게이트는 별도다. 새 후보에 과거 후보/개발 CLI의 첫 화면 PASS를 승계하지 않는다. package/input linkage AC15만 pass이고 나머지 초기 행은 unverified다. AC01–AC19 전체 시나리오 목록은 해당 기능 게이트가 별도로 완성해야 한다.

Ad Hoc은 사용자 결정대로 마지막 유료 계정 단계에 보류하며 Development로 대체하지 않는다. Android 실기기는 승인된 미검증 범위다. 기능·baseline → unsigned 입력 → #225–230 실제 기능 → #222 서명/공증 → #231 → #232 → #233 순서를 유지했다. PR284·서명·공증·공개 배포는 수행하지 않았다. 이전 후보의 실패/UNKNOWN은 기존 후보 evidence root와 원본 actual 기록에 보존하며 새 후보 결과로 승계하지 않는다.

Input revision r2 retains the original 24-input index and failed attempts. Eight previously unexecuted functional tuples correct only selection metadata: Native iOS uses reported container IDs; LocalSend selects app/ while preserving the whole Git source and canonical Pub workspace. Source/tool/runtime and candidate artifact bytes are unchanged. The other 16 inputs retain their original hashes. Affected inputs require new actual attempts; no previous outcome is promoted. Collector r3 has a separate fixed hash, 20 synthetic binding/cleanup checks and three independent non-author reviews.

## alpha.10 실제 시도 반영

AC05 CLI 12개 중 9개 첫 화면·정상 종료·소스 보존을 확인했다. Mattermost iOS는 표준 알림 prompt 뒤에 server-connect 화면이 표시됐고 권한을 고르지 않았다. RN 최소 Android는 ACCESS_LOCAL_NETWORK 거부 뒤 redbox로 실패했으며 승인 허용 비교는 미수행이다. LocalSend 양 플랫폼은 원래 native build 성공과 별개로 제품의 수동 plugin 경계에서 실패했다. GUI 최소 RN Android는 취소130·재빌드·up/down은 관측했으나 첫 화면 미확정이고, 나머지 GUI11개는 미검증이다.

AC12에서 Simulator 앱 파일 교체·자체 Documents 표식 보존·변경된 파일 승인 거부를 관측했다. 정상 메타데이터인 container 경로 변화는 손상으로 판정하지 않았다. Android APK는 SDK37 signer 출력 호환 결함으로 alpha.10에서 실패했다. 개발 수정·개발 CLI 성공은 이 후보에 승계하지 않는다. Ad Hoc 및 전체 실제 기기 게이트는 보류/미완료다.

AC17 원시 기록 702개는 private raw/PNG로 바이트·hash를 보존했고 초기 결과는 priorResults에 연결했다. 미완성/대형 수집기 JSON은 raw로 보존하여 유효한 제품 JSON 실패와 수집기 실패를 구분한다. 이 부분 결과로 #225–230이나 출시 전체를 통과시키지 않는다. 서명·공증·배포는 수행하지 않았다.

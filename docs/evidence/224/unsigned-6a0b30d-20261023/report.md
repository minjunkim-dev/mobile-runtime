# #224 unsigned 공동 후보와 검증 입력

후속 #225–230이 소비할 source·제품 버전·파일 checksum과 여섯 조합의 최소/OSS 입력을 묶는다. 제품 공개나 전체 출시 게이트 통과 기록은 아니다. AC15는 후보·입력 연결을, AC17은 명시한 원본 참조와 실패 이력 보존을 확인한다.

Source `6a0b30d399d8df6399c6b092318f4e9daec6f709`, productVersion `0.1.0`, artifact releaseVersion `0.1.0-alpha.8`. 기존 배포 계약의 내부 제품 버전과 산출물 버전 구분을 유지했다. source stamping·PR284 병합은 없다. Candidate manifest SHA-256 `6a07f1a33bbb2772075c1f7c7ccd6e1654f6aec82c00ff3d9840244c1c361da0`, Core `376dc2998fa9ff78bdfc3b41f27e22246f7fa0055df951547f2ac69be4467774`. 한 cold release build에서 CLI·GUI를 만들었으며 Core46개 객체·BUILD·리소스 bytes가 연결된다. CLI archive, GUI DMG, checksum 고정 Homebrew formula는 restricted-index의 cli/gui/homebrew다. main CI39917978260·CodeQL39917978209 모든5job 각각 성공.

패키지 checksum·외부 CLI 실행·리소스 로딩과 읽기 전용 DMG metadata 검증을 통과했다. GUI 실행·실제 Homebrew 설치·Gatekeeper는 아직 후속 게이트다. signing=unsigned, notarization=not-requested, distributionReady=false. 서명·공증·공식 공개를 수행하지 않았다.

여섯 tuple은 각각 별도 최소/OSS source·도구·runtime·기기 profile·개발 서명 조건과 fresh 준비 정책을 연결한다. RN iOS26/iPhone16Pro, Flutter iOS27/iPhone16, native iOS27/iPhone18Pro를 구분한다. RN Android API37 Google Play r6와 나머지 Android API35 Google APIs r9도 구분한다. 각 CLI/GUI용 새 source24개와 쓰기용 도구/cache 사본을 만들었다. 새 fresh source의 dependency materialization은 고정한 원본 준비 recipe로 각 게이트에서 별도로 실행하며, native build·Pods·앱 데이터 사본을 fresh로 세지 않는다.

native iOS의 옛 Xcode27.0 결과는 현재27.1로 승계하지 않았다. 원래 두 source·scheme·Debug·앱 ID로27.1 native baseline을 새로 실행했고 build/install/launch/첫 화면/종료를 확인했다. 두 raw PNG를 직접 확인했다. NNW 원래 argv에는 sdk 강제 옵션이 없으며 Food Truck과 구분한다. 초기 수집기의 LFS PATH·앱 파일명·정상 dataPathSize 비교 실패와 잘못 추가한 NNW sdk 옵션의 실패는 제한 원본 보고서와 명령에 보존했다. 원본 source/lock은 바꾸지 않았다.

새 소유 AVD 두 종류를 headless로 실제 부팅해35·37 fingerprint/ABI를 확인했고, 선택된 scoped adb와 emulator를 모두 정상 종료·회수했다. API37 fingerprint와 Pixel10 profile은 기존 RN baseline과 일치한다. 다른 AVD와 새 Simulator는 생성 후 부팅하지 않은 상태다. 기존 사용자 기기·프로세스를 멈추거나 복원하지 않았다. 전체 HOME/cache bytes 불변이나 vendor 전체 SDK 재해시를 주장하지 않는다.

Ad Hoc은 사용자 결정에 따라 마지막 유료 계정 단계로 보류했다. #220은 이 미검증 범위로 열어 두며 Development 성공으로 바꾸지 않는다. unsigned 개발·테스트를 유료 멤버십에 묶지 않는다. Android 실기기는 승인된 AC19 미검증 범위를 유지한다. 필수 기능·baseline → #224 unsigned 입력 → #225–230 실제 기능 → #222 서명·공증 → #231 → #232 → #233 순서다.

이 results는 전체 계약의 완전한 시나리오 목록을 대신하지 않는다. AC01–AC19의 미수집 행과 여섯 조합24개 CLI/GUI 첫 화면 행을 unverified로 남겼다. #223 검사기의 evidenceIntegrity=verified는 참조 무결성만 뜻하며, required-results와 distribution-unverified로 출시가 차단되는 것이 기대 결과다. 후보 또는 입력이 바뀌면 새 시도와 영향받는 재검증이 필요하다. 과거 성공이나 문서 검사로 실제 후보 실행을 대신하지 않는다.

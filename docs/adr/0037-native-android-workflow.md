# ADR-0037: native Android를 기존 Android 실행 계약에 연결한다

날짜: 2026-10-16
상태: 구현. 실제 CLI·GUI 실행 검증과 최종 head 승인은 별도다.
관련: #199, #211, #204, #210, ADR-0013, ADR-0015, ADR-0035, ADR-0036

## 선택과 요구

`ProjectCandidate.framework`와 `ProjectAnchor.framework`의 `native-android`를 유지한다.
선택한 native Android 앱 루트가 Gradle root다. RN의 `android/` 경로를 붙이지 않는다.
`AndroidDoctorContext`의 평가한 application module·variant와 SDK/JDK 요구를 재사용한다.
RN·RNGP·Node·package manager를 native Android의 필수 입력으로 요구하지 않는다.
준비는 #204의 정확한 SDK package 계획과 승인·라이선스·목적지 계약을 사용한다.
build/up에서 새 SDK, JDK, wrapper나 실행 기기를 설치하지 않는다.

module과 variant 선택은 기존 `AndroidTargetSelector`를 사용한다.
이름이 정확히 `debug`인 runnable debuggable variant를 기본값으로 유지한다.
`debug`가 없는 복수 flavor는 명시적인 선택을 요구한다.
유효하지 않은 module·variant를 대신 고르지 않는다.
launcher는 기존 merged manifest와 실제 APK의 aapt2 결과를 대조한다.

모델 init script를 사용하는 조회와 build는 해당 실행에서 Configuration Cache와 Isolated Projects를 함께 끈다.
모델의 cross-project callback과 cache 재사용을 섞지 않기 위해서다. 프로젝트의 선언 파일은 수정하지 않는다.
Gradle은 Isolated Projects가 켜진 상태에서 Configuration Cache를 끄면 실패한다.
근거는 [Gradle Isolated Projects 계약](https://docs.gradle.org/9.7.0/userguide/isolated_projects.html)이다.

## 공통 실행

CLI와 GUI는 기존 `EnvironmentInspection`과 `WorkflowExecution`을 사용한다.
native Android build는 `validate → android.build`를 실행한다.
up은 이어서 `android.device → android.install → android.launch`를 실행한다.
RN dependency alignment·Metro·adb reverse 단계와 Metro 포트 lease를 사용하지 않는다.
기존 RN은 dependency alignment·Metro·reverse와 해당 소유권 검사를 유지한다.
빌드 검사는 `includeRuntimeSDKTools=false`일 때 AVD·acceleration probe도 생략한다.
따라서 APK만 만드는 build는 adb·Emulator package를 필수로 요구하지 않는다.

native Java/Kotlin APK의 aapt2 결과에 native library ABI가 없으면 `abis=[]`를 유지한다.
이는 native library ABI 제한이 없다는 뜻이다. 임의의 ABI를 만들어 넣지 않는다.
실행 시에는 기존 AVD와 실제 Emulator의 읽을 수 있는 ABI·API·준비 상태를 확인한다.
native library가 있으면 기존 ABI 대조를 유지한다.
RN APK의 native ABI metadata 필수 조건도 유지한다.

## 소유권과 실패

프로젝트 folder·선택 기기의 공통 `ResourceLeases`를 재사용한다.
Android lifecycle lock과 기존 active-run 기록 형식을 유지한다.
새 native 실행은 Metro와 reverse 자원을 기록하지 않는다.
down과 실패·취소 rollback은 ADR-0013의 기존 소유권 재확인과 best-effort 정리를 사용한다.
재사용한 Emulator와 설치된 package를 보존한다.
uninstall·clear-data·SDK 삭제·AVD 생성·삭제를 추가하지 않는다.
SDK root 실패는 #265의 도메인 실패·unknown 소유권 보존 계약을 유지한다.
취소는 exit 130을 유지한다. 취소 전 완료한 변경과 남은 자원도 기존 결과에 남긴다.

## 검증 경계

소유한 임시 fixture와 `FakeProcessRunner`로 공통 doctor/build/up/down을 실행한다.
Gradle root, RN 입력 부재, exact debug와 flavor 선택, APK·launcher 대조,
native-only ABI 처리, 취소·설치 실패·lease 충돌과 기존 자원 보존을 확인한다.
실제 Gradle·ADB·Emulator·GUI를 이 검사의 근거로 사용하지 않는다.
이 fixture는 #215 baseline과 원본 배포 checksum의 증거를 대신하지 않는다.
실제 두 표본의 CLI·GUI 실행과 보존 검증은 별도 자원 lease 아래 수행해야 한다.
fixture 성공을 AC01·AC04의 실제 실행 완료나 공동 출시 성공으로 표시하지 않는다.

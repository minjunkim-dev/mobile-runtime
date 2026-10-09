# Runstir CLI 확장 공통 계약 초안

상태: 사용자 결정 정리 및 최종 검토 초안. 제품 구현과 GUI 구현을 뜻하지 않는다.
티켓: [결정: 프로젝트 탐지와 공통 CLI 계약](https://github.com/minjunkim-dev/mobile-runtime/issues/181).
기준 source: `1a4ff6dc3815ab6c25df81eaef8ca37acaefe21e`.

## 사용자와 확정한 방향

네이티브 iOS·Android, Flutter iOS·Android, React Native iOS·Android에 공통 명령을 사용한다. 첫 호스트는 macOS Apple Silicon이다. Flutter는 Runstir `1.0.0` 출시 범위에 포함한다. Xcode 지원 하한은 `27.0`이다. Xcode `26.x` 이하는 제외한다. 각 버전 조합의 실제 지원 증거는 별도 검증 결정에서 정한다.

Flutter·React Native는 iOS·Android 양쪽 환경을 준비한다. 앱 실행에서는 플랫폼을 입력받고 해당 플랫폼의 설치된 Simulator/Emulator 또는 연결된 실기기를 선택한다. 환경 준비 범위를 이번 실행의 플랫폼이나 기기로 축소하지 않는다.

CLI와 향후 GUI는 같은 입력·선택 후보·검사·실행 결과 계약을 사용한다. 필요한 항목에는 기본값을 사용한다. GUI 구현은 이번 지도 밖의 후속 effort다.

## 공통 명령의 의미

| 명령 | 계약 |
| --- | --- |
| `doctor` | 환경과 프로젝트 요구사항을 검사한다. 준비 부족과 선택 미확정을 구분한다. 선택을 완료하지 않아도 가능한 검사를 보고한다. |
| `build` | 프로젝트 환경과 의존성을 확인하고 앱 산출물을 만든다. 앱을 설치하거나 실행하지 않는다. |
| `up` | 플랫폼과 실행 기기 선택을 확보하고 앱을 빌드·설치·실행한다. 필요한 framework 개발 연결도 해당 실행 경로에서 처리한다. |
| `down` | 해당 프로젝트의 실행 기록과 플랫폼별 자원 소유권 계약에 따라 실행 자원을 정리한다. 도구·SDK 제거 및 기기 초기화 명령으로 사용하지 않는다. |

환경 준비의 명령 이름, 승인 단위, 설치·중단·복구와 실기기 수동 단계는 [결정: 승인형 환경 준비의 변경과 복구 계약](https://github.com/minjunkim-dev/mobile-runtime/issues/182)에서 정한다. 현재 ADR-0009를 이 초안만으로 변경하지 않는다.

## 탐지와 선택의 구체화 제안

아래 항목은 최종 검토가 필요한 구체화다. CLI 옵션 이름과 JSON 필드의 최종 표기는 후속 구현 명세에서 확정한다.

1. 앱 폴더에서 실행하면 프로젝트 정본을 탐지한다. 별도의 앱 경로 입력도 제공한다. `--project`는 그 입력의 CLI 표기 예시다. 앱 루트와 의존성 정렬을 수행할 workspace root를 구분한다.
2. 프로젝트 종류와 실행 가능한 앱을 정본 근거로 해석한다. framework 앱의 네이티브 host 파일을 별개 앱으로 중복 선택하지 않는다. 혼합 프로젝트처럼 근거만으로 확정할 수 없으면 후보와 필요한 선택을 보고한다.
3. 앱·scheme·variant 후보가 하나면 선택할 수 있다. 여러 후보가 있으면 명시적 선택이 필요하다. 기존 사용자 답의 복수 후보를 임의로 고르지 않는 규칙을 유지한다.
4. 앱 실행은 플랫폼 입력과 실행 기기 선택을 제공한다. CLI는 옵션 또는 터미널 입력을 사용할 수 있다. GUI는 같은 후보로 선택 화면을 구성한다. 입력 수집과 터미널 조작은 Core 밖에 둔다.
5. 기기 후보는 플랫폼·가상/실기기 구분·고유 식별자·관측한 준비 상태를 포함한다. 입력 플랫폼과 기기 플랫폼이 다르면 잘못된 조합을 안내한다. 이름만으로 여러 기기를 같은 대상으로 취급하지 않는다. 선택 후 연결 상태 변화도 실행 단계에서 확인한다.
6. 비대화식 실행은 필요한 선택을 명시적으로 받는다. 선택 미확정이면 후보와 필요한 입력을 구조화된 결과로 돌려주고 작업을 시작하지 않는다. GUI나 CI가 CLI의 사람용 출력 문장을 파싱하도록 만들지 않는다.

## 기본값 제안

기본값은 근거와 적용 결과를 확인할 수 있어야 한다. 단일 후보와 프로젝트가 명시한 선택은 입력을 줄이는 근거가 된다. 여러 후보 중 첫 항목이나 임의의 iOS 기본값으로 사용자 의도를 대신 정하지 않는다.

개발 실행의 build configuration은 프로젝트가 선언한 선택을 우선한다. 별도 선택이 없는 개발 실행은 실제 프로젝트에 해당 후보가 있을 때 개발용 Debug 기본값을 출발점으로 한다. 없는 configuration을 임의로 만들지 않는다. 종류별 configuration 표현과 우선순위는 후속 명세에서 구체화한다.

## CLI와 GUI의 공유 경계

기존 Core·Adapter·플랫폼 provider를 재사용한다. 프로젝트 해석, 검사, 선택 검증, 승인 대상 변경 계획, 실행, 진행 상태와 결과를 공통 계약으로 표현한다. CLI는 인자·터미널·JSON을 표현한다. GUI는 같은 계약으로 입력·선택·진행·결과 화면을 표현한다.

선택 후보와 준비 부족을 공통 결과로 제공한다. 터미널 질문을 플랫폼 실행 코드에 넣지 않는다. 명세 단계에서 실제로 두 표면이 공유할 입력과 결과의 최소 타입을 정한다.

### 현재 코드의 재사용 경계

현재 코드에는 `DoctorEngine.run`의 `DoctorReport`, `UpPipeline.run`의 `UpReport`와 단계 완료 `StageResult`, 플랫폼별 build/up/down factory가 있다. 이 결과와 실행 경로를 출발점으로 삼는다. [DoctorEngine](https://github.com/minjunkim-dev/mobile-runtime/blob/1a4ff6dc3815ab6c25df81eaef8ca37acaefe21e/Sources/Core/Doctor/DoctorEngine.swift), [UpPipeline](https://github.com/minjunkim-dev/mobile-runtime/blob/1a4ff6dc3815ab6c25df81eaef8ca37acaefe21e/Sources/Core/Up/UpPipeline.swift).

기기 후보 목록과 선택기는 공개 입력·응답 계약으로 분리되지 않았다. CLI의 `Wiring.bootstrap`은 cwd·process environment를 읽고 logging을 준비한다. 진행 note는 문자열 callback이며 Core의 `UpWriter`도 터미널 출력 객체다. 따라서 현재 Core 전체가 GUI 입력과 선택에 바로 대응한다고 간주하지 않는다. 실제 후보 조회·선택·실행 준비와 표현의 경계는 후속 명세에서 필요한 범위만 분리한다. [Wiring](https://github.com/minjunkim-dev/mobile-runtime/blob/1a4ff6dc3815ab6c25df81eaef8ca37acaefe21e/Sources/mobile/Wiring.swift), [iOS DeviceStage](https://github.com/minjunkim-dev/mobile-runtime/blob/1a4ff6dc3815ab6c25df81eaef8ca37acaefe21e/Sources/SimulatorKit/DeviceStage.swift), [Android 선택 경로](https://github.com/minjunkim-dev/mobile-runtime/blob/1a4ff6dc3815ab6c25df81eaef8ca37acaefe21e/Sources/AndroidKit/AndroidUpStages.swift), [UpWriter](https://github.com/minjunkim-dev/mobile-runtime/blob/1a4ff6dc3815ab6c25df81eaef8ca37acaefe21e/Sources/Core/Up/UpOutput.swift).

## 공개 계약과 호환성

초기 alpha는 필요한 계약 변경을 허용하고 변경 내용과 이전 방법을 안내한다. Runstir `1.0.0`에서 공개 명령·설정·JSON 계약을 확정한다. 이후 같은 주버전의 minor/patch는 해당 계약의 호환성을 유지한다. 호환을 깨는 변경은 다음 주버전과 이전 방법을 제공한다.

JSON의 구조·의미가 호환되지 않게 바뀌면 schema version과 내부 소비자·검증을 함께 정리한다. schema version 변경만으로 과거 계약의 호환 처리가 구현된다고 간주하지 않는다. 전체 과거 주버전의 영구 지원을 약속하지 않는다.

## 후속 명세와 다른 결정에 남기는 내용

CLI 옵션 및 `mobile.yml` 키, JSON 필드·상태·progress 형식, 종류별 정본 parser와 충돌 처리의 세부 표기는 후속 `/to-spec`에서 구체화한다. 기존 Check·Stage·Envelope·도메인 실패와 도구 장애의 용어를 출발점으로 삼는다.

설치 도구와 승인·변경·복구 정책, 기기 생성·실기기 개발 준비, 지원 SDK 버전과 검증 조합, 구현 순서·출시 단위는 선행 연구와 각각의 결정 티켓에서 정한다. 이번 초안으로 실제 실행 성공이나 지원 범위를 일반화하지 않는다.

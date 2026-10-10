# ADR-0020: RN baseline의 준비 입력을 별도로 고정한다

- 상태: 채택
- 날짜: 2026-10-10
- 관련: #199 · #212 · ADR-0006 · ADR-0012 · ADR-0018

## 배경

#212의 원본 frozen 준비에서 Mattermost의 Hermes checksum이 달랐다. 경로 문자열이 checksum에 영향을 준다는 사실은 확인했다. 원본 serialized spec은 확보하지 못했다. 따라서 원본과의 차이가 경로뿐이라고 입증하지 못했다.

#199는 과거 BlueWallet tracked 예외의 일반화를 금지한다. ADR-0018의 예외는 당시 고정 SHA와 iOS 게이트에만 적용한다. 이번 결정은 그 예외를 승계하지 않고 새 준비 입력을 허용한다. 원본 준비 실패와 과거 판정은 유지한다.

## 결정

원본 source SHA, 원본 lock과 원본 준비 실패 증거를 보존한다. 다음 제한된 준비 조건을 적용한 별도 복사본을 새 준비 입력으로 식별한다. 준비 입력의 고정만으로 known-good이라고 판정하지 않는다.

이번 예외는 #212의 Mattermost source `c2fe3beda22befd2178dce431793c09111ed903e`에 있는 `ios/Podfile.lock`의 `SPEC CHECKSUMS.hermes-engine` 값 하나의 재생성이다. BlueWallet, 다른 source SHA, 다른 checksum에는 자동 적용하지 않는다. Runstir가 checksum을 자동 수정하는 제품 기능을 추가하지 않는다.

앱 소스, 선언 버전, 의존성 그래프와 source 선언은 유지한다. 허용한 checksum 외의 모든 tracked byte는 준비 전 원본 checkout과 같아야 하며 Git index는 원본 HEAD와 같아야 한다. `assume-unchanged`와 `skip-worktree`로 변경을 숨기지 않는다. 원본 checksum의 생성 조건은 미확인으로 보존한다. 새 준비 입력의 독립 재현을 검증하며, 그 결과를 원본 대비 경로만 달랐다는 증거로 제시하지 않는다.

원본 `.gitattributes`는 `*.bat text eol=crlf`를 선언한다. 따라서 원본 checkout의 `android/gradlew.bat` raw byte와 저장된 HEAD blob의 LF byte는 다르다. 준비 전에는 원본 선언의 EOL 변환을 검증하여 Git 정규화 결과가 HEAD blob과 같은지 확인하고, 실제 checkout byte와 선언을 고정한다. 준비 뒤에는 그 실제 byte를 그대로 비교한다. 이것은 원본 checkout의 식별 방법이며 준비 중 source 변경이나 Git 설정 변경을 허용하는 예외가 아니다. 다른 원인으로 초기 byte를 귀속할 수 없으면 중단한다.

## 재현 절차와 증거

1. 각 fresh clone의 source SHA와 원본 checkout byte·index를 확인한다. 원본 선언의 EOL 변환과 HEAD blob 대응을 확인한 뒤 초기 raw byte를 고정한다. 도구 버전, host·runtime·기기, 앱 선택과 준비 명령을 고정한다. 기존 표본별 선언 버전을 유지한다.
2. 각 clone에서 같은 원본 프로젝트 준비 절차를 독립 수행한다. 원본 도구 선언을 사용하는 사람의 `pod install`로 checksum을 재생성한다. Pods와 node_modules를 다른 clone에서 복사하지 않는다. 검증한 공식 다운로드 archive의 캐시는 재사용할 수 있으며 hash와 재사용 사실을 기록한다.
3. 준비 전후 실제 tracked byte를 초기 raw byte와 비교한다. 허용한 checksum 한 값만 정규화한 lock 전체가 원본과 같아야 한다. 다른 tracked byte는 초기 원본 checkout과 같아야 하며 Git index는 HEAD와 같아야 한다. 실제 generated spec, 원본·준비 lock, raw diff, 파일 hash, 도구와 명령·경로·종료 상태를 증거로 고정한다. 준비 입력의 identity는 source SHA, 준비 절차, 검증 조합과 clone별 결과 hash를 함께 식별한다. clone 경로가 달라지면 raw checksum이 같다고 가정하지 않는다.
4. 준비 뒤 원본 도구 선언과 frozen Bundler를 사용하여 `pod install --deployment` 성공을 확인한다. 감사 결과와 frozen 성공이 모두 있어야 baseline build로 진행한다. build·install·launch·첫 화면 뒤에도 tracked byte·index를 감사한다.
5. 같은 표본별 검증 조합에서 Runstir 없이 baseline을 확인한다. 성공하면 별도 fresh clone에서 같은 준비와 frozen 검사를 독립 수행하고 후속 Runstir 검증에 인계한다. baseline의 Pods·node_modules·빌드 산출물을 인계 clone으로 복사하지 않는다. 같은 Simulator·Emulator·Metro를 사용하는 실제 실행은 직렬로 조정한다. 다른 작업의 자원을 변경하지 않는다.

원본 raw 증거는 로컬에 보존한다. 공개 증거는 #199의 비식별·비밀값 제외 규칙을 따른다. 공개용 경로 치환이나 로그 발췌를 원본 파일 byte 감사의 증거로 대신하지 않는다.

## 실패와 검증 범위

허용 범위 밖의 변경이나 필수 검증 실패가 나오면 중단하고 증거를 보존한다. 다른 checksum이나 버전을 추가로 바꾸지 않는다. 사용자 파일을 자동 복구하지 않는다. 조건을 바꾸려면 별도 결정과 새 실행이 필요하다. 원본 baseline 준비 실패를 Runstir 실패로 분류하지 않는다. 필수 입력 unknown이나 원인 불명을 성공으로 처리하지 않는다.

이번 checksum 대상 제한은 #212의 검증 범위를 줄이지 않는다. 최소 RN 앱과 실제 OSS 앱은 각각 iOS와 Android에서 build·install·launch·첫 화면을 확인해야 한다. Mattermost가 실제 OSS 표본이 될 수 있지만, 이 ADR의 채택은 iOS known-good 판정이 아니다. 필수 증거가 미달이면 #212는 미완료이며 PR #236을 병합하지 않는다.

#212는 baseline과 후속 fresh clone 인계 범위다. 실제 Runstir 검증과 공동 출시 판정은 후속 티켓에서 수행한다. 과거 BlueWallet 1/1 Go와 한 OSS 표본의 성공은 공동 1.0.0의 여섯 조합 게이트나 React Native 일반 지원을 대신하지 않는다.

## 대안

원본 lock의 모든 byte를 유지하고 다른 OSS를 조사할 수 있다. 이 방법은 원본 입력을 유지하지만 현재 고정 표본의 재현 조건을 해결하지 못한다. 제한된 준비 입력을 허용하는 대신 원본 성공과 준비 입력 성공을 구분하고, 예외 대상과 감사·frozen·독립 실행 조건을 고정한다.

# #203 도구 준비 증거

## 최신 실제 CLI 검증

[b6329329 실제 CLI 검증](actual-cli-b6329329.md)과
[curated JSON](actual-cli-b6329329.json)에 새 manager-absent store 실측을 기록했다.
mise·Java·Node·Ruby 설치 4개와 실제 SIGINT 취소를 확인했다.
4개 버전 조회도 통과했다.
최종 setup은 수동 단계 12개를 남겨 `partial`, exit `1`을 반환했다.
최종 `b6329329` GUI 실측은 아직 미완이다.
이 기록으로 GUI·앱 실행이나 #203 전체 완료를 판정하지 않는다.
[이전 CLI checkpoint](actual-cli-checkpoint.md)의 실패·미확인은 해당 후보의 기록으로 보존한다.

## 최초 source/fixture 인계 범위

아래 구현·검증·한계는 최초 source/fixture 인계 당시의 기록이다.
후속 실제 CLI 결과는 위 문서에서 구분한다.

이 묶음은 Node, Ruby, JDK 준비 provider와 공유 실행 연결의 source/fixture 근거다.
실제 배포 payload를 받거나 실행하지 않았다.
실제 설치, CLI·GUI 상태 전이, VM 검증은 아직 하지 않았다.
이 근거로 #203의 전체 수용 조건을 완료하지 않는다.

## 구현 경계

- `ToolRequirements`는 `.nvmrc`, `.node-version`, `.ruby-version`, `.java-version`,
  `.tool-versions`와 제한된 mise scalar 선언을 읽는다.
  exact 선언이 우선이다.
  범위에는 적합한 현재 도구를 먼저 사용한다.
  없으면 Node `22.23.2`, Ruby `3.2.2`, Temurin `17.0.18+8` 고정 후보를 검사한다.
  이 후보의 실제 VM 검증은 아직 하지 않았다.
  선언 범위와 알려진 호환 조건을 만족하지 않으면 수동 단계로 남긴다.
  Java 호환은 기존 Android AGP/Gradle/JDK 표를 재사용한다.
  새 설치에서 알 수 없는 표나 AGP 입력을 추측하지 않는다.
  읽을 수 없는 정본을 없는 정본으로 취급하지 않는다.
- `currentToolRunner`는 현재 프로젝트의 `which`와 버전 관측에만 사용한다.
  `runner`는 machine의 metadata, manager, 설치 저장소와 설치 action에 사용한다.
- 현재 실행 파일이 정확한 버전을 만족하면 재사용한다.
  다른 vendor의 Java 선언을 Temurin으로 바꾸지 않는다.
- 기존 JDK는 기존 Android properties collector를 재사용한다.
  `java.version`, `java.runtime.version`, `java.vendor`, `java.home`, `os.arch`가 필요하다.
  `java.home/bin/java`의 실제 properties도 확인한다.
  banner만으로 vendor나 build를 판정하지 않는다.
  필요한 properties가 없으면 정확한 재사용으로 승격하지 않는다.
  적합한 Zulu는 vendorless 또는 Zulu 선언에서 재사용할 수 있다.
  명시 Temurin 선언은 Zulu로 대신하지 않는다.
- 새 설치는 macOS arm64 배포만 지원한다.
  지원하는 새 Java 배포는 `temurin-x.y.z+build`다.
  해결할 수 없는 범위, 충돌, 새 설치의 미지원 vendor, 미확인 기존 설치는 수동 단계로 남긴다.
- 기존 mise를 재사용한다.
  원하는 실행 파일을 찾지 못하고 다른 manager를 감지하면 수동 단계로 남긴다.
  nvm, fnm, rbenv, RVM, asdf, SDKMAN의 숨은 설치를 실행하지 않는다.
- 지원하는 manager가 없으면 정확한 mise `2026.10.7` raw arm64 binary를 계획한다.
  전역 `PATH`, 사용자 shell, 기존 manager 설정을 바꾸지 않는다.
- 저장소는 `MISE_DATA_DIR`, `XDG_DATA_HOME/mise`, `HOME/.local/share/mise` 순서다.
  도구는 `installs/<tool>/<version>`에 나란히 설치한다.
  bootstrap mise는 `manager/2026.10.7/bin/mise`에 설치한다.
  환경 변수의 custom installs/layout는 수동 단계로 남긴다.
- Node와 Ruby는 archive root를 설치한다.
  Java는 archive의 `Contents/Home`을 설치 root로 사용한다.
  세 도구의 실행 파일은 설치 root의 `bin/<tool>`이다.
- 공식 metadata의 URL, 크기, SHA256과 선택한 asset identity를 계획에 고정한다.
  payload는 승인된 `InstallationAction`에서만 받는다.
  새 manager가 별도 payload를 받도록 허용하지 않는다.
- TAR 설치는 기존 `InstallationMetadata.validate`, download, destination 검사와
  `beforeCommit` 계약을 재사용한다.
  호출하는 공유 실행부가 승인, 재확인, lease를 소유한다.
  임시 디렉터리는 승인된 저장소 아래에 만든다.
  기존 cache에 쓰지 않는다.
  성공한 버전이나 기존 버전을 삭제하지 않는다.
- TAR 경로, 링크, entry 종류와 크기를 추출 전에 검사한다.
  선택한 package 밖의 링크를 commit 전에 거절한다.
  `RENAME_EXCL`로 목적지의 다른 소유자를 보존한다.
- stage의 실제 Mach-O architecture, platform, minimum macOS와 linked library를 검사한다.
  Ruby는 stage에서 OpenSSL, Psych, zlib, Fiddle도 확인한다.
  build runner 이름을 minimum macOS로 간주하지 않는다.
  Ruby source compile이나 보조 download는 실행하지 않는다.
- `ProjectExecutionEnvironment.activatingTools`는 child command의 정확한 실행 파일,
  `PATH`, `JAVA_HOME`만 선택한다.
  기존 tracked mise activation과 복구 명령도 같은 정확한 mise 경로를 쓴다.
  automatic installation은 끈다.

## 공유 실행부

`PreparationExecution`에 provider 결과를 연결했다.
설치 action이 있으면 도구가 필요한 npm/Gradle/Bundle 검사를 뒤로 미룬다.
도구 설치 후 새 계획을 관측하고 새로 필요한 변경은 다시 승인한다.
manual 단계만 있다는 이유로 기존 SDK 관측을 없애지 않는다.
`WorkflowContext`는 관측 전용 provider 결과와 정확한 실행 파일을 공유한다.
`EnvironmentInspection`은 기존 `WorkflowContext` 호출로 이 결과를 받는다.
`tools.*` 오류는 build/up의 dependency/build 전에 차단한다.
down은 새 도구를 요구하거나 관측하지 않는다.
`#205` Flutter manual 분기는 유지했다.
`#206` 공통 API는 그대로 사용했다.
공유 API 의존성은 `0e54bb1c7db760427d369119afdef92df3701298`이다.
기존 Java collector의 public 관측 API는
`df2a722578ddf1333903a8dfa53ee9cd7fa69581`이다.
절대 실행 파일 경계 수정은 별도 commit
`29a005ab7466f9272982b69540bb5949c639a72e`다.
로컬 stack은 `#211`의 `ebe18445d464b83351ec2f2a6b9de562372393ac`와
`de99bcad1b2cc171d6a37e832914f2a475c13aaf`도 포함한다.
그 변경은 #203의 독립 기여가 아니다.

1. 기존 선언과 호환 입력에서 `ToolPreparationRequirement`를 만든다.
2. 계획에서 machine runner와 현재 project runner를 구분해 `inspect`에 전달한다.
3. `checks`, `installed`, `actions`를 기존 공유 준비 결과에 합친다.
4. 설치 후 다시 관측한다.
5. 측정한 `activeTools`를 `activatingTools`로 프로젝트 실행 환경에 전달한다.
6. doctor/build/up 관측에는 `planInstallations: false`를 사용한다.
   이 모드는 공식 metadata를 읽거나 설치 action을 만들지 않는다.

## 검증 범위

최초 source/fixture 인계의 제품 source는 `7fac827f7b086ef754d37c71da94946247aa2e0a`다.
전체 Werror 실행은 80개 suite의 655개 테스트를 통과했다.
그 뒤 제품 변경 없이 추가한 Node `v` 접두 fixture 1개도 통과했다.
이 fixture의 파일명에는 `red`가 있지만 실제 결과는 PASS다.
기존 `SemanticVersion`이 이미 접두를 처리하므로 결함으로 판정하지 않았다.
최종 CLI 입력 fixture 3개도 통과했다.
이 입력 fixture를 실제 도구 설치나 실제 앱 실행으로 간주하지 않는다.

전체 실행과 CLI 입력 명령은 다음과 같다.

```sh
swift test --disable-automatic-resolution -Xswiftc -warnings-as-errors
python3 scripts/verify-doctor-input.py .build/out/Products/Debug/mobile
python3 scripts/verify-workflow-input.py .build/out/Products/Debug/mobile
python3 scripts/verify-setup-input.py .build/out/Products/Debug/mobile
```

fixture는 synthetic gzip/TAR와 fake metadata를 사용한다.
실제 실행한 프로세스는 소유한 임시 경로의 shell fixture, Git, gzip과 기존 process tests다.
Node, Ruby, Java, mise, lipo, otool은 provider fixture에서 fake다.
fake-mise shell fixture는 실제 mise 제품이 아니다.
공식 metadata의 읽기와 Node archive의 HTTP HEAD는 별도 정적 관측이다.

| 수용 조건 | 현재 근거 | 남은 검증 |
| --- | --- | --- |
| 기존 manager와 정확한 설치 계획 | 현재 project tool 재사용, mise 재사용/부재, vendor 보존, 공식 metadata fixture | 실제 지원 manager 및 배포 payload |
| 기존 버전 보존과 프로젝트 활성화 | side-by-side 파일 보존, exact child path, `JAVA_HOME`, 전역 선택 marker 보존, fake-mise 실제 프로세스 | 실제 toolchain과 프로젝트 실행 |
| CLI·GUI 공통 의미 | 공유 준비·doctor·workflow 경로에 provider를 연결 | 실제 양 surface 상태 관측 |
| 실패·취소·대기·재확인·재실행 | 세 도구의 download 실패/취소, 부분 완료 유지, 남은 action retry, manual 단계, commit 직전 거절 fixture | 실제 다운로드 중 취소, 양 surface 대기/재확인, VM 실측 |
| #199 AC02·AC03 | 정확한 artifact pin과 설치 경로의 source/fixture 근거 | 실제 설치·활성화·원본 보존 근거 |

원본 로그와 metadata 파일 61개를 private receipt에 보존했다.
공개 `fixture-receipts.json`은 그중 28개 로그의 SHA256과 핵심 발췌를 담는다.
각 발췌의 행 번호는 private 원본 로그를 가리킨다.
공개 발췌는 private 경로를 정규화할 수 있다.
발췌를 원본 로그의 byte 사본으로 주장하지 않는다.
명령을 보존하지 않은 중간 로그는 `command: null`로 남긴다.
중간 fixture 오류와 소유 test process를 종료한 이력도 최종 PASS와 구분한다.
`official-metadata.json`은 metadata 관측이다.
그 파일은 payload byte 검증이나 실제 설치 성공의 근거가 아니다.
Node HTTP HEAD의 원본 header는 보존하지 못했다.
그 관측을 이 묶음의 독립적인 archive 크기 증거로 사용하지 않는다.
`manifest.json`의 `source_head`는 최초 source/fixture 제품 source를 가리킨다.
`files`는 현재 공개 문서 4개의 SHA256과 크기를 고정한다.
이 파일 목록은 `source_head` 시점의 문서 snapshot이 아니다.
실제 CLI receipt 파일은 이 목록에 포함하지 않는다.
manifest 자체는 그 목록에서 제외한다.

## 남은 한계

- 실제 공식 archive의 TAR 특성, 실행 가능성, ABI와 library 범위는 아직 검증하지 않았다.
- 실제 lipo/otool 사용 가능 여부와 Xcode 선택은 후속 실행에서 확인해야 한다.
- mise의 custom 설정 파일에 있는 store/layout 설정은 이 provider에서 해석하지 않는다.
  지원 범위는 후속 공유 계획 연결과 독립 리뷰에서 확인해야 한다.
- 전체 Swift Werror와 CLI 입력 smoke는 `fixture-receipts.json`에 기록한다.
- Linux compile, 독립 리뷰, 원격 CI와 실제 VM·CLI·GUI 검증은 root가 조정한다.
- 실제 SDK, manager 설치, 네트워크 payload, VM, GUI, 기기는 실행하지 않았다.
- 원본 SDK/cache/HOME 전체 보존을 측정한 근거는 없다.

## 공식 source

- [Node 배포 checksum](https://nodejs.org/dist/v22.23.2/SHASUMS256.txt)
- [jdx/ruby 3.2.2 release](https://api.github.com/repos/jdx/ruby/releases/tags/3.2.2)
- [jdx/ruby 고정 package source](https://github.com/jdx/ruby/blob/290439c46673f25b77bd9ada0f1375a2268d2a46/libexec/package.rb)
- [jdx/ruby 고정 dependency source](https://github.com/jdx/ruby/blob/290439c46673f25b77bd9ada0f1375a2268d2a46/recipes/dependencies.yml)
- [Temurin 17.0.18+8 release](https://api.github.com/repos/adoptium/temurin17-binaries/releases/tags/jdk-17.0.18%2B8)
- [mise 2026.10.7 release](https://api.github.com/repos/jdx/mise/releases/tags/v2026.10.7)
- [mise 고정 Java layout source](https://github.com/jdx/mise/blob/v2026.10.7/src/plugins/core/java.rs)

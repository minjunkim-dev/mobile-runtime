# CI 캐시 재현성 검증

issue #133의 CI는 저장소 위생, macOS build·test, Linux Core compile을 병렬로
실행한다. 필수 check는 결과를 모으는 `CI` 하나다. 셋 중 실패·취소·skip이 있으면
`CI`도 실패한다. LICENSE와 README의 SPDX 선언은 #132의 공개 문서를 기준으로 한다.

## 캐시와 무효화

SwiftPM 공유 의존성과 빌드 산출물을 따로 캐시한다. key는 `CACHE_VERSION`(`v1`),
runner OS·arch, 툴체인 fingerprint, `Package.resolved` 해시로 만든다. 빌드 key에는
manifest·소스·resource·검증 script·workflow 해시를 더하고 macOS는 테스트도 포함한다.
Linux 소스 해시는 Core에 한정한다. macOS fingerprint는
Xcode·Swift·SDK 버전이며, Linux는 고정 Swift 이미지 digest와 컨테이너 Swift 버전이다.
다른 key로 복원하는 fallback은 없다. 전체 무효화는 workflow의 `CACHE_VERSION`을
`v2`처럼 올린다. 툴체인이나 Linux 이미지가 바뀌어도 기존 캐시는 재사용하지 않는다.

모든 build·test는 `--force-resolved-versions`로 lockfile만 사용한다. 캐시 없이
실행할 때는 `workflow_dispatch`의 `use-cache=false`를 지정한다. 이 경우 캐시 복원과
저장을 모두 건너뛴다. 툴체인 버전과 캐시 hit 여부는 각 job의 step summary에 남는다.

## 공개 전환 후 같은 SHA로 검증한다

현재 billing으로 실행할 수 없는 원격 검증은 전환 후 티켓에서 수행한다.

1. 검증할 branch의 full SHA를 기록한다. LICENSE/SPDX를 포함한 같은 SHA에서 아래
   실행을 끝낼 때까지 branch를 변경하지 않는다.
2. Actions의 `CI` → `Run workflow`에서 `use-cache=true`로 두 번 실행한다. 첫 실행의
   miss 또는 기존 hit를 기록하고, 두 번째 실행의 의존성·빌드 exact hit를 확인한다.
3. 같은 branch에서 `use-cache=false`로 실행한다. summary의 disabled 상태와 캐시
   step의 skip을 확인한다. 세 실행의 head SHA와 OS·arch·툴체인이 같은지도 확인한다.
4. 세 실행의 위생 검사, macOS build·test 결과와 테스트 수, Linux Core compile,
   `Package.resolved` 무변경 결과를 대조한다. 같은 결과와 `CI` success를 확인한 뒤
   실행 URL·full SHA·툴체인·hit 여부를 후속 티켓에 기록한다. 두 번째 캐시 사용 실행도
   miss이거나 게이트가 실패하면 그 상태를 남기고 재현성 통과로 처리하지 않는다.

로컬 검증은 `swift build --force-resolved-versions`,
`swift test --force-resolved-versions`, `scripts/verify-core-linux.sh`, `actionlint`,
`shellcheck scripts/*.sh`다. Docker·Swift 이미지나 검사 도구가 없으면 설치하지 않고
미실행 사유를 PR에 적는다. 이 검증은 CI 재현성 판정이며 앱 alpha·지원 범위 판정이 아니다.

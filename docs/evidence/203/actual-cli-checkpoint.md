# #203 CLI 실측 checkpoint

판정은 **inconclusive**다.
Node·Ruby·JDK 설치 완료와 첫 absent-store 승인 실행의 실제 GREEN은 아직 확인하지 못했다.
이 기록으로 #203 수용 조건을 완료하지 않는다.

## 후보와 실행 범위

| 후보 | source | CLI SHA256 |
| --- | --- | --- |
| 구 후보 | `279a5e2bd1d00e69cdf5a7293ade028dbb2c75e4` / 제품 `7fac827f7b086ef754d37c71da94946247aa2e0a` | `dd0fca8ce08077ddd00b7e835da4eed9d0eaea2ebddb215cc8d858e701a60d3f` |
| 수정 후보 | `cdaa7e5496991a851153a68827b25602d033a2cf` | `bcfa4af7b2c70c5f3fd2a70b53cb4e429fc23652165e62d71ed1503e05b301e7` |

후보는 이전 로컬 #211·#206 stack을 포함한다.
root의 최신 통합 제품이나 출시 후보와 같다고 주장하지 않는다.
보존 baseline의 기존 clone에서만 실행했다.
입력은 정확한 Node `22.23.2`, Ruby `3.2.2`, Temurin `17.0.18+8`을 선언한 소유 프로젝트다.
Gradle `8.10.2`와 AGP `8.7.3`을 정적 호환 입력으로 제공했다.
이 프로젝트를 실제 OSS 앱의 실행 근거로 사용하지 않는다.

## 관측 결과

| case | 실제 결과 | 범위 |
| --- | --- | --- |
| 01·02 구 후보 첫 계획·승인 | 계획 exit 0. 승인 exit 1. 완료 0. payload 요청 0 | 저장소 생성 후 URL 끝 `/`가 달라져 metadata equality를 거절했다. |
| 03·04 재계획·오래된 승인 | 새 계획을 반환했다. 오래된 승인은 exit 1 `needs-approval` | 변경 작업을 시작하지 않았다. |
| 05 구 후보 재승인 | mise 설치 완료 뒤 Java 다운로드 exit 7. CLI exit 1 `failed` | 소유 transport wrapper가 Java payload에 도달할 수 없는 loopback proxy를 적용했다. 공식 URL·pin은 바꾸지 않았다. 자연 발생 vendor 장애가 아니다. |
| 06·07 수정 후보의 새 prefix 첫 계획·승인 | 계획 exit 0. 승인 exit 1. 완료 0. payload 요청 0 | absent 상태부터 root URL 끝 `/`를 고정했다. 첫 재확인 중 GitHub API 제한이 발생했다. 실제 수정 GREEN은 미확인이다. |
| 08·09 API 부재 재계획·승인 | install/align 0. CLI exit 1 `waiting-manual` | metadata 부재를 설치 성공으로 처리하지 않았다. |

실제 mise payload는 127277984 bytes다.
직접 계산한 SHA256은 `f5171e341518a57e8c4e9280e28443e35d66212c51164c83be76794e0a78b014`다.
계획의 공식 pin과 일치했다.
기존 prefix의 mise `2026.10.7`은 보존했다.
Node·Ruby·JDK 완료는 0개다.

공식 GitHub 응답은 HTTP 403, limit 60, used 60, remaining 0이었다.
응답의 reset은 `1792117728` / `2026-10-16T02:28:48Z`다.
캐시 metadata로 stock CLI 실측을 대신하지 않았다.
API를 반복 호출하지 않고 중앙 VM lease를 반환했다.

## 수정과 보존 경계

`cdaa7e5`는 저장소 URL을 처음부터 directory URL로 만든다.
같은 결함의 fixture는 `MISE_DATA_DIR`, `XDG_DATA_HOME`, `HOME` 세 case에서 수정 전 실패했다.
수정 후 관련 21개 테스트와 전체 657개 테스트/80개 suite의 Werror 실행이 통과했다.
unit 통과와 실제 설치 통과를 구분한다.

원본 baseline은 계속 stopped였다.
config·manifest·NVRAM 전체 SHA256과 disk stat은 전후 같았다.
disk 전체 bytes와 전체 VM/cache bytes는 해시하지 않았다.
clone의 전역 PATH, 소유 프로젝트 8개 파일 SHA256과 raw index SHA256은 같았다.
clone의 `Library/Caches` 디렉터리 크기와 mtime은 달라졌다.
그 하위 bytes와 변경 actor·원인은 확인하지 못했다.
이를 전체 cache 보존 PASS로 기록하지 않았다.
mtime을 복원하지 않았다.

설치 프로세스 0개를 확인한 뒤 `tart stop`이 exit 0으로 끝났다.
원본·clone·부분 설치·실패 이력은 보존했다.
같은 source의 private GUI 후보는 build와 ad-hoc strict/deep 서명 검사만 통과했다.
GUI를 실행하지 않았다.
Developer ID·공증·배포·실제 GUI 결과를 검증한 근거가 아니다.

private checkpoint index SHA256은 `b40dee2806b7587135652e65d5cf559a6a9f461eb0d190636339fc30fa1b09ca`다.
그 index는 원본 receipt·후보·운영 script 62개 파일을 연결한다.
전체 raw 로그나 개인 경로를 이 문서에 복사하지 않는다.
다운로드 중 취소, 세 도구의 완료·재검사·재실행과 실제 GUI 수용 조건은 남아 있다.

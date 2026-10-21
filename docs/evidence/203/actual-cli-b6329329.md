# #203 b6329329 실제 CLI 검증

2026-10-16에 manager가 없는 새 저장소에서 mise·Java·Node·Ruby 설치를 확인했다.
실제 다운로드 중 취소와 재승인도 확인했다.
최종 setup은 수동 단계 12개를 남겨 `partial`, exit `1`을 반환했다.
설치 오류는 없었다.
최종 `b6329329` GUI 실측은 아직 미완이다.
이 기록으로 앱 실행이나 #203 전체 완료를 판정하지 않는다.

공개 [curated JSON](actual-cli-b6329329.json)에 정확한 pin과 제한된 receipt 참조를 기록했다.
이전 [CLI checkpoint](actual-cli-checkpoint.md)의 실패·미확인은 그 후보의 기록으로 보존한다.

## 후보와 실행

- base: `c3dfcf806e7250ecef8b0fe2dfeac2a1d8348502`
- 실측 source HEAD: `b6329329a95b93e39283fa3cc11b9b73af73205f`
- 31파일 canonical diff SHA256: `a501a1a9d3d924702d4aa5ce9f6ba81cd79ba38b1e4f2aef796127444907534d`
- CLI SHA256: `23bcc69031678029a62c7618bde9fca00d81ace1d77ddfc0072011f09447a1aa`

실측 당시 source는 clean이었다.
후보 13파일의 host·guest SHA256, bytes와 mode가 같았다.
현재 제품 code blob은 실측 HEAD와 같다.
이 문서 3개는 그 뒤의 증거 변경이다.
문서 변경으로 CLI를 다시 만들지 않았다.
JSON은 204개 code blob의 목록 hash와 후보 파일 mapping을 구분한다.
동일한 source로 byte가 같은 binary를 재생성했다고 주장하지 않는다.

입력은 선언·정적 호환 파일 8개와 `.git`을 복사한 소유 프로젝트다.
hardlink는 없다.
새 `HOME`, tmp와 빈 `MISE_DATA_DIR`를 사용했다.
초기 `PATH`는 `/usr/bin:/bin:/usr/sbin:/sbin`이었다.
기존 system Ruby는 변경하지 않았다.
stock `/usr/bin/curl`의 SHA256과 kernel 실행 경로를 확인했다.
wrapper, proxy, 인증, curl 설정과 payload 대체는 사용하지 않았다.

| 승인 대상 | 버전 | 공식 payload bytes |
| --- | --- | ---: |
| mise | `2026.10.7` | 127277984 |
| Java | `Temurin 17.0.18+8` | 185658966 |
| Node | `22.23.2` | 50068815 |
| Ruby | `3.2.2` | 39479292 |

정확한 공식 URL, metadata SHA256, artifact SHA256과 목적지는 JSON에 있다.
mise는 raw 실행 파일이다.
나머지 3개는 TAR archive다.
4개 설치는 선택한 tool-store root의 resourceKey 하나를 공유했다.
도구 버전별 lock 예외는 사용하지 않았다.

## 관측 결과

최초 PLAN ID는 `13c1cde2a78bef9d0e2874597fdd8d854e50688d12e18bcf8e4a60fe8e4009e1`이다.

| 단계 | 실제 결과 |
| --- | --- |
| 최초 계획 | install 4개와 manual 3개. `needs-approval`, exit `0`. |
| 최초 승인과 취소 | mise raw 다운로드 585728B에서 소유 mobile parent에 SIGINT 1회. `cancelled`, exit `130`. 완료 0개. 7.945초. |
| 취소 후 감사 | 새 store entry 0개. 소유 CLI·tool process 0개. root lease 파일 0B. |
| 재PLAN 1회 | 전체 installation dictionary·전체 steps·manual·remaining이 최초 PLAN과 같았다. 새 automatic 단계는 0개다. 상태가 같아서 PLAN ID도 같았다. |
| 남은 설치 재승인 1회 | 4개 stage가 모두 `succeeded`였다. 완료 4개. 오류 없음. `partial`, exit `1`. 126.334초. |
| 설치된 실행 파일 조회 | mise `2026.10.7`, Temurin `17.0.18+8`, Node `22.23.2`, Ruby `3.2.2`. 4개 모두 exit `0`. |

SIGINT 전에 PID, PPID, 시작 시각, kernel 실행 경로와 PGID를 대조했다.
소유 mobile parent PID 하나에만 신호를 보냈다.
완료된 도구를 다시 설치하지 않았다.
최종 반환 PLAN ID는 `654c6c7d906d9bad3c1216e609f80c6f5946afce008ea1d5081f4c738af30383`이다.
남은 12개는 SDK·프로젝트 관측과 dependency 수동 단계다.
그 단계의 변경이나 앱 build를 실행하지 않았다.
버전 조회 child는 선택한 정확한 실행 파일과 child `PATH`·`JAVA_HOME`을 사용했다.
전역 선택을 바꾸지 않았다.

## 보존 범위와 한계

원본·복사 프로젝트의 tracked bytes, index, stage flags와 config가 같았다.
기존 후보 6개 root와 mise binary 2개를 보존했다.
기존 Java·Node·Ruby tree의 regular bytes·SHA256·mode와 symlink target이 같았다.
이전 dfc actual02의 index 166개 파일도 같았다.
보호 VM 6개는 전후 stopped였다.
그 VM의 작은 metadata 전체 SHA256과 disk stat이 같았다.
전체 disk bytes는 hash하지 않았다.

선택한 HOME 항목 중 `Library/Caches` root mtime만 달랐다.
크기 1824B와 mode `0700`은 같았다.
변경 actor와 원인은 미확인이다.
전체 HOME·cache bytes 보존으로 판정하지 않는다.

Java·Node·Ruby 원본 archive 3개의 bytes와 SHA256은 공식 pin과 같았다.
mise는 curl 종료 관측 전에 다운로드 경로에서 이동해 그 위치의 snapshot을 놓쳤다.
설치된 raw mise를 읽기 전용으로 복사했다.
그 bytes와 SHA256은 승인한 공식 raw pin과 같았다.
증거를 위해 다시 다운로드하지 않았다.
최초 finalizer는 다운로드 위치 snapshot 4개를 가정해 실패했다.
실패한 script와 실패 기록을 보존했다.
후속 감사는 archive snapshot 3개와 설치된 raw mise를 구분했다.

최종 소유 child와 stage root는 0개다.
정확한 root·folder lease 파일 2개는 각각 0B다.
기존 설치 삭제나 원자적 rollback을 측정한 근거는 아니다.
CLI 작업자는 VM boot·stop·GUI를 실행하지 않았다.
그래픽 VM의 정상 종료와 run exit 수집은 Root 소유 범위다.
이전 dfc guard 실패 원인은 계속 미확인이다.

private HANDOFF SHA256은 `38f29db83b21d4a2f6fdbe6e6ba89bacae1fdc3c65df5ee1ed9ada1329a3c20c`다.
188파일 private index SHA256은 `083cc7613c8672f5902a74673ccd7c31f78d483db6a5b20b2da3da457cd5185e`다.
그 188개 파일의 SHA256·bytes·mode를 독립적으로 재확인했다.
공개 JSON은 private bundle 기준 상대 receipt 경로와 SHA256을 연결한다.
각 참조는 필요한 JSON 필드 또는 NDJSON 행 범위만 지정한다.
개인 경로는 정규화했다.
원본 로그·payload·인증 정보는 이 공개 묶음에 복사하지 않았다.

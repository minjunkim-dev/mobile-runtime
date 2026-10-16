# #204 시도 이력

모든 실제 실행은 소유 prefix와 동일한 쓰기 guard를 사용했다.
Emulator guest와 ADB server를 시작하지 않았다. 새 license를 수락하지 않았다.
원본 로그는 `private-receipts.json`의 소유 경로에 남긴다.

| 시도 | 관측 |
| --- | --- |
| 1 | 소유 harness 옆 resource bundle이 없어 abort했다. 제품 실패로 분류하지 않았다. bundle을 복제했다. |
| 2 | 실제 기존 SDK package를 재사용하는 계획을 관측했다. tuple과 요구 blocker 0개를 확인했다. |
| 3–4 | raw license SHA 판단을 공식 sdkmanager와 JAXB adapter로 대조했다. 기존 수락 hash 재사용을 확인했다. 새 수락은 없었다. |
| 5 | 소유 copy의 정확한 package 두 개만 quarantine으로 이동했다. 고정 archive 두 개의 계획을 관측했다. |
| 6 | 전역 Foundation temporary directory 쓰기를 guard가 차단했다. 다운로드 전 실패했다. scratch를 승인 SDK root로 옮겼다. |
| 7 | 실제 Build Tools 다운로드 뒤 취소했다. product exit 130, 완료 0개, package 부재, scratch 잔여 0개였다. source는 `c45fe2e`였다. |
| 8–9 | 최종 210 context와 연결한 계획을 확인했다. Build Tools의 실제 size·SHA-1·추출을 확인했다. metadata의 `.atomic` write가 guard 아래 실패했다. |
| atomic/regular probe | 같은 소유 위치에서 무해한 Foundation atomic write는 실패했다. 일반 write는 성공했다. 외부 쓰기 예외를 추가하지 않았다. owned stage metadata write를 바꾸고 최종 package의 exclusive rename을 유지했다. |
| 10–11 | `0b0cd7d`에서 Build Tools를 실제 설치했다. 두 번째 payload 전에 의도한 harness 실패를 넣었다. 완료한 첫 package를 보존했다. 실제 network 실패로 표현하지 않는다. |
| 12–13 | 남은 platform 하나의 새 계획을 확인했다. 이전 plan-id는 product exit 1, `needs-approval`, 완료 0개로 거부했다. |
| 14 | 같은 SDK root의 소유 lease를 잡았다. 정확한 destination key와 소유자를 반환하고 다운로드 전에 중단했다. |
| 15 | `a50d652`의 재관측 중 Gradle model timeout으로 실패했다. 원인을 단정하지 않는다. 완료한 Build Tools 171개 파일의 bytes·mode가 같았다. 소유 JVM 잔여는 관측되지 않았다. |
| 16 | `a50d652`에서 남은 platform의 실제 size·SHA-1과 commit을 확인했다. SDK install 단계는 0개가 됐다. AVD와 workspace 수동 단계가 남아 `partial`이었다. |
| 17 | CMake 독립 리뷰 수정과 최종 210 기준을 반영한 `73f20f9`의 공개 API 계획을 확인했다. SDK install 0개와 요구 blocker 0개였다. |
| 실제 CLI | 같은 `73f20f9`의 `mobile setup --plan --non-interactive --json`은 exit 0이었다. 공개 API와 같은 tuple·SDK install 0개·요구 blocker 0개를 반환했다. CLI 설치는 실행하지 않았다. |

초기 시도 4–5의 harness receipt에는 이전 HEAD가 하드코딩되어 있었다.
이를 소유 `assessment-corrections.json`에 기록했다. 당시 compiled 수정은 나중에 `09c8018`로 커밋했다.
후속 receipt는 실제 Git HEAD를 읽는다. binary/source SHA-256도 별도로 기록한다.

# #212 기존 ADB 근거의 보존과 대응

공개용 경로 치환본이다. 원본 로컬 조사 문서는 별도로 유지한다. `EVIDENCE_ROOT`·`SESSION_RECORD`·`SELECTED_ADB`·`SOURCE_TEMP_ROOT`·`PRIVATE_METADATA_RECEIPT`는 비공개 경로의 역할이다. 근거의 파일 이름·행·크기·hash와 판정은 유지한다. 공개용 경로 치환을 원본 파일 byte 감사의 증거로 사용하지 않는다. 저장소 문서 인용은 조사 당시 정책 기준 commit의 permalink다. 이 공개용 문서를 만들 때 원본 evidence를 다시 읽거나 공식 URL을 조회하지 않았다.

조사일: 2026-10-12, Asia/Seoul. 대상: [issue #212](https://github.com/minjunkim-dev/mobile-runtime/issues/212).
정책 기준: PR #254 병합 commit `bab865b6ad79559325dc460fd2b3a2117d8b304c`의 ADR-0033·ADR-0034다.

기존 기록 조사에서는 기존 파일과 기록만 읽었다. 그 조사 결과는 새 정책 채택이나 실제 준비 권한이 아니다. 실제 환경 수집·resource 조회·GUI/ADB 시작·SDK binary 실행을 수행하지 않았다. SDK 설치 경로의 현재 파일·metadata·key를 읽지 않았다. 기존 기록 조사에서는 network fetch·download·설치·source 복원을 수행하지 않았다. 원본 봉인 evidence를 수정하지 않았다. 이후 Q1에서 확정한 새 HTTPS 메모리 읽기는 아래의 별도 단계에 귀속한다.

## 확인 결과

기존 SDK catalog와 설치 목록 기록은 보존돼 있다. catalog는 macOS용 Platform-Tools `37.0.1` archive 이름·크기·SHA-1을 기록한다. 설치 목록은 같은 revision을 기록한다. 이 두 기록은 실제 archive payload와 설치 ADB가 같다는 증거가 아니다.

AOSP source pin과 일곱 source hash는 ADR-0033에 남아 있다. 기존 `/tmp`의 source 파일과 metadata receipt는 확인한 경로에서 없었다. E22 provenance는 정책과 모델 및 이전 packet hash를 기록한다. E22 provenance는 AOSP source bytes의 보존 목록이 아니다. 따라서 설치 ADB와 pinned source 및 전체 build의 대응은 `UNKNOWN`이다.

## 기존 SDK catalog와 설치 기록

증거 root는 `EVIDENCE_ROOT`이다. 아래 hash는 이번 조사에서 기존 파일 bytes로 계산했다. hash는 보존한 파일의 identity만 나타낸다. 기록의 원격 origin이나 과거 설치 과정을 새로 인증하지 않는다.

| 기존 파일 | 크기 | 이번 SHA-256 | 직접 확인한 내용 |
| --- | --- | --- | --- |
| `EVIDENCE_ROOT/android-repository.xml:11400` | `419999B` | `13dd16e8984cc6f3202a72c8eb269bd7ad03be4247b41b4412b315c5b8bf6d4b` | `remotePackage[@path='platform-tools']`의 revision과 host별 archive metadata다. |
| `EVIDENCE_ROOT/sdkmanager-list.log:16` | `108342B` | `40a5a51c7ec7491ea9e0d868bc78afd2534e1d37ba7ded7dc39aa6251b683100` | Installed packages에 `platform-tools 37.0.1`을 기록한다. `:199`의 Available Packages도 같은 revision이다. 이 기록은 현재 설치 상태의 조회가 아니다. |
| `EVIDENCE_ROOT/sdk-install.log:2` | `136B` | `bb9be8378c1e3d581a1526cf21e3fd2414163b1bde14d3ae892090b2a5866fd0` | `platforms;android-37`을 찾지 못한 경고다. Platform-Tools archive 설치 완료 receipt가 아니다. |
| `EVIDENCE_ROOT/sdk-build-tools-install.log:1` | `1B` | `01ba4719c80b6fe911b091a7c05124b64eeece964e09c058ef8f9805daca546b` | newline 한 개다. ADB build provenance를 담지 않는다. |

`android-repository.xml:11402–11406`은 revision `37.0.1`을 기록한다. macOS archive 항목은 아래와 같다.

| XML 위치 | 기록 값 |
| --- | --- |
| `remotePackage[@path='platform-tools']/archives/archive[host-os='macosx']/complete/size`, `:11421` | `16110554` |
| 같은 항목의 `checksum[@type='sha1']`, `:11422` | `6ae73f4de6452dc57e62ec02b68eed92a4c21661` |
| 같은 항목의 `url`, `:11423` | `platform-tools_r37.0.1-darwin.zip` |
| 같은 archive의 `host-os`, `:11425` | `macosx` |

이 SHA-1은 catalog에 선언한 archive hash다. 이번 조사에서 archive bytes로 계산한 hash가 아니다. 확인한 위치에서 해당 ZIP을 찾지 못했다. 따라서 ZIP checksum 검증·archive 내부 `adb` hash·설치 payload 일치는 미확인이다. 같은 revision 문자열만으로 source commit이나 build 입력을 대응시키지 않는다.

## AOSP source와 E22 보존 기록

[ADR-0033:21](https://github.com/minjunkim-dev/mobile-runtime/blob/bab865b6ad79559325dc460fd2b3a2117d8b304c/docs/adr/0033-rn-gui-adb-resource-preparation.md#L21)은 AOSP `platform/packages/modules/adb`의 pin `fb529d52f4485c1fdbe6208f20af6578493e1ca7`을 기록한다. ADR-0033의 이번 SHA-256은 `f85fb94264b3ffca63b03b2ca808be309181dc14727a63881abfce45e209863c`다. 크기는 `20287B`다. [ADR-0034:42](https://github.com/minjunkim-dev/mobile-runtime/blob/bab865b6ad79559325dc460fd2b3a2117d8b304c/docs/adr/0034-rn-adb-environment-evidence-gap.md#L42)도 같은 pin의 조건부 endpoint 계산을 기록한다. ADR-0034의 이번 SHA-256은 `86ed9e6a5da188054e04cf3fb56445429d088ada04590fb8804c77ad6146e0c1`다. 크기는 `5734B`다.

아래 값은 [ADR-0033:27–33](https://github.com/minjunkim-dev/mobile-runtime/blob/bab865b6ad79559325dc460fd2b3a2117d8b304c/docs/adr/0033-rn-gui-adb-resource-preparation.md#L27)에 보존된 source hash다. 이번 조사에서 source bytes로 재검증한 값이 아니다.

| pinned source | 기록된 SHA-256 |
| --- | --- |
| `client/commandline.cpp` | `a3da993989356e95f864744833bf309c2175d7a7e5110bf5d2c7e36e521ae349` |
| `client/main.cpp` | `8ffbd78cce04df0d5d1a1fc358ce99a59c63f4dec8224d1d3090c14a240a7a1d` |
| `client/adb_client.cpp` | `9f1f14d7bbad7ebb7ccbc5c92f917f0a737f37ac42c41d2c5e9ac76438ee1d7c` |
| `client/auth.cpp` | `aba13cf80b3db2998962127d687a09225cd831d3760dd55d0876b9ed5bf0ea75` |
| `adb_utils.cpp` | `747a7ceff6eedcc62b8ee9c6f962028d560f7abc4473135a032afb5c479d71a0` |
| `client/adb_wifi.cpp` | `3d57dcdd3e0cd5dba9c66fb42dd962bf1bfcf48d9ad0599cbad720789da0ba4d` |
| `adb.h` | `448530595669e914264f314765c9d839dbc82c29e8f1e9a23b21738f23d4606a` |

`SOURCE_TEMP_ROOT/source-index.json`·`SOURCE_TEMP_ROOT/client/commandline.cpp`·`PRIVATE_METADATA_RECEIPT`은 이번 확인에서 없었다. 이 결과는 해당 경로의 부재다. 모든 저장소에서 복사본이 없다는 주장이 아니다.

E22 `EVIDENCE_ROOT/attempt-22-gui-adb-source-model/source-reference-provenance.json`은 보존돼 있다. 이번 SHA-256은 `396eca70feb75a1c808c396bdad892b10346cdb65280f71d35193313b9e30ff1`다. 크기는 `22343B`다. `/kind`는 `MODEL-ONLY`다. `/actualAuthority`와 `/actualReadiness`는 false다. `/policyDocRefs`는 정책 문서 hash를 연결한다. `/oldPacketRefs`와 `/e21RecursiveRefs`는 과거 검증 packet 및 helper 기록을 연결한다. `/sourceProof/syntaxFiles`는 `memory_selfcheck.py`와 `resource_model.py`만 나열한다. `/sourceOnlyReads`는 당시 읽기 범위의 기록이다. 이 문자열은 AOSP source bytes를 이 packet에 보존했다는 증거가 아니다.

E22 `EVIDENCE_ROOT/attempt-22-gui-adb-source-model/PLAN.md:17`은 symbolic foreground argv 비교를 실제 설치 binary 대응 증거로 사용하지 않는다. `EVIDENCE_ROOT/attempt-22-gui-adb-source-model/SOURCE_ONLY_SUBMISSION.md:11`은 E22가 원본 source와 packet을 복사하지 않았다고 기록한다. E22의 현재 파일 11개에는 AOSP source bytes나 SDK archive가 없다.

## 설치 binary와 build 대응의 판정

[ADR-0033:23](https://github.com/minjunkim-dev/mobile-runtime/blob/bab865b6ad79559325dc460fd2b3a2117d8b304c/docs/adr/0033-rn-gui-adb-resource-preparation.md#L23)은 당시 선택한 `SELECTED_ADB`를 기록한다. 기록된 크기는 `18844128B`다. 기록된 SHA-256은 `1811e253b21b12cbfda7201ebaf86c10e7ddcb5c606a7a81f7c82b4c429c2d3b`다. 당시 SDK metadata revision 두 개와 embedded version 후보는 `37.0.1`이었다. 당시 binary 실행은 없었다. 원본 private metadata receipt의 기록된 SHA-256은 `c1eaeeae2bee9b93df35b0112040bb61d7690435639a9009d0334cb6b1d06096`이다.

이 identity는 과거 조사 기록이다. 이번 조사에서 설치 binary를 읽거나 다시 hash하지 않았다. 따라서 현재 같은 bytes인지 확인하지 않았다. private metadata receipt의 현재 부재를 다른 HOME·key·환경 관측으로 채우지 않았다.

기존 원본 session에도 당시 metadata-read tool 결과가 남아 있다. 원본 경로는 `SESSION_RECORD`이다. 아래 hash는 지정한 raw JSONL 한 줄의 bytes로 계산했다. 마지막 LF를 포함한다. 전체 session 파일의 hash가 아니다.

| 원본 기록 위치 | 당시 시각 UTC | raw line 크기·SHA-256 | 보존한 결과의 의미 |
| --- | --- | --- | --- |
| `SESSION_RECORD:31538` | `2026-10-12T06:01:30.954Z` | `2512B`; `ce6d675cad4666d13f0b82c7a4c041179a1a1808a449c98069c90745a8ce6509` | 당시 private metadata receipt hash `c1eaeeae2bee9b93df35b0112040bb61d7690435639a9009d0334cb6b1d06096`를 기록한 tool 결과다. |
| `SESSION_RECORD:31546` | `2026-10-12T06:01:42.882Z` | `3316B`; `5c8c5e73471b5f0023756e914b4444f62e7ab7ae5b57ecb6589017b4822e1069` | 당시 selected ADB의 일반 파일·symlink 부재·ancestor alias 부재와 SHA-256 `1811e253…`를 기록한다. `sourceProperties`와 `packageXml`의 revision 및 embedded version 후보는 `37.0.1`이다. `installedSourceFullCorrespondence`는 `UNKNOWN`이다. |

두 줄의 JSON pointer `/payload/output/1/text`는 nested tool 결과 JSON 문자열이다. 그 문자열의 `/content/0/text`에 렌더링된 당시 결과가 있다. `/payload/output/0/text`는 호출 code다. 호출 code를 실행 결과나 AOSP source bytes로 사용하지 않는다. selected ADB 크기 `18844128B`는 위 ADR-0033 기록에 귀속한다. `:31546` 결과에는 그 크기가 없다. 이 session 결과는 역사 identity의 직접 기록이다. 원본 metadata receipt 전체 bytes나 AOSP source bytes를 복원한 결과가 아니다.

| 대응 단계 | 이번 판정 | 근거와 남은 공백 |
| --- | --- | --- |
| 보존 SDK catalog → revision·macOS archive 선언 | 확인 | 기존 XML bytes와 항목을 확인했다. |
| 보존 설치 목록 → historical installed revision | 확인 | 기존 목록은 `37.0.1`을 기록한다. |
| archive 선언 → 보존 ZIP bytes | `UNKNOWN` | 확인한 위치에서 해당 ZIP을 찾지 못했다. |
| archive payload `adb` → historical installed hash | `UNKNOWN` | archive payload를 대조할 근거가 없다. |
| AOSP pin → 보존된 source bytes·완전한 build 입력 | `UNKNOWN` | pin·hash 기록은 남았다. source bytes·build manifest·toolchain·dependency 대응은 입증하지 못했다. |
| full source/build → historical installed ADB | `UNKNOWN` | release/revision 문자열은 전체 build 대응을 증명하지 않는다. |
| historical installed ADB → 현재 binary identity | 미조회 | 현재 설치 파일을 읽지 않았다. |

## 조사 범위와 다음 검토

증거 root의 metadata·log·문서 이름을 depth 2까지 조사했다. 파일 content 검색은 `.json`·`.md`·`.txt`·`.log` 중 `300000B` 미만인 1682개에 한정했다. 검색어는 AOSP pin·historical installed hash·기존 source-index 경로·macOS ZIP 이름·archive SHA-1·private metadata receipt hash를 포함했다. `node_modules`·`Pods`·`vendor`·`.git`·`build`·`DerivedData`와 clone·baseline·fresh 하위 tree는 제외했다. XML은 정확한 기존 파일 한 개의 `platform-tools` 항목만 parse했다.

확인한 archive 이름은 RN·Hermes·앱 archive였다. 이 archive를 SDK ADB provenance로 사용하지 않았다. SDK 설치 tree·cache·HOME·전체 volume을 검색하지 않았다. 이 제한 때문에 검색 결과를 전체 host의 부재로 확장하지 않는다.

기존 session의 위 두 metadata-read 결과를 정확한 위치에서 확인했다. key bytes나 환경값 원문을 출력하지 않았다. 이 기록 확인은 실제 환경 수집이 아니다.

다음 검토는 source bytes의 보존 공백과 설치 build 대응 공백을 처리할 읽기 정책 범위다. 필요한 근거는 고정한 source bytes와 hash, 공식 release archive payload와 checksum, payload ADB와 historical installed hash의 대응, release의 source/build manifest 연결이다. 이 근거가 없으면 `UNKNOWN STOP`을 유지한다. network 재수집·source 복원·현재 SDK 읽기·실제 준비는 이 조사 범위가 아니다. 해당 근거를 수집할 대상·경로·방법은 별도 검토와 결정이 필요하다. 새 읽기 권한을 자동으로 도출하지 않는다.

## 읽기 검증 범위 — 첫 단계 확정

사용자는 2026-10-12에 Q1의 첫 단계 범위를 확정했다. 아래 고정 URL의 HTTPS 메모리 읽기와 hash 대조 및 결과 metadata 문서 저장을 허용했다. 이 허용은 실제 환경·resource·시작이나 현재 SDK 읽기를 포함하지 않는다. 아래 URL은 이번 새 조회 대상이다. 과거 다운로드 origin을 입증한 값이 아니다. source/build manifest 조회는 다음 결정으로 남긴다.

### 첫 결정: 고정 source와 archive의 메모리 검증

1. AOSP source 7개를 commit `fb529d52f4485c1fdbe6208f20af6578493e1ca7`의 고정 URL에서 HTTPS GET으로 읽는다. 대상은 위 source 표의 일곱 파일이다. URL 형식은 `https://android.googlesource.com/platform/packages/modules/adb/+/fb529d52f4485c1fdbe6208f20af6578493e1ca7/<file>?format=TEXT`다. 응답은 메모리에서 엄격한 Base64 decode를 수행한다. encoded 응답은 파일별 2MiB 이하로 제한한다. decoded 크기는 파일별 1MiB 이하로 제한한다. decoded SHA-256을 위의 기존 기록과 대조한다. branch·latest·다른 pin으로 대체하지 않는다.
2. archive 후보는 `https://dl.google.com/android/repository/platform-tools_r37.0.1-darwin.zip` 한 개다. 이것은 새 조회 대상의 선언이다. 보존 catalog의 상대 URL로 과거 다운로드 origin을 인증하지 않는다. 응답 크기는 기록된 `16110554B`와 같아야 한다. SHA-1은 기록된 `6ae73f4de6452dc57e62ec02b68eed92a4c21661`과 같아야 한다. 새 SHA-256도 계산한다. checksum 불일치나 HTTP 오류를 다른 revision·mirror·새 catalog로 보정하지 않는다.
3. checksum이 일치한 ZIP의 중앙 directory와 `platform-tools/adb`를 메모리에서 검사한다. ZIP을 filesystem에 extract하지 않는다. `adb` member는 일반 파일 하나여야 한다. 중복 이름·암호화·symlink·손상·기록된 크기 `18844128B` 초과 또는 크기 불일치면 STOP한다. member SHA-256을 과거 설치 hash `1811e253b21b12cbfda7201ebaf86c10e7ddcb5c606a7a81f7c82b4c429c2d3b`와 대조한다. binary를 실행하지 않는다.

HTTPS GET은 토큰·쿠키를 전달하지 않는다. TLS 인증을 끄지 않는다. redirect와 추가 URL은 자동으로 따라가지 않는다. 응답을 읽는 동안 각 크기 상한을 적용한다. 상한 초과를 확인한 뒤 나머지 응답을 수집하지 않는다. 허용 URL과 메모리 상한 밖의 입력은 STOP한다. 응답 bytes를 설치·cache·HOME·`/tmp`·원본 packet에 저장하지 않는다. 결과 문서에는 대상 URL·시각·HTTP 상태·크기·hash·대조 판정만 기록한다. 기존 조사 문서의 이번 절과 결과 절을 저장하는 범위만 포함한다. 기존 정책과 합성 helper는 수정하지 않는다.

기존 [공식 metadata 조사 기록:18–19](https://github.com/minjunkim-dev/mobile-runtime/blob/bab865b6ad79559325dc460fd2b3a2117d8b304c/docs/research/cli-expansion-validation-candidates.md#L18)은 `https://dl.google.com/android/repository/repository2-3.xml`을 근거로 명시한다. 이 기록은 향후 archive URL의 host와 repository base를 선택한 근거다. 현재 보존 XML의 과거 download origin이나 archive bytes를 인증한 receipt는 아니다. 새 catalog 조회는 이번 첫 단계에 포함하지 않는다.

새 조회 결과는 새 근거다. 기존 source hash와 같으면 그 기록과 bytes가 일치한다고 판정한다. 과거 원본 파일의 보존·다운로드 origin·현재 설치 상태를 소급 인증하지 않는다. archive의 member hash가 과거 설치 hash와 같아도 전체 source/build 대응이나 현재 설치 bytes를 입증하지 않는다.

### 다음 결정: 공식 source/build 연결 근거

첫 단계의 고정 source와 archive 검증 뒤에도 full source/build 대응은 별도다. 정확한 release 또는 build 식별자와 공식 manifest 대상 URL을 근거로 고정한 뒤 조회 범위를 결정한다. 필요한 연결은 해당 release의 build identity와 source commit·dependency·toolchain·build 입력이다. 같은 revision 문자열·파일 이름·부분 source hash를 full source/build 대응으로 사용하지 않는다. 현재는 manifest URL·build 입력·toolchain·dependency 연결이 미확정이다. 이 초안은 임의 release 검색·전체 source tree 수집·build·추가 URL 조회를 허용하지 않는다.

### 계속 제외하는 범위와 판정

현재 설치 SDK binary·metadata·HOME·key·환경을 읽지 않는다. Simulator·Emulator·GUI·ADB process·device·socket·port를 조회하거나 시작하지 않는다. 원본 `adb` client를 호출하지 않는다. network install·source 복원·key write·runtime 조건 적용·lease·baseline 실행을 포함하지 않는다. 오류·필수 누락·불일치·UNKNOWN은 해당 단계의 STOP이다. 첫 단계의 source 또는 archive 대조 PASS를 실제 readiness·compatibility·권한으로 사용하지 않는다. historical UNKNOWN과 #212의 실제 미완료를 유지한다.

첫 단계의 새 HTTPS 메모리 읽기 범위는 확정했다. source/build manifest 조회의 다음 결정은 첫 단계의 결과를 받은 뒤 질문한다. 이 확정은 실제 준비 권한을 부여하지 않는다.

## Q1 읽기 검증 결과 — PASS

사용자가 확정한 고정 URL 8개를 새로 읽었다. 검증은 `2026-10-12T08:43:18.838104+00:00`부터 `2026-10-12T08:43:20.348098+00:00` 사이의 HTTPS 응답에 귀속한다. 시각은 UTC다. 아래 결과는 새 조회 metadata다. 기존 기록 조사의 판정을 소급 변경하지 않는다.

수신 상한·엄격한 Base64 decode·일반 ZIP member 검사에는 먼저 합성 메모리 self-check 6개를 적용했다. 정상 입력과 수신 상한 초과·잘못된 Base64·symlink 거부를 확인했다. 응답은 토큰·쿠키·proxy·redirect 없이 HTTPS에서 읽었다. 실제 SDK·HOME·key·환경·resource를 수집하지 않았다. raw 응답과 decoded source 및 archive member는 메모리에서 처리했다. filesystem extract·raw 파일 저장·binary 실행은 하지 않았다.

| source URL | 요청 → 수신 완료 UTC | encoded / decoded bytes | 새 decoded SHA-256 | 판정 |
| --- | --- | --- | --- | --- |
| [client/commandline.cpp](https://android.googlesource.com/platform/packages/modules/adb/+/fb529d52f4485c1fdbe6208f20af6578493e1ca7/client/commandline.cpp?format=TEXT) | `2026-10-12T08:43:18.838104+00:00` → `2026-10-12T08:43:19.600699+00:00` | `108776` / `81582` | `a3da993989356e95f864744833bf309c2175d7a7e5110bf5d2c7e36e521ae349` | HTTP `200` · `PASS` |
| [client/main.cpp](https://android.googlesource.com/platform/packages/modules/adb/+/fb529d52f4485c1fdbe6208f20af6578493e1ca7/client/main.cpp?format=TEXT) | `2026-10-12T08:43:18.841039+00:00` → `2026-10-12T08:43:19.479431+00:00` | `11956` / `8965` | `8ffbd78cce04df0d5d1a1fc358ce99a59c63f4dec8224d1d3090c14a240a7a1d` | HTTP `200` · `PASS` |
| [client/adb_client.cpp](https://android.googlesource.com/platform/packages/modules/adb/+/fb529d52f4485c1fdbe6208f20af6578493e1ca7/client/adb_client.cpp?format=TEXT) | `2026-10-12T08:43:18.843879+00:00` → `2026-10-12T08:43:19.382942+00:00` | `19456` / `14590` | `9f1f14d7bbad7ebb7ccbc5c92f917f0a737f37ac42c41d2c5e9ac76438ee1d7c` | HTTP `200` · `PASS` |
| [client/auth.cpp](https://android.googlesource.com/platform/packages/modules/adb/+/fb529d52f4485c1fdbe6208f20af6578493e1ca7/client/auth.cpp?format=TEXT) | `2026-10-12T08:43:18.844135+00:00` → `2026-10-12T08:43:19.519736+00:00` | `22804` / `17101` | `aba13cf80b3db2998962127d687a09225cd831d3760dd55d0876b9ed5bf0ea75` | HTTP `200` · `PASS` |
| [adb_utils.cpp](https://android.googlesource.com/platform/packages/modules/adb/+/fb529d52f4485c1fdbe6208f20af6578493e1ca7/adb_utils.cpp?format=TEXT) | `2026-10-12T08:43:18.849210+00:00` → `2026-10-12T08:43:19.373729+00:00` | `14696` / `11020` | `747a7ceff6eedcc62b8ee9c6f962028d560f7abc4473135a032afb5c479d71a0` | HTTP `200` · `PASS` |
| [client/adb_wifi.cpp](https://android.googlesource.com/platform/packages/modules/adb/+/fb529d52f4485c1fdbe6208f20af6578493e1ca7/client/adb_wifi.cpp?format=TEXT) | `2026-10-12T08:43:18.851667+00:00` → `2026-10-12T08:43:19.347830+00:00` | `11740` / `8804` | `3d57dcdd3e0cd5dba9c66fb42dd962bf1bfcf48d9ad0599cbad720789da0ba4d` | HTTP `200` · `PASS` |
| [adb.h](https://android.googlesource.com/platform/packages/modules/adb/+/fb529d52f4485c1fdbe6208f20af6578493e1ca7/adb.h?format=TEXT) | `2026-10-12T08:43:18.852065+00:00` → `2026-10-12T08:43:19.478055+00:00` | `11364` / `8523` | `448530595669e914264f314765c9d839dbc82c29e8f1e9a23b21738f23d4606a` | HTTP `200` · `PASS` |

일곱 source의 새 SHA-256이 위의 기존 기록과 모두 일치한다. 이 결과는 고정 pin의 해당 일곱 파일에 한정한다. 전체 source tree나 build 입력의 검증이 아니다.

| archive metadata | 새 조회 결과 |
| --- | --- |
| 대상 | [Platform-Tools 37.0.1 macOS ZIP](https://dl.google.com/android/repository/platform-tools_r37.0.1-darwin.zip) |
| 요청 → 수신 완료 UTC | `2026-10-12T08:43:18.856681+00:00` → `2026-10-12T08:43:20.348098+00:00` |
| HTTP 상태·크기 | `200` · `16110554B` |
| SHA-1 | `6ae73f4de6452dc57e62ec02b68eed92a4c21661` |
| SHA-256 | `ee39ad5967e95c2a07f04dbcbde96b1a0c916ba376096db5d2f498b7727a5d1d` |
| 크기·기존 catalog SHA-1 대조 | `PASS` |
| archive member | `platform-tools/adb` |
| member 크기·SHA-256 | `18844128B` · `1811e253b21b12cbfda7201ebaf86c10e7ddcb5c606a7a81f7c82b4c429c2d3b` |
| 과거 설치 ADB hash 대조 | `PASS` |

같은 hash는 archive payload와 과거 기록된 설치 ADB bytes의 대응 근거다. 현재 설치 binary를 새로 확인한 결과는 아니다. 원본 설치 과정이나 과거 다운로드 origin을 인증하지 않는다.

첫 단계의 source 7개·archive·member 대조는 모두 `PASS`다. full source/build 대응은 `UNKNOWN`이다. 현재 설치 identity는 `미조회`다. 실제 compatibility·readiness·권한·lease는 부여하지 않는다. #212의 실제 검증은 계속 미완료다. build manifest는 조회하지 않았다. 그 조회에는 정확한 build 식별자와 공식 대상 URL을 고정하는 다음 결정이 필요하다.

## Q2 공개 build 식별자 읽기 — 범위 확정

기존 session:31538·31546의 실제 metadata-read 결과에는 정확한 build ID나 공식 manifest URL이 없다. `sdkRevision`과 `embeddedVersionCandidates`는 `37.0.1`만 기록한다. 조회할 manifest URL을 아직 고정할 수 없다. 다음 결정은 manifest 조회 전의 공개 식별자 확인으로 한정한다.

사용자는 2026-10-12에 Q2 범위를 확정했다. 같은 고정 ZIP URL을 한 번 새로 읽는다. Q1과 같은 수신 크기·SHA-1·SHA-256과 일반 `adb` member 크기·SHA-256을 먼저 감사한다. Q1의 source 7개는 다시 읽지 않는다. archive bytes를 저장하거나 extract하지 않는다.

checksum이 일치하면 `platform-tools/source.properties` 한 member의 공개 `Pkg.Revision` 값만 메모리에서 읽는다. member는 중복·암호화·symlink가 없는 일반 파일 하나여야 한다. decoded 크기는 16KiB 이하로 제한한다. member 부재·잘못된 UTF-8·중복 필드·revision 불일치는 STOP이다. 다른 archive member로 자동 확대하지 않는다.

Q1과 같은 hash가 확인된 archive의 `platform-tools/adb` bytes에서 `37.0.1`을 포함한 정적 ASCII version 문자열 후보를 찾는다. binary를 실행하거나 전체 strings dump를 만들지 않는다. 후보 한 개는 128 ASCII 문자 이하이며 후보 수는 32개 이하로 제한한다. bound 초과나 정확한 build 식별자 미입증이면 UNKNOWN STOP이다. 발견한 문자열은 공개 식별자 후보 metadata로만 기록한다. 문자열 존재를 공식 build manifest나 full source/build 대응 증거로 사용하지 않는다.

허용한 두 member의 크기·hash·공개 revision·식별자 후보·추출 판정과 HTTPS 결과 metadata만 같은 조사 문서에 저장한다. 전체 member text·raw binary·원본 environment·key를 저장하지 않는다. 현재 SDK 읽기·설치·binary 실행·실제 환경 수집·resource 조회·시작은 계속 제외한다. manifest와 추가 URL을 조회하지 않는다. build 식별자가 확인된 뒤에도 공식 manifest 대상 URL과 그 읽기 범위는 별도 결정이다. Q2 확정은 이 한정된 읽기 권한만 부여한다.

## Q2 읽기 결과 — 정확한 build 식별자 UNKNOWN STOP

2026-10-12에 승인한 ZIP URL을 HTTPS로 한 번 읽었다. 요청 시각은 `2026-10-12T08:52:50.088562+00:00`이다. 완료 시각은 `2026-10-12T08:52:52.184992+00:00`이다. 응답은 HTTP `200`이다. URL은 `https://dl.google.com/android/repository/platform-tools_r37.0.1-darwin.zip`이다. redirect나 추가 URL을 사용하지 않았다.

| 검사 대상 | 크기 | hash / 공개 값 | 판정 |
| --- | ---: | --- | --- |
| ZIP | 16110554 B | SHA-1 `6ae73f4de6452dc57e62ec02b68eed92a4c21661` | Q1 기준과 일치 |
| ZIP | 16110554 B | SHA-256 `ee39ad5967e95c2a07f04dbcbde96b1a0c916ba376096db5d2f498b7727a5d1d` | Q1 기준과 일치 |
| `platform-tools/adb` | 18844128 B | SHA-256 `1811e253b21b12cbfda7201ebaf86c10e7ddcb5c606a7a81f7c82b4c429c2d3b` | Q1 및 과거 설치 hash와 일치 |
| `platform-tools/source.properties` | 38 B | SHA-256 `2dccd788c0234d8cf7f7457377e57f57527a86a629c6ed54feb8af0f549dac38` | 한정 member 읽기 PASS |
| 공개 `Pkg.Revision` | — | `37.0.1` | 선언 revision과 일치 |

수신 크기와 checksum을 먼저 확인했다. 두 member의 일반 파일 조건을 확인했다. 그 뒤 메모리에서 공개 revision과 승인한 정적 ASCII 후보를 검사했다. 수신 상한·revision 파싱·후보 상한·symlink 거부를 포함한 메모리 self-check 8개가 PASS다.

정적 version 후보는 `["37.0.1"]`이다. 승인한 추출 범위에서 숫자 build ID 후보는 `[]`이다. 정확한 공식 build 식별자를 입증하지 못했다. 이 결과는 archive 전체에 다른 식별자가 없다는 증거가 아니다.

archive identity·adb identity·한정 literal 읽기는 PASS다. 필수 식별자 판정은 `UNKNOWN_STOP`이다. Q2 종합 판정은 `CANDIDATE_ONLY_UNKNOWN_STOP`이다. 공식 build identity·공식 manifest URL·full source/build 대응은 계속 `UNKNOWN`이다. 공개 revision이나 hash 일치를 full source/build 대응 증거로 사용하지 않는다.

raw ZIP과 두 member bytes는 파일로 저장하지 않았다. bytes는 메모리 검사 프로세스가 끝날 때 폐기했다. binary를 실행하지 않았다. Q1 source 7개를 다시 읽지 않았다. 현재 SDK·HOME·key를 읽지 않았다. 실제 환경 수집·resource 조회·시작을 수행하지 않았다. manifest와 추가 URL을 조회하지 않았다. 새 응답을 과거 보존 상태나 현재 설치 상태의 증거로 사용하지 않는다.

이번 읽기는 승인한 범위에서 종료했다. 실제 준비 권한과 실제 준비 완료 판정은 계속 `false`다. 실제 lease는 없다. #212의 실제 실행은 미완료다. 다음 검토 대상은 공식 release/build 근거의 조회 대상과 증거 기준이다. 구체적인 URL과 읽기 범위를 별도로 확정하기 전에는 추가 조회를 수행하지 않는다. ADR-0033의 full source/build 대응 요구를 자동으로 완화하지 않는다.

## Q3 공식 release notes 읽기 — 범위 확정과 결과

사용자는 2026-10-13에 `https://developer.android.com/tools/releases/platform-tools` 한 페이지의 단일 HTTPS GET 범위를 확정했다. 기존 기록에 조회 결과가 없던 신규 대상이다. 확정 뒤 identity encoding을 요청했다. redirect와 재시도 없이 한 번만 읽었다. 수신 상한은 2MiB다. 연결·읽기 timeout은 15초다. 총 수신 상한은 30초다. HTML은 메모리에서만 파싱했다. script·assets·링크를 실행하거나 조회하지 않았다.

추출 범위는 revision `37.0.1`의 공개 날짜·명시적 source/build 식별자·관련 링크 후보다. 관련 텍스트 상한은 32KiB다. 링크 상한은 16개다. 각 URL 상한은 2048자다. HTTP 오류·redirect·상한 초과·필수 식별자 미입증은 UNKNOWN STOP이다. 후속 URL 조회는 포함하지 않았다.

| metadata | 결과 |
| --- | --- |
| 요청 URL | [Platform-Tools release notes](https://developer.android.com/tools/releases/platform-tools) |
| 요청 시각 UTC | `2026-10-13T02:36:17.304882+00:00` |
| 수신 완료 시각 UTC | `2026-10-13T02:36:18.291666+00:00` |
| 검사 완료 시각 UTC | `2026-10-13T02:36:18.330284+00:00` |
| 요청 횟수·HTTP 상태 | `1` · `200` |
| 응답 크기 | `357601B` |
| 응답 SHA-256 | `b8eca5ab9c21c3e142e50cf81dfda2ec093ebba3fbe11e6768a6cffc1fdc27d4` |
| revision | `37.0.1` |
| 공개 날짜 후보 | `["July 2026"]` |
| 추출 section 텍스트 크기 | `886B` |
| source commit 후보 | `[]` |
| 명시적 build 식별자 후보 | `[]` |
| 링크 후보 | `[]` |
| 메모리 self-check | `8`개 PASS |
| 한정 읽기 판정 | `PASS` |
| Q3 종합 판정 | `LOCATOR_CANDIDATE_ONLY_UNKNOWN_STOP` |
| 공식 build identity·공식 manifest URL·full source/build 대응 | 모두 `UNKNOWN` |

수신 상한·revision section 선택·텍스트와 링크 상한 및 script 제외를 합성 메모리 self-check로 확인했다. 후보 0건은 수신한 페이지의 해당 section과 승인한 추출 범위에만 귀속한다. 페이지 전체나 다른 공식 자료에 식별자가 없다는 증거가 아니다. version과 공개 날짜를 공식 build identity나 전체 source/build 대응의 PASS 근거로 사용하지 않는다. 응답 SHA-256은 그 시각의 새 응답 identity다. 과거 다운로드 origin이나 현재 설치 상태를 인증하지 않는다.

Q3 읽기 당시 `rawBytesPersisted=false`와 `documentWritten=false`였다. raw HTML과 추출 원문은 저장하지 않았다. 메모리 검사 프로세스 종료 뒤 원문을 보존하지 않았다. binary 실행·현재 SDK·HOME·key 읽기·실제 환경 수집·resource 조회·시작·추가 URL 조회는 수행하지 않았다. 실제 준비 권한과 readiness는 `false`다. 실제 lease는 없다.

사용자는 Q4의 증거 기준과 Q5의 미입증 시 중단 경로를 확정했다. 이 두 결정은 [ADR-0033](../adr/0033-rn-gui-adb-resource-preparation.md)의 `full source/build 증거 기준과 중단 경로` 절에 저장한다. 사용자는 이어서 기존 정책 문서와 이 조사 문서의 파일 저장을 허용했다. 이번 저장은 앞서 대화에 표시한 Q3 결과 metadata의 기록이다. Q3 당시의 문서 미저장 사실을 바꾸지 않는다. 응답을 다시 조회하거나 raw bytes를 복원하지 않았다. 추가 URL·실제 환경·resource 조회·시작 권한은 부여하지 않는다. full source/build 대응은 UNKNOWN STOP이며 #212는 계속 미완료다.

## 고정 ZIP member 목록 읽기 — 범위 확정과 결과

사용자는 2026-10-13에 PR #257 병합 뒤의 다음 읽기 범위와 STOP 기준을 추천대로 확정했다. 정확한 대상은 `https://dl.google.com/android/repository/platform-tools_r37.0.1-darwin.zip`다. HTTPS GET 1회만 허용했다. redirect·재시도·후속 URL 조회는 제외했다. identity encoding을 요청했다. 원문 ZIP은 메모리에서만 처리했다. 기존 Q1도 중앙 directory를 검사했다. 이번 새 목적은 전체 member 이름에서 build 근거의 위치 후보를 찾는 것이다. 기존 Q1을 중앙 directory 미조회로 바꾸지 않는다.

연결·읽기 timeout은 각각 15초다. 전체 상한은 30초다. 수신 상한은 `16110554B`다. 중앙 directory는 64KiB 이하, entry는 128개 이하, 이름은 각각 512B 이하, 추출 metadata는 64KiB 이하로 제한했다. HTTP 오류·redirect·불완전 수신·timeout·상한 초과·해석 불가·중복 또는 안전하지 않은 entry는 UNKNOWN STOP이다. 후보 부재·모호함도 UNKNOWN STOP이다. 완전히 수신한 산출물이 기존 크기·SHA-1·SHA-256과 다르면 실패 STOP이다. 같은 대상에 귀속한 직접 근거의 모순도 실패 STOP이다. 어느 STOP에서도 조회를 자동 확대하지 않는다.

| metadata | 결과 |
| --- | --- |
| 요청 시작 UTC | `2026-10-13T06:31:45.943703+00:00` |
| 수신 완료 UTC | `2026-10-13T06:31:48.412743+00:00` |
| 검사 완료 UTC | `2026-10-13T06:31:48.438797+00:00` |
| 요청 횟수·HTTP 상태 | `1` · `200` |
| archive 크기 | `16110554B` |
| archive SHA-1 | `6ae73f4de6452dc57e62ec02b68eed92a4c21661` |
| archive SHA-256 | `ee39ad5967e95c2a07f04dbcbde96b1a0c916ba376096db5d2f498b7727a5d1d` |
| archive identity 판정 | `PASS` — 기존 Q1·Q2와 일치 |
| 중앙 directory 크기·entry 수 | `1153B` · `14` |
| 한정 목록 검사 판정 | `PASS` |
| build locator 이름 후보 | `[]` |
| 일반 metadata 이름 후보 | `platform-tools/source.properties`, `platform-tools/NOTICE.txt` |
| 읽기 전 합성 메모리 검사 | `10`개 PASS |
| 경과 시간 | `2.495`초 |
| 종합 판정 | `LOCATOR_CANDIDATE_ONLY_UNKNOWN_STOP` |

중앙 directory에 선언된 member 이름·형식·크기는 다음과 같다. 아래 크기는 member 내용에서 측정한 값이 아니다. 압축 해제와 member 내용 검사는 수행하지 않았다.

| member | 형식 | 선언 압축 크기 B | 선언 비압축 크기 B |
| --- | --- | ---: | ---: |
| `platform-tools/` | DIRECTORY | 0 | 0 |
| `platform-tools/mke2fs` | FILE | 796313 | 1815872 |
| `platform-tools/lib64/` | DIRECTORY | 0 | 0 |
| `platform-tools/lib64/libc++.dylib` | FILE | 903319 | 2662912 |
| `platform-tools/make_f2fs_casefold` | FILE | 247016 | 595376 |
| `platform-tools/source.properties` | FILE | 39 | 38 |
| `platform-tools/mke2fs.conf` | FILE | 380 | 1157 |
| `platform-tools/adb` | FILE | 8087530 | 18844128 |
| `platform-tools/etc1tool` | FILE | 316911 | 669952 |
| `platform-tools/fastboot` | FILE | 2198377 | 5736048 |
| `platform-tools/make_f2fs` | FILE | 247015 | 595360 |
| `platform-tools/sqlite3` | FILE | 3032907 | 6606368 |
| `platform-tools/hprof-conv` | FILE | 19033 | 134624 |
| `platform-tools/NOTICE.txt` | FILE | 259362 | 1152421 |

build locator 이름 후보는 basename에 `build`·`manifest`·`provenance`·`revision`·`version`을 포함하는 파일을 대소문자 구분 없이 찾은 결과다. 후보 0건은 이 이름 규칙과 이번 목록 범위에만 귀속한다. 다른 member 내용이나 다른 공식 자료에 build 근거가 없다는 증거가 아니다. 일반 metadata 후보 두 개도 build identity나 공식 연결의 입증 근거가 아니다. `source.properties`의 revision-only 결과는 기존 Q2에 있다. 이번에 그 내용을 다시 읽지 않았다. `NOTICE.txt`의 내용도 읽지 않았다.

원문 ZIP은 파일로 저장하지 않았다. 메모리 검사 프로세스가 끝나면 원문을 폐기했다. 이번 문서 저장은 결과 metadata의 기록이다. member 내용·고정 source 7개·release notes·manifest·후속 URL·현재 SDK·HOME·key·실제 환경·resource를 조회하지 않았다. binary 실행·extract·설치·실제 준비를 수행하지 않았다. MODEL-ONLY helper를 실제 응답의 입증 도구로 사용하지 않았다. 공식 build identity와 full source/build 대응은 UNKNOWN STOP이다. 실제 권한·readiness는 false이며 lease는 없다. #212와 PR #236의 상태를 변경하지 않았다.

이번 승인 범위에서 읽기를 종료했다. member 내용이나 다른 공식 자료로 확대하려면 정확한 대상과 읽기 범위를 새로 확정해야 한다. 이 결과로 실제 준비 권한을 도출하지 않는다.

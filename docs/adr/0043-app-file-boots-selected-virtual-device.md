# ADR-0043: 앱 파일 경로는 사용자가 고른 꺼진 Simulator·AVD를 승인 뒤 부팅한다

- 상태: 채택
- 날짜: 2026-10-22
- 관련: #189, #218, #199, ADR-0007, ADR-0013, ADR-0041

## 배경

#189 결정의 직접 설치 구현(#218)은 준비·부팅한 가상 기기만 받았다.
종료된 Simulator와 실행하지 않은 AVD는 "수동 준비 필요"였다.
사용자는 원하는 Simulator·Emulator를 골라 시험할 수 있어야 한다. 프로젝트 `up`은 이미 선택한 기기를 부팅한다.
사용자 결정: 앱 파일 경로에서도 고른 꺼진 Simulator·AVD를 Runstir가 부팅한다. 기존 `up`의 부팅·소유권 계약을 재사용한다.

## 결정

이 ADR은 [앱 파일 직접 설치](../app-file-direct-install.md)의 "가상 기기는 먼저 부팅하고 준비한다"만 대체한다.
#189의 승인·파일 식별·교체·데이터 보존·충돌·결과 계약은 그대로다.

1. 후보에 부팅 가능한 꺼진 가상 기기를 넣는다. `boot: required`로 표시한다.
   - iOS: `simctl`이 `Shutdown`·사용 가능으로 보고하고 runtime capability를 읽을 수 있는 Simulator.
   - Android: `emulator -list-avds`의 AVD 중 실행 중인 Emulator가 없고 `config.ini`·system image·API·ABI가 있는 것.
     실행 중인 Emulator의 AVD 이름을 하나라도 읽지 못하면 부팅 후보를 내지 않는다.
   - 그 밖의 상태(`Booting`, runtime·image 없음)는 수동 준비 필요다. runtime·AVD 생성, image 다운로드는 하지 않는다. 그 준비는 ADR-0041의 별도 승인 흐름이다.
2. 계획은 부팅을 승인 대상에 넣는다. 기존 앱은 `unobserved`다. 꺼진 기기에서는 설치 상태를 읽을 수 없기 때문이다.
   `BOOT:` 경고로 부팅·계속 실행·부팅 뒤 재관측을 알린다. `--plan`·`inspect`·승인 없는 실행은 부팅하지 않는다.
3. 승인 뒤 기기 lease를 잡고 파일 사본·기기 상태를 다시 확인한다. 같은 계획이면 그 기기만 부팅한다.
   - iOS: `up`의 `simctl bootstatus <UDID> -b`를 같은 함수로 호출한다. headless이며 Simulator.app을 열지 않는다.
   - Android: `up`과 같은 `emulator -avd <name>`을 분리 실행한다. 준비 판정(`sys.boot_completed`, API, ABI, `pm path android`)은 `up`과 같은 함수다. 대기 한도도 `up`의 300초다.
4. 부팅 뒤 기기 이름·OS·runtime identity와 호환성을 다시 확인한다. 기존 앱이 없을 때만 승인한 새 설치를 계속한다.
   앱이 있거나 확인 불가면 설치하지 않는다. 부팅한 기기로 새 교체 계획을 만들고 다시 승인받는다.
5. 결과의 `deviceBoot`에 Runstir가 시작한 기기를 기록한다. 상태는 `requested`·`started`·`unconfirmed`다.
   iOS는 UDID, Android는 관측한 serial·launcher PID·Emulator log 경로를 남긴다.
6. 이미 실행 중인 기기는 부팅하지 않고 그대로 쓴다. 다른 기기를 부팅·전환·종료하지 않는다.

## 종료

Runstir가 부팅한 기기는 계속 실행 상태로 둔다. 앱 파일 경로는 나중에 그 기기를 종료하지 않는다.

- iOS는 ADR-0007과 같다. `up`이 부팅한 Simulator도 `down`의 대상이 아니다.
- Android의 `down`은 프로젝트 active run에 기록한 Emulator만 끈다(ADR-0013). 앱 파일 작업에는 프로젝트 active run이 없다. 새 종료 명령을 추가하지 않는다.
- 창 닫기·GUI 종료·실패·취소도 기기를 끄지 않는다. 기존 앱 파일 계약과 같다.
- 사용자는 필요할 때 직접 종료한다. 결과는 Runstir가 시작했다는 사실과 handle을 보여 준다.

## 실패와 취소

부팅 요청 뒤 실패·취소하면 `deviceBoot`를 `unconfirmed`로 바꾼다. 취소를 물려받지 않는 별도 작업으로 기기 상태를 다시 관측한다.
기기를 끄거나 지우지 않는다. 설치를 시작하지 않는다. 다음 실행은 현재 상태로 새 계획을 만든다.
설치 요청 뒤의 재관측은 기존 계약과 같다.

## 결과

- 부팅은 기존 기기 lease 안에서 한다. 같은 기기를 고른 `up`과 다른 파일 작업은 그동안 그 기기를 쓰지 못한다.
- 부팅한 기기는 계속 실행되므로 호스트 자원을 쓴다. 이는 `up`과 같은 대가다.
- fixture는 승인·부팅 순서·재관측·금지 명령만 확인한다. 실제 부팅·설치·실행은 실제 검증이 따로 확인한다.

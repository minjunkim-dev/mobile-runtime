# Runstir 검사·패키징 영역 리뷰

- 외부 입력은 안전한 argv·env로 전달한다. 경로 탈출·덮어쓰기·삭제·취소·timeout의 실패 처리를 보존한다.
- 호출자가 사용하는 interface를 실행한다. source-only·mock·ZIP 목록은 해당 범위의 근거로만 보고한다.
- source SHA·manifest·archive checksum·target을 대조한다. 일부 성공이 UNKNOWN_STOP 또는 FAILURE_STOP을 지우지 않는다.
- CI 실패를 검사 삭제·skip·완화로 숨기지 않는다. 공개 배포·유료 실행·계정 변경을 시작하지 않는다.

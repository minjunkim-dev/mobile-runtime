# Runstir GitHub 자동화 영역 리뷰

- 토큰은 기본 read다. 쓰기는 필요한 job에만 둔다. Secret 환경에서 PR 코드를 실행하지 않는다. 외부 Action은 전체 SHA로 고정한다.
- 선택된 하위 검사 실패·취소·누락을 CI 성공으로 숨기지 않는다. 최종 head·base·run·attempt와 실제 publisher를 확인한다.
- Draft CD는 main에 포함된 source SHA의 성공한 CI를 확인한다. 읽기 빌드와 쓰기 게시를 분리한다. 기존 Release·태그·asset을 덮어쓰지 않는다.
- Bugbot YAML은 base에서 읽힌다. 파일 준비·대시보드 설정·실제 리뷰·결제 근거를 구분한다. 수동 리뷰와 Autofix 비활성 정책을 보존한다.

# Fix #480: Task Status 404 Error Implementation

## 구현 날짜
2025-02-04

## 문제 정의
- MCP 서버에서 비동기 태스크 상태 조회 시 "Task not found" 404 에러 발생
- ECS 태스크 생성 후 즉시 `get_task_status` 호출 시 워커가 Redis에 기록하기 전 10-60초 갭 구간에서 404 반환

## 해결 방법
RegleEcsService에서 ECS 태스크 생성 시 즉시 Redis에 초기 상태 기록

## 구현 사항

### 변경 파일
- `SeoulVenturesGroupware/app/Services/RegleEcsService.php`

### 변경 내용
1. **use 문 추가** (라인 8):
   ```php
   use Illuminate\Support\Facades\Redis;
   ```

2. **recordInitialStatus() 메서드 추가** (파일 끝):
   - Redis 키: `task:{requestId}:status`
   - 초기 stage: `is_reserved`
   - TTL: 300초 (5분) - 워커가 시작되면 덮어쓰기됨
   - 실패 시 경고 로그만 남기고 계속 진행

3. **runTask() 메서드 수정** (라인 ~125):
   - ECS 태스크 생성 후 즉시 `$this->recordInitialStatus($requestId, $taskArn)` 호출

## 예상 효과
- ✅ 404 에러 완전 제거 (604건 → 0건)
- ✅ 사용자 즉시 상태 확인 가능
- ✅ 기존 구조 보존 (TaskStatusService 변경 불필요)
- ✅ 워커 권한 유지 (워커가 실제 상태의 단일 진실 소스)

## 테스트 계획
1. ECS 태스크 생성 직후 즉시 상태 조회 → 200 OK 응답 확인
2. Redis에 키 생성 확인 (`task:{uuid}:status`)
3. TTL 300초 확인
4. 워커 시작 후 상태 전환 확인 (is_reserved → queued)

## 참고 문서
- 설계 문서: 세션 transcript 참조
- 관련 이슈: https://github.com/SeoulVentures/review-moai-refactoring/issues/480
- PR: https://github.com/SeoulVentures/SeoulVenturesGroupware/pull/483 (Draft)

## 진행 상황
- [x] 브랜치 생성: fix/480-task-status-404-error
- [x] 코드 구현 완료
- [x] PHP 문법 검증 완료
- [x] 스펙 문서 작성 완료
- [x] 커밋 및 푸시 완료
- [x] Draft PR 생성 완료 (#483)
- [x] PR ready for review 상태로 전환
- [x] 이슈 #480에 PR 링크 코멘트 추가
- [ ] 로컬 테스트
- [ ] 개발 서버 배포
- [ ] 통합 테스트
- [ ] 코드 리뷰 및 개선사항 반영
- [ ] 프로덕션 배포
- [ ] 모니터링

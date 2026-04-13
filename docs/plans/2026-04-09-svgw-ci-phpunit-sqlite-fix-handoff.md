# SVGW master CI 복구 — 세션 이관 프롬프트

**작성일**: 2026-04-09
**대상 저장소**: `SeoulVenturesGroupware`
**용도**: 이전 세션 컨텍스트가 너무 길어져 새 세션에서 이어서 진행하기 위한 핸드오프

> **✅ 완료 (2026-04-10 PR #544 머지)**: 이 문서의 원래 가설("phpunit.xml 의 `<server>` 가 env 를 덮어써서 sqlite 로 돌아간다")은 **틀렸다**. 실제 원인은 PR #542 가 retaku_admin DB 를 CI 에 추가하면서 `skipIfDatabaseUnavailable` 로 스킵되던 테스트 약 50건이 처음 실행되기 시작했고, 그 과정에서 잠재되어 있던 **11개 패턴 (A~K) 의 버그가 한꺼번에 드러난** 것.
>
> **최종 복구 결과**: [SeoulVentures/SeoulVenturesGroupware#544](https://github.com/SeoulVentures/SeoulVenturesGroupware/pull/544) 머지 완료 (squash 머지 커밋 `1713e2c4`).
> - CI: Failures 4→0, Errors 41→0, Assertions 277→479, Tests 235→237
> - 상세 스펙: `SeoulVenturesGroupware/docs/specs/svgw-ci-retaku-admin-tests-fix.md`
> - 후속 이슈: [SeoulVentures/SeoulVenturesGroupware#545](https://github.com/SeoulVentures/SeoulVenturesGroupware/issues/545) (ReviewClientService partial-update 버그)
>
> 이 문서의 Phase 2 방향(A~D 옵션)은 모두 잘못된 전제였음. **참고용**으로만 남겨둔다.

---

## 현재 상황

SVGW PR #541, #542, #543 연달아 머지됐지만 **master CI 여전히 failure**. 근본 원인이 방금 판명됨.

### 머지된 PR 체인
- **#541**: 매핑 삭제 감사 테이블 + UI 안전장치 (바닐라코 사고 재발 방지)
- **#542**: retaku_admin 레거시 9개 테이블 개별 마이그레이션 인수
- **#543**: TargetItemMapAuditGuardTest 격리 문제 수정 (Unit → Feature 이전)

## 방금 발견한 진짜 근본 원인

**`phpunit.xml` 기본값이 `DB_CONNECTION=sqlite` 이고 `DB_DATABASE=:memory:` 임.**

```xml
<server name="DB_CONNECTION" value="sqlite"/>
<server name="DB_DATABASE" value=":memory:"/>
```

`.github/workflows/deploy.yml` 의 `env:` 에 `DB_CONNECTION: mysql` 을 지정해도 **phpunit.xml 의 `<server>` 설정이 우선**해서 테스트가 sqlite :memory: 로 돌아감. 그래서:

- `User::factory()->create()` → sqlite 에서 `no such table: users`
- `HyperSpeedConfig::where(...)` → sqlite 에서 `no such table: hyper_speed_config`
- `Client::find(13)` → sqlite 에서 `no such table: review_clients`

이전에 의심한 "`TargetItemMapAuditGuardTest` 의 `config()` 오버라이드 오염"은 **오진**이었음. 원래부터 phpunit.xml 이 sqlite 를 강제하고 있었고, PR#541 이전부터 master CI 가 몇 주째 failing 이었던 진짜 이유가 이것일 가능성이 큼.

## 다음 세션에서 해야 할 일

### Phase 1 — 진짜 원인 확인
1. master 에서 `git log --oneline .github/workflows/deploy.yml` 로 deploy.yml 의 env 가 언제 추가됐는지 확인
2. `phpunit.xml` 의 git 히스토리 확인 — sqlite 기본값이 언제부터였는지
3. 이전 master CI failure 들(`#536`, `#533` 등)의 실패 원인이 정말 같은 건지 확인 (`gh run view <id> --log-failed`)

### Phase 2 — 수정 방향 결정
다음 중 하나를 선택:

- **(A) phpunit.xml 의 DB 설정을 mysql 로 변경** — deploy.yml env 와 일치. 로컬 개발자는 `.env.testing` 또는 개별 `phpunit.xml` override 로 sqlite 유지 가능
- **(B) deploy.yml 에 phpunit CLI 옵션으로 환경변수 주입**
- **(C) phpunit.xml 을 `.env.testing` 에서 읽도록 전환** — Laravel 권장 패턴. `.env.testing` 에 `DB_CONNECTION=mysql` + `DB_DATABASE=testing` 기록. phpunit.xml 의 `<server>` 태그는 제거
- **(D) RefreshDatabase + sqlite :memory:** 로 전체 통일 → User factory 등이 돌아갈 수 있게 Laravel 마이그레이션 + retaku_admin 마이그레이션이 함께 sqlite 에 돌도록 구성. 단 retaku_admin 마이그레이션은 sqlite 호환성 문제 가능 (json 컬럼, COMMENT 등)

## 참고할 메모리
- `/opt/SeoulVentures/.claude/projects/-opt-SeoulVentures-regle/memory/banila-mapping-restore-2026-04-08.md` — 전체 작업 기록, 커밋 해시, 핵심 교훈

## 주요 파일
- `/opt/SeoulVentures/regle/SeoulVenturesGroupware/phpunit.xml` — 원흉
- `/opt/SeoulVentures/regle/SeoulVenturesGroupware/.github/workflows/deploy.yml` — env 에 mysql 설정되어 있지만 phpunit.xml 이 덮음
- `/opt/SeoulVentures/regle/SeoulVenturesGroupware/tests/TestCase.php` — `canConnectToDatabase` / `skipIfDatabaseUnavailable` 헬퍼

## 주의사항
- 머지된 PR #541~#543 의 실질 기능(감사 테이블, UI 안전장치, 복원 커맨드, 레거시 마이그레이션)은 정상. **테스트 실행 환경 문제일 뿐**이라 운영 영향 없음
- 운영 배포는 자동 롤백으로 이전 버전 유지 중 (최근 배포 안 됨). phpunit 이슈 해결 후 정상 배포 재개
- CLAUDE.md 의 필수 작업 순서 18단계 준수
- 응답/사고 모두 한국어
- master 직접 push 금지 — 새 브랜치 + PR 로 진행

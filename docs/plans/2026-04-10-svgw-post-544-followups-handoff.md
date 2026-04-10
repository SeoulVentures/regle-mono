# SVGW PR #544 이후 후속 작업 3건 — 세션 이관

**작성일**: 2026-04-10
**완료일**: 2026-04-10 (3건 모두 머지)
**대상 저장소**: `SeoulVenturesGroupware`
**배경**: PR #544 (retaku_admin CI 복구 11개 패턴 일괄 해결) 및 PR #539 (frontend vite 7.3.2) 머지 후 남은 후속 작업

## 최종 결과

- ✅ **PR #549** (`18ec86f6`) — 작업 3 claude-code-review allowed_bots
- ✅ **PR #548** (`457ea8ba`) — 작업 2 루트 package.json 정리 + dependabot scope
- ✅ **PR #547** (`391f1891`) — 작업 1 ReviewClientService partial-update (#545 close)
- ✅ **이슈 #545** 자동 close
- ✅ **PR #546** (dependabot axios) — 루트 파일 삭제로 대상 소멸, 수동 close
- 📋 **후속 이슈 #550** — application-legacy 라우트/뷰/컨트롤러 전면 제거 (별도)

### 리뷰 진행 요약

- 1차 리뷰: code-reviewer / pr-test-analyzer / silent-failure-hunter (3개 에이전트 병렬) → Important 수정 + 테스트 3건 추가
- CI 수정: `$connectionsToTransact` 추가 (retaku_admin)
- 2차 리뷰: 동일 4개 에이전트 병렬 → I1 (빈 문자열) 오탐 원복 + cross-client scope 가드 추가
- Sentry AI 리뷰: PR #547 `review_service` null clear 반영 (선택지 A 로 전환) + PR #548 dependabot `bun` ecosystem 전환

---

## 공통 컨텍스트

작업 디렉토리: `/opt/SeoulVentures/regle`

먼저 세션 메모리를 읽어 컨텍스트를 파악한다:
- `/opt/SeoulVentures/.claude/projects/-opt-SeoulVentures-regle/memory/MEMORY.md`
- `/opt/SeoulVentures/.claude/projects/-opt-SeoulVentures-regle/memory/svgw-ci-retaku-admin-recovery.md`

CLAUDE.md 의 "필수 작업 순서 18단계" 를 각 작업마다 준수한다 (스펙 → 브랜치 → Draft PR → 구현 → 리뷰 → 머지).

**PR #544 가 머지한 새 CI 인프라 활용**: `deploy.yml` 에 `pull_request` 트리거가 추가되어 PR 에서도 test job 이 자동 실행된다 (`build/deploy/rollback/blue-green-management` 는 PR 에서 skip).

**응답/사고 모두 한국어**.

---

## 작업 1 (P0 — 운영 영향 가능) — 이슈 #545: ReviewClientService partial-update 버그

**이슈**: https://github.com/SeoulVentures/SeoulVenturesGroupware/issues/545

### 배경

`app/Services/Review/ReviewClientService.php` 의 `updateClient` 메서드 (line 140~173) 가 요청에 없는 필드를 `$data['field'] ?? null` 패턴으로 덮어쓴다. `UpdateStoreRequest` 의 validation 은 대부분 필드를 nullable 로 허용하므로 API 계약상 partial update 가 가능해 보이지만, Service 가 이를 깨뜨린다.

- 프론트 `frontend/resources/ts/pages/review/client/[id]/edit.vue` 는 항상 formData 전체를 전송하므로 운영 영향이 드러나지 않음
- **MCP / 외부 클라이언트가 부분 필드만 보내면**:
  - NOT NULL 컬럼 (`m_host` 등) → DB 에러 (즉각 인지)
  - nullable 컬럼 (`shop_id`, `product_url_pattern`, `product_scan_type`, `product_scan_selector` 등) → silent null-overwrite (데이터 손실)

### 수정 방향

1. `updateClient` 의 `$client->field = $data['field'] ?? null` 패턴을 `array_key_exists('field', $data)` 체크로 전환. 요청에 있는 필드만 setAttribute.
   ```php
   if (array_key_exists('m_host', $data)) {
       $client->m_host = $data['m_host'];
   }
   ```
2. `createClient` (line 109~135) 의 동일 패턴도 함께 검토 — 생성 시에는 null 기본값 의미가 다르므로 구분해서 처리
3. `Client::$fillable` 이 현재 `['scanned_review_count', 'collected_review_count', 'filtered_review_count']` 3개뿐이라 `fill()` 전환은 fillable 정비가 필요. 이번 이슈 범위에서는 `array_key_exists` 접근이 더 보수적.

### 회귀 anchor

`tests/Feature/Api/ReviewClientApiTest.php::test_클라이언트_부분_수정_시_기존_필드_보존` 가 이미 `markTestSkipped('후속 이슈 #545')` 로 존재. 이 이슈 처리 시:
1. `markTestSkipped` 호출 제거
2. 테스트가 통과하는지 확인
3. 같은 패턴의 추가 회귀 테스트가 필요한지 검토 (다른 nullable 필드 보존)

### 확인할 파일

- `app/Services/Review/ReviewClientService.php` (수정 대상)
- `app/Http/Requests/Api/Review/UpdateStoreRequest.php` (validation 규칙 참조)
- `app/Http/Requests/Api/Review/CreateStoreRequest.php`
- `tests/Feature/Api/ReviewClientApiTest.php` (anchor + 기존 테스트)
- `app/Models/Review/Client.php` (fillable 정책)

### Acceptance criteria

- [ ] `ReviewClientService::updateClient` 가 partial update 를 지원
- [ ] 회귀 anchor 테스트의 `markTestSkipped` 제거 후 통과
- [ ] 기존 `test_클라이언트_정보_수정` 도 여전히 통과
- [ ] CI 통과 확인
- [ ] 이슈 #545 클로즈

---

## 작업 2 (P1 — dependabot 노이즈 차단) — 루트 package.json legacy 정리

### 배경

루트 `package.json` 은 실제 사용되지 않는 legacy 파일이다 (2026-04-10 세션에서 분석):

- 루트에 `vite.config.*` 가 없어 `scripts.build: vite build` 는 실행 불가
- CI/배포 파이프라인 (`deploy.yml`) 은 `working-directory: ./frontend` 로 Bun 만 사용
- PR #527 (`f2b9fc21 chore: frontend-legacy 디렉토리 제거`) 에서 `frontend-legacy` 는 정리됐으나 루트 `package.json` 은 함께 정리되지 않음
- Dependabot 이 매번 무의미한 PR 을 생성 (최근: #540(닫힘), #536, #533, #532, #525, #524 등 모두 루트 package.json 관련)

PR #540 (vite 5→6) 은 이미 이 사유로 닫혔음. 이번 작업은 근본 정리.

### 수정 방향

1. **루트 `package.json`, `package-lock.json` 삭제** — 단, 삭제 전 다음을 grep 확인:
   - `resources/` 디렉토리 (Laravel Blade view / sass) 가 루트 package 의존성을 암묵적으로 사용하지 않는지
   - `husky` `prepare` 스크립트가 필요한지 (frontend/package.json 에 이미 husky 있음)
   - `laravel-vite-plugin`, `@vitejs/plugin-vue` 등 Laravel 표준 Vite 통합 의존성을 실제로 쓰는 곳이 있는지 (`composer.json` 또는 Laravel config)
2. **`.github/dependabot.yml`** 에서 루트 npm ecosystem 제외:
   - `package-ecosystem: "npm"` 의 `directory: "/"` 항목 삭제 또는 `directory: "/frontend"` 만 유지
3. `public/build/` 관련 legacy 확인 — 이미 `.gitignore` 에 추가됨 (2026-02-13)
4. 루트 `node_modules/` 가 있다면 정리 (이미 `.gitignore` 대상)
5. README 또는 CLAUDE.md 에 "frontend 는 `frontend/` 디렉토리에서 Bun 사용, 루트 package.json 없음" 명시

### 확인할 파일

- `package.json`, `package-lock.json` (루트)
- `.github/dependabot.yml`
- `composer.json` (Laravel Vite 통합 여부)
- `resources/views/*.blade.php` (Vite directive 사용 여부)
- `vite.config.*` (루트 어디에도 없어야 함)

### 주의사항

- 삭제 전 **로컬에서 `php artisan serve` + `cd frontend && bun run dev` 로 동작 확인**. 루트 package.json 제거가 Laravel + Vite HMR 을 깨뜨리지 않는지 검증.
- 운영 배포는 `frontend/` 의 `bun run build` 로 `public/build/` 생성 → Laravel 의 Vite facade 가 `public/build/manifest.json` 을 읽는 구조. 루트 package.json 과 무관.

### Acceptance criteria

- [ ] 루트 `package.json`, `package-lock.json` 삭제 (별도 설정에 의존하는 게 없다면)
- [ ] `.github/dependabot.yml` 에서 루트 npm 제외
- [ ] CI 통과 확인
- [ ] 로컬 `php artisan serve` + frontend dev 동작 확인
- [ ] 이후 dependabot PR 이 루트 package.json 관련으로는 열리지 않음

---

## 작업 3 (P2 — 리뷰 인프라 개선) — claude-code-action allowed_bots 설정

### 배경

2026-04-10 세션에서 PR #540 (dependabot) 의 `claude-review` check 가 FAILURE 였는데, 실제 에러 로그:

```
Workflow initiated by non-human actor: dependabot (type: Bot).
Add bot to allowed_bots list or use '*' to allow all bots.
```

즉 `claude-code-action` 이 dependabot PR 에서 bot 가드로 실행 거부. `allowed_bots` 설정 누락 → dependabot PR 에서 자동 코드 리뷰가 아예 돌지 않음.

### 수정 방향

1. `.github/workflows/claude-review.yml` (또는 claude-code-action 이 설정된 파일) 찾기
2. `allowed_bots` 파라미터 추가:
   ```yaml
   - uses: anthropics/claude-code-action@v1
     with:
       allowed_bots: "dependabot"  # 또는 "*"
       # 나머지 설정
   ```
3. Dependabot 만 허용할지 모든 bot 을 허용할지 결정
4. 변경 후 dependabot PR 을 재트리거해서 claude-review 가 정상 동작하는지 확인

### 확인할 파일

- `.github/workflows/claude-review.yml` (또는 다른 이름)
- `.github/workflows/*.yml` 중 `anthropics/claude-code-action` 사용처 전수 검사

### Acceptance criteria

- [ ] `allowed_bots` 설정 추가
- [ ] 기존 또는 새 dependabot PR 에서 claude-review check 가 정상 동작 확인
- [ ] 추가로 이 변경이 일반 PR 의 claude-review 동작을 깨뜨리지 않는지 검증

---

## 관련 참조

- PR #544 (머지 완료): https://github.com/SeoulVentures/SeoulVenturesGroupware/pull/544
- PR #539 (머지 완료): https://github.com/SeoulVentures/SeoulVenturesGroupware/pull/539
- PR #540 (닫힘 - 참고용): https://github.com/SeoulVentures/SeoulVenturesGroupware/pull/540
- 이슈 #545: https://github.com/SeoulVentures/SeoulVenturesGroupware/issues/545
- 스펙 문서: `SeoulVenturesGroupware/docs/specs/svgw-ci-retaku-admin-tests-fix.md`
- 세션 메모리: `memory/svgw-ci-retaku-admin-recovery.md`

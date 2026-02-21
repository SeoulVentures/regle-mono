# sv-nova-master 마이그레이션 Phase 4 설계 — 운영 도구 이관

**작성일:** 2026-02-21
**대상 리포:** regle-mono (서브모듈: sv-nova-master, SeoulVenturesGroupware)
**목표:** JobResource, CfClearance, ReviewApiUser, IssueCase 4종 운영 도구를 SVGW `/admin/*` 페이지로 이관

---

## 범위

### 이관 대상
| 기능 | sv-nova-master | SVGW 대상 경로 |
|------|---------------|----------------|
| Job 큐 모니터링 | Nova `JobResource` | `/admin/jobs` |
| CF Clearance 관리 | Nova `CfClearance` | `/admin/cf-clearance` |
| Review API User 관리 | Nova `ReviewApiUser` + RefreshCremaToken | `/admin/review-api-users` |
| Issue Case 관리 | Nova `IssueCase` | `/admin/issue-cases` |

### 제외 (Phase 5에서 처리)
- MongoDB 리뷰 직접 조회 (Filament MongoDBReviews) — 구현 비용 높음

---

## 아키텍처

```
SVGW API (auth:sanctum)
  Route::prefix('admin')
    → GET  /jobs                    → JobController@index
    → GET  /cf-clearance            → CfClearanceController@index
    → GET  /review-api-users        → ReviewApiUserController@index
    → POST /review-api-users/refresh-crema-token → ReviewApiUserController@refreshCremaToken
    → GET  /issue-cases             → IssueCaseController@index
    → PATCH /issue-cases/{id}/toggle-resolved → IssueCaseController@toggleResolved
```

---

## 컴포넌트 설계

### 1. JobController

`app/Http/Controllers/Admin/JobController.php`

- 모델: `App\Models\Job` — sv_nova DB의 `jobs` 테이블 (Laravel 기본 큐 테이블)
- `index()`: paginate(20), queue 필터
- payload에서 config_id 추출: PHP unserialize 대신 JSON에서 정규식으로 안전하게 추출
  ```php
  // payload->data->command 필드에서 config_id 파싱
  preg_match('/s:\d+:"config_id";i:(\d+)/', $payload, $matches)
  ```
- 응답 필드: `id`, `queue`, `config_id`(추출), `attempts`, `available_at`, `created_at`
- 읽기 전용 (생성/수정/삭제 없음)

### 2. CfClearanceController

`app/Http/Controllers/Admin/CfClearanceController.php`

- 모델: `App\Models\CfClearance` — sv_nova DB의 `cf_clearances` 테이블
- `index()`: paginate(20), endpoint/ip 필터
- 응답 필드: `id`, `cf_clearance_value`(앞 20자 + `...` 마스킹), `ip`, `user_agent`, `endpoint`, `created_at`
- 읽기 전용

### 3. ReviewApiUserController + CremaApiService

`app/Http/Controllers/Admin/ReviewApiUserController.php`
`app/Services/CremaApiService.php` (신규 — sv-nova-master에서 이식)

- 모델: `App\Models\ReviewApiUser` — retaku_admin DB의 `review_api_users` 테이블
- `index()`: 전체 목록 (페이지네이션 불필요, 레코드 수 적음)
  - `client_password`, `authorization` 필드 마스킹(`****`) 처리
- `refreshCremaToken()`: `CremaApiService::refreshToken()` 호출
  - Crema OAuth 토큰 갱신: `POST https://api.cre.ma/oauth/token`
  - 성공 시 `authorization` 필드 업데이트
  - 실패 시 HTTP 422 + 에러 메시지

**CremaApiService 이식 범위:**
- `refreshToken()` 메서드만 이식 (loadBrands는 제외 — 기존 CremaBrand 기능에 이미 연결)

### 4. IssueCaseController

`app/Http/Controllers/Admin/IssueCaseController.php`

- 모델: `App\Models\IssueCase` — sv_nova DB의 `issue_cases` 테이블
- `index()`: paginate(20), type/is_resolved 필터
  - cross-DB: `client_id` → client name은 별도 조회 후 응답에 포함
  - cross-DB: `driver_config_id` → driver config name 별도 조회 후 포함
- `toggleResolved(IssueCase $issueCase)`: `is_resolved` 반전 후 저장

---

## 모델 정리

| 모델 | connection | 테이블 | 비고 |
|------|-----------|--------|------|
| `App\Models\Job` | `sv_nova` | `jobs` | 기존 모델 활용 또는 신규 |
| `App\Models\CfClearance` | `sv_nova` | `cf_clearances` | 신규 |
| `App\Models\ReviewApiUser` | `retaku_admin` | `review_api_users` | 신규 |
| `App\Models\IssueCase` | `sv_nova` | `issue_cases` | 신규 |

---

## 프론트엔드 설계

### 공통 패턴
- `definePage({ meta: { action: 'read', subject: 'review' } })` — 기존 review 권한 재활용
- VDataTable + VPagination (JobResource, CfClearance, IssueCase)
- API 엔티티: `frontend/resources/ts/api/entities/admin/` 디렉토리 신규 생성

### 페이지별 주요 기능

**`/admin/jobs`**
- 컬럼: ID, Queue, Config ID, Attempts, Available At
- 필터: queue 선택

**`/admin/cf-clearance`**
- 컬럼: ID, CF Clearance (마스킹), IP, User Agent, Endpoint, Created At
- 필터: endpoint, IP

**`/admin/review-api-users`**
- 컬럼: ID, Client, Client ID, Password(****), Authorization(****)
- "크레마 토큰 갱신" 버튼 — POST /admin/review-api-users/refresh-crema-token

**`/admin/issue-cases`**
- 컬럼: ID, Type, Client, Driver Config, Content(축약), Is Resolved, Created At
- 필터: type, is_resolved
- 각 행에 "해결 완료/미해결" 토글 버튼

---

## 에러 처리

| 상황 | 처리 방식 |
|------|----------|
| payload 파싱 실패 | config_id = null 반환, 에러 무시 |
| Crema API 호출 실패 | HTTP 422 + 에러 메시지 |
| IssueCaseController cross-DB 조회 실패 | client_name = "Unknown #{id}" |
| ReviewApiUser 없음 | 404 반환 |

---

## 테스트

- `tests/Feature/Admin/JobControllerTest.php` — 인증 401 테스트
- `tests/Feature/Admin/CfClearanceControllerTest.php` — 인증 401 테스트
- `tests/Feature/Admin/ReviewApiUserControllerTest.php` — 인증 401, refreshCremaToken Http::fake
- `tests/Feature/Admin/IssueCaseControllerTest.php` — 인증 401, toggleResolved 동작 확인

---

## 변경 파일 목록

| 파일 | 작업 | 위치 |
|------|------|------|
| `app/Models/CfClearance.php` | 신규 | SVGW |
| `app/Models/ReviewApiUser.php` | 신규 | SVGW |
| `app/Models/IssueCase.php` | 신규 | SVGW |
| `app/Services/CremaApiService.php` | 신규 (refreshToken만 이식) | SVGW |
| `app/Http/Controllers/Admin/JobController.php` | 신규 | SVGW |
| `app/Http/Controllers/Admin/CfClearanceController.php` | 신규 | SVGW |
| `app/Http/Controllers/Admin/ReviewApiUserController.php` | 신규 | SVGW |
| `app/Http/Controllers/Admin/IssueCaseController.php` | 신규 | SVGW |
| `routes/api.php` | admin 라우트 그룹 추가 | SVGW |
| `frontend/resources/ts/api/entities/admin/jobs.ts` | 신규 | SVGW |
| `frontend/resources/ts/api/entities/admin/cfClearance.ts` | 신규 | SVGW |
| `frontend/resources/ts/api/entities/admin/reviewApiUsers.ts` | 신규 | SVGW |
| `frontend/resources/ts/api/entities/admin/issueCases.ts` | 신규 | SVGW |
| `frontend/resources/ts/pages/admin/jobs/index.vue` | 신규 | SVGW |
| `frontend/resources/ts/pages/admin/cf-clearance/index.vue` | 신규 | SVGW |
| `frontend/resources/ts/pages/admin/review-api-users/index.vue` | 신규 | SVGW |
| `frontend/resources/ts/pages/admin/issue-cases/index.vue` | 신규 | SVGW |
| `tests/Feature/Admin/JobControllerTest.php` | 신규 | SVGW |
| `tests/Feature/Admin/CfClearanceControllerTest.php` | 신규 | SVGW |
| `tests/Feature/Admin/ReviewApiUserControllerTest.php` | 신규 | SVGW |
| `tests/Feature/Admin/IssueCaseControllerTest.php` | 신규 | SVGW |
| `app/Nova/JobResource.php` | `$displayInNavigation = false` | sv-nova-master |
| `app/Nova/CfClearance.php` | `$displayInNavigation = false` | sv-nova-master |
| `app/Nova/ReviewApiUser.php` | `$displayInNavigation = false` | sv-nova-master |
| `app/Nova/IssueCase.php` | `$displayInNavigation = false` | sv-nova-master |

---

## 리스크

| 리스크 | 완화 방안 |
|--------|----------|
| jobs 테이블이 sv_nova에 없을 수 있음 | 컨트롤러 진입 전 테이블 존재 확인, 없으면 빈 목록 반환 |
| ReviewApiUser 민감정보 노출 | 응답에서 마스킹 처리, HTTPS 전제 |
| IssueCase cross-DB BelongsTo | 서비스 레이어에서 별도 쿼리로 처리 |
| Crema API 인증 변경 시 refreshToken 실패 | 에러 응답 명확히 반환, Slack 알림 고려 |

# Phase 4 운영 도구 이관 구현 계획

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** sv-nova-master의 JobResource, CfClearance, ReviewApiUser, IssueCase 4종 운영 도구를 SVGW `/admin/*` 페이지로 이관한다.

**Architecture:** SVGW `auth:sanctum` 미들웨어 그룹 내 `admin` prefix 라우트 그룹을 신규 추가하고, `app/Http/Controllers/Admin/` 하위에 컨트롤러 4개를 생성한다. 프론트엔드는 `pages/admin/` 하위에 Vue 3 + Vuetify 3 페이지 4개를 추가한다.

**Tech Stack:** Laravel 12 / PHP 8.4, Vue 3 + TypeScript + Vuetify 3, sv_nova MySQL DB, retaku_admin MySQL DB

---

## 참고 파일

| 역할 | 경로 |
|------|------|
| 라우트 파일 | `SeoulVenturesGroupware/routes/api.php` (끝부분 `});` 직전에 admin 그룹 추가) |
| 컨트롤러 패턴 | `SeoulVenturesGroupware/app/Http/Controllers/Review/NaverXlsController.php` |
| API 엔티티 패턴 | `SeoulVenturesGroupware/frontend/resources/ts/api/entities/review/naverXls.ts` |
| 페이지 패턴 | `SeoulVenturesGroupware/frontend/resources/ts/pages/review/naver-xls/index.vue` |
| 설계 문서 | `docs/plans/2026-02-21-sv-nova-master-migration-phase4-design.md` |
| sv-nova-master 원본 서비스 | `sv-nova-master/app/Services/CremaApiService.php` |

## 작업 브랜치

```bash
cd SeoulVenturesGroupware
git checkout -b feat/admin-tools-migration
```

---

## Task 1: CfClearance 모델 + 컨트롤러 + 라우트

**Files:**
- Create: `SeoulVenturesGroupware/app/Models/CfClearance.php`
- Create: `SeoulVenturesGroupware/app/Http/Controllers/Admin/CfClearanceController.php`
- Modify: `SeoulVenturesGroupware/routes/api.php`
- Create: `SeoulVenturesGroupware/tests/Feature/Admin/CfClearanceControllerTest.php`

**컨텍스트:**
- `CfClearance` 모델: sv_nova DB, `cf_clearances` 테이블
- 필드: `id`, `cf_clearance_value`, `ip`, `user_agent`, `endpoint`, `created_at`, `updated_at`
- 조회 전용, paginate(20), endpoint/ip 필터
- `cf_clearance_value`는 응답에서 앞 20자 + `...` 마스킹

**Step 1: 테스트 작성**

```php
<?php

namespace Tests\Feature\Admin;

use Tests\TestCase;

class CfClearanceControllerTest extends TestCase
{
    public function test_index_requires_auth(): void
    {
        $response = $this->getJson('/api/admin/cf-clearance');
        $response->assertStatus(401);
    }
}
```

**Step 2: 테스트 실행 (실패 확인)**

```bash
cd SeoulVenturesGroupware && vendor/bin/phpunit tests/Feature/Admin/CfClearanceControllerTest.php --no-coverage
```
Expected: FAIL - 404 (라우트 없음)

**Step 3: 모델 구현**

```php
<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class CfClearance extends Model
{
    protected $connection = 'sv_nova';
    protected $table = 'cf_clearances';
    protected $guarded = [];
}
```

**Step 4: 컨트롤러 구현**

```php
<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\CfClearance;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class CfClearanceController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $query = CfClearance::orderBy('created_at', 'desc');

        if ($request->filled('endpoint')) {
            $query->where('endpoint', 'like', '%' . $request->string('endpoint') . '%');
        }
        if ($request->filled('ip')) {
            $query->where('ip', $request->string('ip'));
        }

        $items = $query->paginate(20);

        // cf_clearance_value 마스킹
        $items->through(function ($item) {
            $item->cf_clearance_value = mb_substr($item->cf_clearance_value ?? '', 0, 20)
                . (mb_strlen($item->cf_clearance_value ?? '') > 20 ? '...' : '');
            return $item;
        });

        return response()->json($items);
    }
}
```

**Step 5: 라우트 추가**

`routes/api.php`의 `Route::middleware('auth:sanctum')->group(function() {` 블록 안, 기존 라우트 그룹들 아래에 추가:

```php
    // === 어드민 도구 ===
    Route::prefix('admin')->group(function () {
        Route::get('cf-clearance', [\App\Http\Controllers\Admin\CfClearanceController::class, 'index']);
    });
```

**Step 6: 테스트 실행 (통과 확인)**

```bash
cd SeoulVenturesGroupware && vendor/bin/phpunit tests/Feature/Admin/CfClearanceControllerTest.php --no-coverage
```
Expected: 1 test PASS (401)

**Step 7: 커밋**

```bash
cd SeoulVenturesGroupware && git add app/Models/CfClearance.php app/Http/Controllers/Admin/CfClearanceController.php routes/api.php tests/Feature/Admin/CfClearanceControllerTest.php
git commit -m "feat(admin): CfClearance 모델 + 컨트롤러 + 라우트 추가"
```

---

## Task 2: IssueCase 모델 + 컨트롤러 + 라우트

**Files:**
- Create: `SeoulVenturesGroupware/app/Models/IssueCase.php`
- Create: `SeoulVenturesGroupware/app/Http/Controllers/Admin/IssueCaseController.php`
- Modify: `SeoulVenturesGroupware/routes/api.php`
- Create: `SeoulVenturesGroupware/tests/Feature/Admin/IssueCaseControllerTest.php`

**컨텍스트:**
- `IssueCase` 모델: sv_nova DB, `issue_cases` 테이블
- 필드: `id`, `type`, `content`, `hash`, `is_resolved`, `client_id`, `driver_config_id`
- `client_id` → retaku_admin `clients` 테이블 cross-DB 조회 (name만 반환)
- `driver_config_id` → retaku_admin `driver_configs` 테이블 cross-DB 조회 (name만 반환)
- `toggleResolved`: is_resolved 반전

**Step 1: 테스트 작성**

```php
<?php

namespace Tests\Feature\Admin;

use Tests\TestCase;

class IssueCaseControllerTest extends TestCase
{
    public function test_index_requires_auth(): void
    {
        $response = $this->getJson('/api/admin/issue-cases');
        $response->assertStatus(401);
    }

    public function test_toggle_resolved_requires_auth(): void
    {
        $response = $this->patchJson('/api/admin/issue-cases/1/toggle-resolved');
        $response->assertStatus(401);
    }
}
```

**Step 2: 테스트 실행 (실패 확인)**

```bash
cd SeoulVenturesGroupware && vendor/bin/phpunit tests/Feature/Admin/IssueCaseControllerTest.php --no-coverage
```
Expected: FAIL - 404

**Step 3: IssueCase 모델 구현**

```php
<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class IssueCase extends Model
{
    protected $connection = 'sv_nova';
    protected $table = 'issue_cases';
    protected $guarded = [];

    protected $casts = [
        'is_resolved' => 'boolean',
    ];
}
```

**Step 4: IssueCaseController 구현**

```php
<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\IssueCase;
use App\Models\Review\Client;
use App\Models\Review\DriverConfig;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class IssueCaseController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $query = IssueCase::orderBy('created_at', 'desc');

        if ($request->filled('type')) {
            $query->where('type', $request->string('type'));
        }
        if ($request->has('is_resolved')) {
            $query->where('is_resolved', $request->boolean('is_resolved'));
        }

        $items = $query->paginate(20);

        // cross-DB: client/driverConfig name 조회
        $clientIds = $items->pluck('client_id')->filter()->unique()->values();
        $driverConfigIds = $items->pluck('driver_config_id')->filter()->unique()->values();

        $clients = Client::whereIn('id', $clientIds)->pluck('name', 'id');
        $driverConfigs = DriverConfig::whereIn('id', $driverConfigIds)->pluck('name', 'id');

        $items->through(function ($item) use ($clients, $driverConfigs) {
            $item->client_name = $clients[$item->client_id] ?? "Unknown #{$item->client_id}";
            $item->driver_config_name = $driverConfigs[$item->driver_config_id] ?? "Unknown #{$item->driver_config_id}";
            return $item;
        });

        return response()->json($items);
    }

    public function toggleResolved(IssueCase $issueCase): JsonResponse
    {
        $issueCase->update(['is_resolved' => !$issueCase->is_resolved]);
        return response()->json($issueCase);
    }
}
```

**Step 5: 라우트 추가**

`routes/api.php`의 admin prefix 블록에 추가:

```php
        Route::get('issue-cases', [\App\Http\Controllers\Admin\IssueCaseController::class, 'index']);
        Route::patch('issue-cases/{issueCase}/toggle-resolved', [\App\Http\Controllers\Admin\IssueCaseController::class, 'toggleResolved']);
```

**Step 6: 테스트 실행 (통과 확인)**

```bash
cd SeoulVenturesGroupware && vendor/bin/phpunit tests/Feature/Admin/IssueCaseControllerTest.php --no-coverage
```
Expected: 2 tests PASS (401)

**Step 7: 커밋**

```bash
cd SeoulVenturesGroupware && git add app/Models/IssueCase.php app/Http/Controllers/Admin/IssueCaseController.php routes/api.php tests/Feature/Admin/IssueCaseControllerTest.php
git commit -m "feat(admin): IssueCase 모델 + 컨트롤러 + 라우트 추가"
```

---

## Task 3: ReviewApiUser 모델 + CremaApiService + 컨트롤러 + 라우트

**Files:**
- Create: `SeoulVenturesGroupware/app/Models/ReviewApiUser.php`
- Create: `SeoulVenturesGroupware/app/Services/CremaApiService.php`
- Create: `SeoulVenturesGroupware/app/Http/Controllers/Admin/ReviewApiUserController.php`
- Modify: `SeoulVenturesGroupware/routes/api.php`
- Create: `SeoulVenturesGroupware/tests/Feature/Admin/ReviewApiUserControllerTest.php`

**컨텍스트:**
- `ReviewApiUser` 모델: retaku_admin DB, `review_api_users` 테이블, `timestamps = false`
- 필드: `id`, `client_id`, `client_password`, `authorization`, `client`
- `client_password`, `authorization` → 응답에서 `****` 마스킹
- `CremaApiService::refreshToken()`: Crema OAuth 토큰 갱신
  - `POST https://api.cre.ma/oauth/token` with `grant_type`, `client_id`, `client_secret`
  - 응답의 `access_token`으로 `authorization` 업데이트

**Step 1: 테스트 작성**

```php
<?php

namespace Tests\Feature\Admin;

use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class ReviewApiUserControllerTest extends TestCase
{
    public function test_index_requires_auth(): void
    {
        $response = $this->getJson('/api/admin/review-api-users');
        $response->assertStatus(401);
    }

    public function test_refresh_crema_token_requires_auth(): void
    {
        $response = $this->postJson('/api/admin/review-api-users/refresh-crema-token');
        $response->assertStatus(401);
    }
}
```

**Step 2: 테스트 실행 (실패 확인)**

```bash
cd SeoulVenturesGroupware && vendor/bin/phpunit tests/Feature/Admin/ReviewApiUserControllerTest.php --no-coverage
```
Expected: FAIL - 404

**Step 3: ReviewApiUser 모델 구현**

```php
<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class ReviewApiUser extends Model
{
    protected $connection = 'retaku_admin';
    protected $table = 'review_api_users';
    protected $guarded = [];
    public $timestamps = false;
}
```

**Step 4: CremaApiService 구현**

```php
<?php

namespace App\Services;

use App\Models\ReviewApiUser;
use Illuminate\Support\Facades\Http;

class CremaApiService
{
    private const API_ENDPOINT = 'https://api.cre.ma';

    /**
     * Crema OAuth 토큰을 갱신하고 ReviewApiUser의 authorization을 업데이트한다.
     */
    public function refreshToken(): void
    {
        $reviewApiUser = ReviewApiUser::where('client', 'crema')->firstOrFail();

        $response = Http::post(self::API_ENDPOINT . '/oauth/token', [
            'grant_type'    => 'client_credentials',
            'client_id'     => $reviewApiUser->client_id,
            'client_secret' => $reviewApiUser->client_password,
        ]);

        if (!$response->successful()) {
            throw new \RuntimeException('Crema 토큰 갱신 실패: ' . $response->body());
        }

        $data = $response->json();
        $reviewApiUser->update([
            'authorization' => $data['token_type'] . ' ' . $data['access_token'],
        ]);
    }
}
```

**Step 5: ReviewApiUserController 구현**

```php
<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\ReviewApiUser;
use App\Services\CremaApiService;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\Log;

class ReviewApiUserController extends Controller
{
    public function __construct(private CremaApiService $cremaApiService) {}

    public function index(): JsonResponse
    {
        $items = ReviewApiUser::all()->map(function ($item) {
            $item->client_password = '****';
            $item->authorization = '****';
            return $item;
        });

        return response()->json($items);
    }

    public function refreshCremaToken(): JsonResponse
    {
        try {
            $this->cremaApiService->refreshToken();
            return response()->json(['message' => '크레마 토큰이 갱신되었습니다.']);
        } catch (\Throwable $e) {
            Log::error('ReviewApiUserController: 크레마 토큰 갱신 실패', [
                'error' => $e->getMessage(),
            ]);
            return response()->json(['message' => '토큰 갱신 실패: ' . $e->getMessage()], 422);
        }
    }
}
```

**Step 6: 라우트 추가**

```php
        Route::get('review-api-users', [\App\Http\Controllers\Admin\ReviewApiUserController::class, 'index']);
        Route::post('review-api-users/refresh-crema-token', [\App\Http\Controllers\Admin\ReviewApiUserController::class, 'refreshCremaToken']);
```

**Step 7: 테스트 실행 (통과 확인)**

```bash
cd SeoulVenturesGroupware && vendor/bin/phpunit tests/Feature/Admin/ReviewApiUserControllerTest.php --no-coverage
```
Expected: 2 tests PASS (401)

**Step 8: 커밋**

```bash
cd SeoulVenturesGroupware && git add app/Models/ReviewApiUser.php app/Services/CremaApiService.php app/Http/Controllers/Admin/ReviewApiUserController.php routes/api.php tests/Feature/Admin/ReviewApiUserControllerTest.php
git commit -m "feat(admin): ReviewApiUser 모델 + CremaApiService + 컨트롤러 + 라우트 추가"
```

---

## Task 4: Job 컨트롤러 + 라우트

**Files:**
- Create: `SeoulVenturesGroupware/app/Http/Controllers/Admin/JobController.php`
- Modify: `SeoulVenturesGroupware/routes/api.php`
- Create: `SeoulVenturesGroupware/tests/Feature/Admin/JobControllerTest.php`

**컨텍스트:**
- Laravel 기본 `jobs` 테이블 사용 (sv_nova DB)
- 모델 없이 DB 파사드로 직접 쿼리 (모델 불필요)
- payload JSON → `data.command` 필드에서 정규식으로 config_id 추출:
  ```
  preg_match('/s:\d+:"config_id";i:(\d+)/', $payload, $matches)
  ```
- 테이블이 없을 경우 빈 목록 반환
- 응답 필드: `id`, `queue`, `config_id`, `attempts`, `available_at`

**Step 1: 테스트 작성**

```php
<?php

namespace Tests\Feature\Admin;

use Tests\TestCase;

class JobControllerTest extends TestCase
{
    public function test_index_requires_auth(): void
    {
        $response = $this->getJson('/api/admin/jobs');
        $response->assertStatus(401);
    }
}
```

**Step 2: 테스트 실행 (실패 확인)**

```bash
cd SeoulVenturesGroupware && vendor/bin/phpunit tests/Feature/Admin/JobControllerTest.php --no-coverage
```
Expected: FAIL - 404

**Step 3: JobController 구현**

```php
<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

class JobController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        // sv_nova DB의 jobs 테이블이 없으면 빈 목록 반환
        if (!Schema::connection('sv_nova')->hasTable('jobs')) {
            return response()->json([
                'data' => [],
                'total' => 0,
                'current_page' => 1,
                'last_page' => 1,
                'per_page' => 20,
            ]);
        }

        $query = DB::connection('sv_nova')
            ->table('jobs')
            ->select('id', 'queue', 'payload', 'attempts', 'reserved_at', 'available_at', 'created_at')
            ->orderBy('id', 'desc');

        if ($request->filled('queue')) {
            $query->where('queue', $request->string('queue'));
        }

        $paginator = $query->paginate(20);

        $items = collect($paginator->items())->map(function ($job) {
            $payload = json_decode($job->payload, true);
            $command = $payload['data']['command'] ?? '';
            $configId = null;
            if (preg_match('/s:\d+:"config_id";i:(\d+)/', $command, $matches)) {
                $configId = (int) $matches[1];
            }

            return [
                'id'           => $job->id,
                'queue'        => $job->queue,
                'config_id'    => $configId,
                'attempts'     => $job->attempts,
                'available_at' => $job->available_at,
                'created_at'   => $job->created_at,
            ];
        });

        return response()->json([
            'data'         => $items,
            'total'        => $paginator->total(),
            'current_page' => $paginator->currentPage(),
            'last_page'    => $paginator->lastPage(),
            'per_page'     => $paginator->perPage(),
        ]);
    }
}
```

**Step 4: 라우트 추가**

```php
        Route::get('jobs', [\App\Http\Controllers\Admin\JobController::class, 'index']);
```

**Step 5: 테스트 실행 (통과 확인)**

```bash
cd SeoulVenturesGroupware && vendor/bin/phpunit tests/Feature/Admin/JobControllerTest.php --no-coverage
```
Expected: 1 test PASS (401)

**Step 6: 전체 테스트 확인**

```bash
cd SeoulVenturesGroupware && vendor/bin/phpunit --no-coverage 2>&1 | tail -5
```
Expected: All tests PASS

**Step 7: 커밋**

```bash
cd SeoulVenturesGroupware && git add app/Http/Controllers/Admin/JobController.php routes/api.php tests/Feature/Admin/JobControllerTest.php
git commit -m "feat(admin): Job 큐 컨트롤러 + 라우트 추가"
```

---

## Task 5: 프론트엔드 — API 엔티티 4개 + 페이지 4개

**Files:**
- Create: `SeoulVenturesGroupware/frontend/resources/ts/api/entities/admin/jobs.ts`
- Create: `SeoulVenturesGroupware/frontend/resources/ts/api/entities/admin/cfClearance.ts`
- Create: `SeoulVenturesGroupware/frontend/resources/ts/api/entities/admin/reviewApiUsers.ts`
- Create: `SeoulVenturesGroupware/frontend/resources/ts/api/entities/admin/issueCases.ts`
- Create: `SeoulVenturesGroupware/frontend/resources/ts/pages/admin/jobs/index.vue`
- Create: `SeoulVenturesGroupware/frontend/resources/ts/pages/admin/cf-clearance/index.vue`
- Create: `SeoulVenturesGroupware/frontend/resources/ts/pages/admin/review-api-users/index.vue`
- Create: `SeoulVenturesGroupware/frontend/resources/ts/pages/admin/issue-cases/index.vue`

**컨텍스트:**
- API 엔티티 패턴: `frontend/resources/ts/api/entities/review/naverXls.ts` 참고
- 페이지 패턴: `frontend/resources/ts/pages/review/naver-xls/index.vue` 참고
- `definePage({ meta: { title: '...', action: 'read', subject: 'review' } })`
- **배럴 익스포트(`index.ts`) 절대 생성 금지** (CLAUDE.md 규정)

**Step 1: API 엔티티 파일 4개 작성**

`frontend/resources/ts/api/entities/admin/jobs.ts`:
```typescript
import { type ApiResponse, get } from '@/api'

export interface Job {
  id: number
  queue: string
  config_id: number | null
  attempts: number
  available_at: number | null
  created_at: number | null
}

export interface JobsPaginated {
  data: Job[]
  total: number
  per_page: number
  current_page: number
  last_page: number
}

export const jobsApi = {
  list: (queue?: string, page?: number): Promise<ApiResponse<JobsPaginated>> => {
    const params: Record<string, unknown> = {}
    if (queue) params.queue = queue
    if (page && page > 1) params.page = page
    return get('/admin/jobs', Object.keys(params).length ? params : undefined)
  },
}
```

`frontend/resources/ts/api/entities/admin/cfClearance.ts`:
```typescript
import { type ApiResponse, get } from '@/api'

export interface CfClearance {
  id: number
  cf_clearance_value: string | null
  ip: string | null
  user_agent: string | null
  endpoint: string | null
  created_at: string
}

export interface CfClearancePaginated {
  data: CfClearance[]
  total: number
  per_page: number
  current_page: number
  last_page: number
}

export const cfClearanceApi = {
  list: (params?: { endpoint?: string; ip?: string; page?: number }): Promise<ApiResponse<CfClearancePaginated>> => {
    const query: Record<string, unknown> = {}
    if (params?.endpoint) query.endpoint = params.endpoint
    if (params?.ip) query.ip = params.ip
    if (params?.page && params.page > 1) query.page = params.page
    return get('/admin/cf-clearance', Object.keys(query).length ? query : undefined)
  },
}
```

`frontend/resources/ts/api/entities/admin/reviewApiUsers.ts`:
```typescript
import { type ApiResponse, get, post } from '@/api'

export interface ReviewApiUser {
  id: number
  client_id: string | null
  client_password: string
  authorization: string
  client: string | null
}

export const reviewApiUsersApi = {
  list: (): Promise<ApiResponse<ReviewApiUser[]>> =>
    get('/admin/review-api-users'),

  refreshCremaToken: (): Promise<ApiResponse<{ message: string }>> =>
    post('/admin/review-api-users/refresh-crema-token', {}),
}
```

`frontend/resources/ts/api/entities/admin/issueCases.ts`:
```typescript
import { type ApiResponse, get, patch } from '@/api'

export interface IssueCase {
  id: number
  type: string
  content: string
  hash: string
  is_resolved: boolean
  client_id: number | null
  driver_config_id: number | null
  client_name: string
  driver_config_name: string
  created_at: string
}

export interface IssueCasesPaginated {
  data: IssueCase[]
  total: number
  per_page: number
  current_page: number
  last_page: number
}

export const issueCasesApi = {
  list: (params?: { type?: string; is_resolved?: boolean; page?: number }): Promise<ApiResponse<IssueCasesPaginated>> => {
    const query: Record<string, unknown> = {}
    if (params?.type) query.type = params.type
    if (params?.is_resolved !== undefined) query.is_resolved = params.is_resolved ? 1 : 0
    if (params?.page && params.page > 1) query.page = params.page
    return get('/admin/issue-cases', Object.keys(query).length ? query : undefined)
  },

  toggleResolved: (id: number): Promise<ApiResponse<IssueCase>> =>
    patch(`/admin/issue-cases/${id}/toggle-resolved`, {}),
}
```

> `patch` 함수가 `@/api`에 없을 경우: `post`로 대체하고 라우트를 `POST`로 변경

**Step 2: api/index.ts에서 patch export 여부 확인**

```bash
grep -n "export.*patch\|^export" SeoulVenturesGroupware/frontend/resources/ts/api/index.ts | head -20
```

`patch`가 없으면 issueCases.ts의 `patch` 임포트를 `post`로 바꾸고, `routes/api.php`의 `PATCH`를 `POST`로 변경.

**Step 3: 페이지 4개 작성**

`frontend/resources/ts/pages/admin/jobs/index.vue`:
```vue
<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { type Job, jobsApi } from '@/api/entities/admin/jobs'

definePage({
  meta: { title: 'Job 큐 모니터링', action: 'read', subject: 'review' },
})

const { snackbar, handleError } = useErrorHandler()
const loading = ref(false)
const jobs = ref<Job[]>([])
const total = ref(0)
const currentPage = ref(1)
const lastPage = ref(1)
const queueFilter = ref('')

const headers = [
  { title: 'ID', key: 'id', sortable: false },
  { title: 'Queue', key: 'queue', sortable: false },
  { title: 'Config ID', key: 'config_id', sortable: false },
  { title: 'Attempts', key: 'attempts', sortable: false },
  { title: 'Available At', key: 'available_at', sortable: false },
]

const loadJobs = async () => {
  loading.value = true
  try {
    const { success, data } = await jobsApi.list(queueFilter.value || undefined, currentPage.value)
    if (success && data) {
      jobs.value = data.data
      total.value = data.total
      lastPage.value = data.last_page
    }
  }
  catch (error) {
    handleError(error, { showNotification: false })
  }
  finally {
    loading.value = false
  }
}

const onPageChange = (page: number) => {
  currentPage.value = page
  loadJobs()
}

const formatTimestamp = (ts: number | null): string => {
  if (!ts) return '-'
  return new Date(ts * 1000).toLocaleString('ko-KR')
}

onMounted(loadJobs)
</script>

<template>
  <VCard>
    <VCardTitle class="pa-4">Job 큐 모니터링</VCardTitle>
    <VCardText>
      <VRow class="mb-4">
        <VCol cols="12" md="4">
          <VTextField v-model="queueFilter" label="Queue 필터" clearable hide-details @keyup.enter="loadJobs" />
        </VCol>
        <VCol cols="12" md="2">
          <VBtn color="primary" @click="loadJobs">검색</VBtn>
        </VCol>
      </VRow>
      <VDataTable :headers="headers" :items="jobs" :loading="loading" hide-default-footer>
        <template #item.available_at="{ item }">
          {{ formatTimestamp(item.available_at) }}
        </template>
        <template #no-data>
          <div class="text-center py-8">대기 중인 Job이 없습니다.</div>
        </template>
      </VDataTable>
      <div v-if="lastPage > 1" class="d-flex justify-center mt-4">
        <VPagination :model-value="currentPage" :length="lastPage" @update:model-value="onPageChange" />
      </div>
    </VCardText>
  </VCard>
</template>
```

`frontend/resources/ts/pages/admin/cf-clearance/index.vue`:
```vue
<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { type CfClearance, cfClearanceApi } from '@/api/entities/admin/cfClearance'

definePage({
  meta: { title: 'CF Clearance 관리', action: 'read', subject: 'review' },
})

const { handleError } = useErrorHandler()
const loading = ref(false)
const items = ref<CfClearance[]>([])
const currentPage = ref(1)
const lastPage = ref(1)
const endpointFilter = ref('')
const ipFilter = ref('')

const headers = [
  { title: 'ID', key: 'id', sortable: false },
  { title: 'CF Clearance Value', key: 'cf_clearance_value', sortable: false },
  { title: 'IP', key: 'ip', sortable: false },
  { title: 'Endpoint', key: 'endpoint', sortable: false },
  { title: 'Created At', key: 'created_at', sortable: false },
]

const loadItems = async () => {
  loading.value = true
  try {
    const { success, data } = await cfClearanceApi.list({
      endpoint: endpointFilter.value || undefined,
      ip: ipFilter.value || undefined,
      page: currentPage.value,
    })
    if (success && data) {
      items.value = data.data
      lastPage.value = data.last_page
    }
  }
  catch (error) {
    handleError(error, { showNotification: false })
  }
  finally {
    loading.value = false
  }
}

const onPageChange = (page: number) => {
  currentPage.value = page
  loadItems()
}

const formatDate = (d: string | null) => d ? new Date(d).toLocaleString('ko-KR') : '-'

onMounted(loadItems)
</script>

<template>
  <VCard>
    <VCardTitle class="pa-4">CF Clearance 관리</VCardTitle>
    <VCardText>
      <VRow class="mb-4">
        <VCol cols="12" md="3">
          <VTextField v-model="endpointFilter" label="Endpoint 필터" clearable hide-details />
        </VCol>
        <VCol cols="12" md="3">
          <VTextField v-model="ipFilter" label="IP 필터" clearable hide-details />
        </VCol>
        <VCol cols="12" md="2">
          <VBtn color="primary" @click="loadItems">검색</VBtn>
        </VCol>
      </VRow>
      <VDataTable :headers="headers" :items="items" :loading="loading" hide-default-footer>
        <template #item.created_at="{ item }">{{ formatDate(item.created_at) }}</template>
        <template #no-data>
          <div class="text-center py-8">데이터가 없습니다.</div>
        </template>
      </VDataTable>
      <div v-if="lastPage > 1" class="d-flex justify-center mt-4">
        <VPagination :model-value="currentPage" :length="lastPage" @update:model-value="onPageChange" />
      </div>
    </VCardText>
  </VCard>
</template>
```

`frontend/resources/ts/pages/admin/review-api-users/index.vue`:
```vue
<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { type ReviewApiUser, reviewApiUsersApi } from '@/api/entities/admin/reviewApiUsers'

definePage({
  meta: { title: 'Review API Users', action: 'read', subject: 'review' },
})

const { snackbar, handleError } = useErrorHandler()
const loading = ref(false)
const refreshing = ref(false)
const users = ref<ReviewApiUser[]>([])

const headers = [
  { title: 'ID', key: 'id', sortable: false },
  { title: 'Client', key: 'client', sortable: false },
  { title: 'Client ID', key: 'client_id', sortable: false },
  { title: 'Password', key: 'client_password', sortable: false },
  { title: 'Authorization', key: 'authorization', sortable: false },
]

const loadUsers = async () => {
  loading.value = true
  try {
    const { success, data } = await reviewApiUsersApi.list()
    if (success && data) users.value = data
  }
  catch (error) {
    handleError(error, { showNotification: false })
  }
  finally {
    loading.value = false
  }
}

const handleRefreshCremaToken = async () => {
  refreshing.value = true
  try {
    const { success, error } = await reviewApiUsersApi.refreshCremaToken()
    if (success) {
      snackbar.success('크레마 토큰이 갱신되었습니다.')
      await loadUsers()
    }
    else {
      snackbar.error(error?.message || '토큰 갱신 실패')
    }
  }
  catch (error) {
    handleError(error)
  }
  finally {
    refreshing.value = false
  }
}

onMounted(loadUsers)
</script>

<template>
  <VCard>
    <VCardTitle class="pa-4 d-flex align-center justify-space-between">
      Review API Users
      <VBtn color="warning" :loading="refreshing" @click="handleRefreshCremaToken">
        크레마 토큰 갱신
      </VBtn>
    </VCardTitle>
    <VCardText>
      <VDataTable :headers="headers" :items="users" :loading="loading" hide-default-footer>
        <template #no-data>
          <div class="text-center py-8">데이터가 없습니다.</div>
        </template>
      </VDataTable>
    </VCardText>
  </VCard>
</template>
```

`frontend/resources/ts/pages/admin/issue-cases/index.vue`:
```vue
<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { type IssueCase, issueCasesApi } from '@/api/entities/admin/issueCases'

definePage({
  meta: { title: 'Issue Cases', action: 'read', subject: 'review' },
})

const { snackbar, handleError } = useErrorHandler()
const loading = ref(false)
const items = ref<IssueCase[]>([])
const currentPage = ref(1)
const lastPage = ref(1)
const typeFilter = ref('')
const resolvedFilter = ref<boolean | null>(null)

const headers = [
  { title: 'ID', key: 'id', sortable: false },
  { title: 'Type', key: 'type', sortable: false },
  { title: 'Client', key: 'client_name', sortable: false },
  { title: 'Driver Config', key: 'driver_config_name', sortable: false },
  { title: 'Content', key: 'content', sortable: false },
  { title: '해결 여부', key: 'is_resolved', sortable: false },
  { title: 'Created At', key: 'created_at', sortable: false },
  { title: '작업', key: 'actions', sortable: false },
]

const loadItems = async () => {
  loading.value = true
  try {
    const { success, data } = await issueCasesApi.list({
      type: typeFilter.value || undefined,
      is_resolved: resolvedFilter.value ?? undefined,
      page: currentPage.value,
    })
    if (success && data) {
      items.value = data.data
      lastPage.value = data.last_page
    }
  }
  catch (error) {
    handleError(error, { showNotification: false })
  }
  finally {
    loading.value = false
  }
}

const toggleResolved = async (item: IssueCase) => {
  try {
    const { success, error } = await issueCasesApi.toggleResolved(item.id)
    if (success) {
      snackbar.success('상태가 변경되었습니다.')
      await loadItems()
    }
    else {
      snackbar.error(error?.message || '변경 실패')
    }
  }
  catch (error) {
    handleError(error)
  }
}

const onPageChange = (page: number) => {
  currentPage.value = page
  loadItems()
}

const formatDate = (d: string | null) => d ? new Date(d).toLocaleString('ko-KR') : '-'
const truncate = (s: string, n = 50) => s.length > n ? s.slice(0, n) + '...' : s

onMounted(loadItems)
</script>

<template>
  <VCard>
    <VCardTitle class="pa-4">Issue Cases</VCardTitle>
    <VCardText>
      <VRow class="mb-4">
        <VCol cols="12" md="3">
          <VTextField v-model="typeFilter" label="Type 필터" clearable hide-details />
        </VCol>
        <VCol cols="12" md="3">
          <VSelect
            v-model="resolvedFilter"
            :items="[{ title: '전체', value: null }, { title: '해결됨', value: true }, { title: '미해결', value: false }]"
            item-title="title"
            item-value="value"
            label="해결 여부"
            hide-details
          />
        </VCol>
        <VCol cols="12" md="2">
          <VBtn color="primary" @click="loadItems">검색</VBtn>
        </VCol>
      </VRow>
      <VDataTable :headers="headers" :items="items" :loading="loading" hide-default-footer>
        <template #item.content="{ item }">{{ truncate(item.content) }}</template>
        <template #item.is_resolved="{ item }">
          <VChip :color="item.is_resolved ? 'success' : 'warning'" size="small">
            {{ item.is_resolved ? '해결됨' : '미해결' }}
          </VChip>
        </template>
        <template #item.created_at="{ item }">{{ formatDate(item.created_at) }}</template>
        <template #item.actions="{ item }">
          <VBtn size="small" :color="item.is_resolved ? 'warning' : 'success'" @click="toggleResolved(item)">
            {{ item.is_resolved ? '미해결로' : '해결 완료' }}
          </VBtn>
        </template>
        <template #no-data>
          <div class="text-center py-8">데이터가 없습니다.</div>
        </template>
      </VDataTable>
      <div v-if="lastPage > 1" class="d-flex justify-center mt-4">
        <VPagination :model-value="currentPage" :length="lastPage" @update:model-value="onPageChange" />
      </div>
    </VCardText>
  </VCard>
</template>
```

**Step 4: 타입체크**

```bash
cd SeoulVenturesGroupware/frontend && bun run typecheck 2>&1 | grep -E "admin|error" | head -20
```
Expected: admin 관련 타입 오류 없음 (기존 오류만 있음)

**Step 5: 전체 테스트 확인**

```bash
cd SeoulVenturesGroupware && vendor/bin/phpunit --no-coverage 2>&1 | tail -5
```
Expected: All PASS

**Step 6: 커밋**

```bash
cd SeoulVenturesGroupware && git add \
  frontend/resources/ts/api/entities/admin/ \
  frontend/resources/ts/pages/admin/
git commit -m "feat(admin): 운영 도구 프론트엔드 페이지 4개 추가 (jobs, cf-clearance, review-api-users, issue-cases)"
```

---

## Task 6: sv-nova-master Nova 4개 Resource 숨김

**Files:**
- Modify: `sv-nova-master/app/Nova/JobResource.php`
- Modify: `sv-nova-master/app/Nova/CfClearance.php`
- Modify: `sv-nova-master/app/Nova/ReviewApiUser.php`
- Modify: `sv-nova-master/app/Nova/IssueCase.php`

**Step 1: 각 Resource에 $displayInNavigation = false 추가**

각 파일의 클래스 본문 상단에 추가:
```php
public static $displayInNavigation = false;
```

**Step 2: PHP 문법 확인**

```bash
cd sv-nova-master && php -l app/Nova/JobResource.php && php -l app/Nova/CfClearance.php && php -l app/Nova/ReviewApiUser.php && php -l app/Nova/IssueCase.php
```
Expected: No syntax errors

**Step 3: sv-nova-master 커밋**

```bash
cd /opt/SeoulVentures/regle/sv-nova-master
git add app/Nova/JobResource.php app/Nova/CfClearance.php app/Nova/ReviewApiUser.php app/Nova/IssueCase.php
git commit -m "feat(admin): Nova에서 운영 도구 4개 Resource 제거 - SVGW로 이관"
```

**Step 4: regle-mono 서브모듈 업데이트 커밋**

```bash
cd /opt/SeoulVentures/regle && git add sv-nova-master
git commit -m "chore: sv-nova-master 서브모듈 업데이트 - 운영 도구 Nova 제거"
```

---

## Task 7: PR 생성

**Step 1: SVGW 브랜치 푸시**

```bash
cd SeoulVenturesGroupware && git push -u origin feat/admin-tools-migration
```

**Step 2: PR 생성**

```bash
gh pr create \
  --title "feat(admin): Phase 4 - 운영 도구 이관 (sv-nova-master → SVGW)" \
  --body "$(cat <<'EOF'
## Summary

- `CfClearance` 모델 + 조회 페이지 추가 (`/admin/cf-clearance`)
- `IssueCase` 모델 + 조회/해결토글 페이지 추가 (`/admin/issue-cases`)
- `ReviewApiUser` 모델 + `CremaApiService` + 크레마 토큰 갱신 페이지 추가 (`/admin/review-api-users`)
- Job 큐 모니터링 페이지 추가 (`/admin/jobs`)
- sv-nova-master Nova에서 4개 Resource `$displayInNavigation = false` 처리

## Test Plan

- [ ] `/api/admin/*` 인증 없이 401 반환 확인
- [ ] `/admin/jobs` 페이지 Job 목록 조회 확인
- [ ] `/admin/cf-clearance` 페이지 CF Clearance 목록 조회 확인
- [ ] `/admin/review-api-users` 페이지 사용자 목록 + 크레마 토큰 갱신 확인
- [ ] `/admin/issue-cases` 페이지 목록 조회 + is_resolved 토글 확인
- [ ] sv-nova-master Nova UI에서 해당 메뉴 미노출 확인

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

# 진열되지 않은 상품 관리 페이지 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 네이버 브랜드스토어/스마트스토어에서 진열되지 않은 상품을 DB에 저장하고, 그룹웨어에서 목록 조회(필터링/정렬/페이징) 및 매핑 삭제 기능을 제공한다.

**Architecture:** Python 크롤러(review-moai-refactoring)에서 진열되지 않은 상품 감지 시 `review_non_displayed_items` 테이블에 upsert하고, 그룹웨어(SeoulVenturesGroupware) 백엔드에서 API를 제공하며, Vue 3 프론트엔드에서 VDataTableServer 기반 관리 페이지를 구현한다.

**Tech Stack:** Python(SQLModel) / Laravel(Eloquent, retaku_admin DB) / Vue 3 + Vuetify 3 + TypeScript

---

## 파일 구조

### Python (review-moai-refactoring)
| 파일 | 역할 |
|------|------|
| `regle/Models/NonDisplayedItem.py` (생성) | SQLModel 모델 — review_non_displayed_items 테이블 |
| `app/drivers/download/NaverBrandStoreDriver.py` (수정) | 감지 시 DB upsert 추가 |
| `app/drivers/download/NaverSmartStoreDriver.py` (수정) | 감지 시 DB upsert 추가 |

### Laravel 백엔드 (SeoulVenturesGroupware)
| 파일 | 역할 |
|------|------|
| `database/migrations/2026_04_02_000001_create_review_non_displayed_items_table.php` (생성) | 마이그레이션 |
| `app/Models/Review/NonDisplayedItem.php` (생성) | Eloquent 모델 |
| `app/Services/Review/NonDisplayedItemService.php` (생성) | 비즈니스 로직 (목록, 매핑 삭제) |
| `app/Http/Controllers/Review/NonDisplayedItemController.php` (생성) | API 컨트롤러 |
| `app/Http/Resources/Review/NonDisplayedItemResource.php` (생성) | JSON 변환 |
| `routes/api.php` (수정) | 라우트 등록 |

### Vue 프론트엔드 (SeoulVenturesGroupware/frontend)
| 파일 | 역할 |
|------|------|
| `resources/ts/pages/review/non-displayed-items/index.vue` (생성) | 관리 페이지 |
| `resources/ts/api/entities/review/nonDisplayedItem.ts` (생성) | API 클라이언트 |
| `resources/ts/navigation/vertical/index.ts` (수정) | 네비게이션 메뉴 추가 |

---

## DB 스키마

```sql
CREATE TABLE review_non_displayed_items (
    id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    client_id INT UNSIGNED NOT NULL,
    config_id INT UNSIGNED NOT NULL,
    config_name VARCHAR(255) NOT NULL,
    driver_code VARCHAR(100) NOT NULL,
    target_item_code VARCHAR(255) NOT NULL,
    detected_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    resolved_at TIMESTAMP NULL DEFAULT NULL,
    created_at TIMESTAMP NULL DEFAULT NULL,
    updated_at TIMESTAMP NULL DEFAULT NULL,
    UNIQUE KEY uq_config_item (config_id, target_item_code),
    INDEX idx_client_id (client_id),
    INDEX idx_config_id (config_id),
    INDEX idx_resolved_at (resolved_at)
) DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
```

- `UNIQUE(config_id, target_item_code)` — 동일 상품 중복 방지, upsert 시 `detected_at` 갱신
- `resolved_at` — 매핑 삭제 시 타임스탬프 기록 (NULL = 미해결)

---

## Task 1: Python SQLModel 모델 생성

**Files:**
- Create: `review-moai-refactoring/regle/Models/NonDisplayedItem.py`

- [ ] **Step 1: 모델 파일 생성**

```python
from datetime import datetime
from typing import Optional

from sqlalchemy import func
from sqlmodel import Field, Session, select

from regle.connector.MySql import engine
from regle.Models.ExtendedSQLModel import ExtendedSQLModel


class NonDisplayedItem(ExtendedSQLModel, table=True):
    __tablename__ = "review_non_displayed_items"

    id: Optional[int] = Field(default=None, primary_key=True)
    client_id: int
    config_id: int
    config_name: str
    driver_code: str
    target_item_code: str
    detected_at: datetime
    resolved_at: Optional[datetime] = None
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None

    @classmethod
    def upsert_non_displayed(cls, client_id: int, config_id: int, config_name: str, driver_code: str, target_item_code: str):
        """진열되지 않은 상품 upsert. 이미 존재하면 detected_at 갱신, resolved_at NULL로 리셋."""
        with Session(engine) as session:
            statement = (
                select(cls)
                .where(cls.config_id == config_id)
                .where(cls.target_item_code == target_item_code)
            )
            existing = session.exec(statement).first()
            if existing:
                existing.detected_at = func.now()
                existing.resolved_at = None
                existing.config_name = config_name
                existing.updated_at = func.now()
                session.add(existing)
            else:
                item = cls(
                    client_id=client_id,
                    config_id=config_id,
                    config_name=config_name,
                    driver_code=driver_code,
                    target_item_code=target_item_code,
                    detected_at=func.now(),
                    created_at=func.now(),
                    updated_at=func.now(),
                )
                session.add(item)
            session.commit()

    @classmethod
    def bulk_upsert_non_displayed(cls, items: list[dict]):
        """여러 진열되지 않은 상품을 일괄 upsert."""
        with Session(engine) as session:
            for item_data in items:
                statement = (
                    select(cls)
                    .where(cls.config_id == item_data["config_id"])
                    .where(cls.target_item_code == item_data["item_code"])
                )
                existing = session.exec(statement).first()
                if existing:
                    existing.detected_at = func.now()
                    existing.resolved_at = None
                    existing.config_name = item_data["config_name"]
                    existing.updated_at = func.now()
                    session.add(existing)
                else:
                    new_item = cls(
                        client_id=item_data["client_id"],
                        config_id=item_data["config_id"],
                        config_name=item_data["config_name"],
                        driver_code=item_data["driver_code"],
                        target_item_code=item_data["item_code"],
                        detected_at=func.now(),
                        created_at=func.now(),
                        updated_at=func.now(),
                    )
                    session.add(new_item)
            session.commit()
```

- [ ] **Step 2: 커밋**

---

## Task 2: Python 드라이버 수정 — DB 저장 연동

**Files:**
- Modify: `review-moai-refactoring/app/drivers/download/NaverBrandStoreDriver.py:989-1007`
- Modify: `review-moai-refactoring/app/drivers/download/NaverSmartStoreDriver.py:845-863`

- [ ] **Step 1: NaverBrandStoreDriver 수정**

`_send_non_displayed_items_report()` 메서드에서 Slack 전송 전에 DB 일괄 저장 추가:

```python
def _send_non_displayed_items_report(self):
    """진열되지 않은 상품들에 대한 일괄 리포트 전송 및 DB 저장"""
    if not self._non_displayed_items:
        return

    # DB에 일괄 저장
    try:
        from regle.Models.NonDisplayedItem import NonDisplayedItem

        db_items = []
        for item in self._non_displayed_items:
            db_items.append({
                "client_id": self._review_client.id,
                "config_id": item["config_id"],
                "config_name": item["config_name"],
                "driver_code": self._review_driver_config.driver_code,
                "item_code": item["item_code"],
            })
        NonDisplayedItem.bulk_upsert_non_displayed(db_items)
    except Exception as e:
        self.logger.warning(f"진열되지 않은 상품 DB 저장 실패: {e}")

    # config별 그룹핑 (Slack 메시지)
    grouped = {}
    for item in self._non_displayed_items:
        key = (item["config_name"], item["config_id"])
        grouped.setdefault(key, []).append(item["item_code"])

    message = "**네이버 브랜드스토어 진열되지 않은 상품 리포트**\n"
    message += f"**총 {len(self._non_displayed_items)}개 상품 ({len(grouped)}개 설정)**\n\n"

    for (config_name, config_id), item_codes in grouped.items():
        message += f"• {config_name} (ID: {config_id}) — {len(item_codes)}건\n"
        message += f"  item_codes: {', '.join(str(c) for c in item_codes)}\n"

    message += f"\n**수집 시간:** {datetime.datetime.now(timezone('Asia/Seoul')).strftime('%Y-%m-%d %H:%M:%S')}"

    slack_msg(message, channel="regle-errors")
```

- [ ] **Step 2: NaverSmartStoreDriver 동일 수정**

위와 동일한 패턴으로 수정. 메시지 타이틀만 "스마트스토어"로 유지.

- [ ] **Step 3: 커밋**

---

## Task 3: Laravel 마이그레이션

**Files:**
- Create: `SeoulVenturesGroupware/database/migrations/2026_04_02_000001_create_review_non_displayed_items_table.php`

- [ ] **Step 1: 마이그레이션 파일 생성**

```php
<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    protected $connection = 'retaku_admin';

    public function up(): void
    {
        try {
            if (Schema::connection('retaku_admin')->hasTable('review_non_displayed_items')) {
                return;
            }
        } catch (\Throwable $e) {
            if (app()->environment('testing')) {
                logger()->warning('Skip migration in testing: ' . $e->getMessage());
                return;
            }
            throw $e;
        }

        Schema::connection('retaku_admin')->create('review_non_displayed_items', function (Blueprint $table) {
            $table->id();
            $table->unsignedInteger('client_id');
            $table->unsignedInteger('config_id');
            $table->string('config_name');
            $table->string('driver_code', 100);
            $table->string('target_item_code');
            $table->timestamp('detected_at')->useCurrent();
            $table->timestamp('resolved_at')->nullable();
            $table->timestamps();

            $table->unique(['config_id', 'target_item_code'], 'uq_config_item');
            $table->index('client_id');
            $table->index('config_id');
            $table->index('resolved_at');
        });
    }

    public function down(): void
    {
        try {
            Schema::connection('retaku_admin')->dropIfExists('review_non_displayed_items');
        } catch (\Throwable $e) {
            logger()->warning('Rollback skip: ' . $e->getMessage());
        }
    }
};
```

- [ ] **Step 2: 커밋**

---

## Task 4: Laravel Eloquent 모델

**Files:**
- Create: `SeoulVenturesGroupware/app/Models/Review/NonDisplayedItem.php`

- [ ] **Step 1: 모델 생성**

```php
<?php

namespace App\Models\Review;

use Illuminate\Database\Eloquent\Model;

class NonDisplayedItem extends Model
{
    protected $connection = 'retaku_admin';

    protected $table = 'review_non_displayed_items';

    protected $fillable = [
        'client_id',
        'config_id',
        'config_name',
        'driver_code',
        'target_item_code',
        'detected_at',
        'resolved_at',
    ];

    protected $casts = [
        'detected_at' => 'datetime',
        'resolved_at' => 'datetime',
    ];

    public function client()
    {
        return $this->belongsTo(Client::class, 'client_id');
    }

    public function driverConfig()
    {
        return $this->belongsTo(DriverConfig::class, 'config_id');
    }
}
```

- [ ] **Step 2: 커밋**

---

## Task 5: Laravel Service

**Files:**
- Create: `SeoulVenturesGroupware/app/Services/Review/NonDisplayedItemService.php`

- [ ] **Step 1: 서비스 생성**

```php
<?php

namespace App\Services\Review;

use App\Models\Review\Client;
use App\Models\Review\NonDisplayedItem;
use App\Models\Review\TargetItemMap;
use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Http\Request;

class NonDisplayedItemService
{
    public function __construct(
        private ReviewCountManager $reviewCountManager,
    ) {}

    public function getPaginatedList(Client $client, Request $request): LengthAwarePaginator
    {
        $query = NonDisplayedItem::where('client_id', $client->id)
            ->when($request->filled('config_id'), function ($q) use ($request) {
                $q->where('config_id', $request->input('config_id'));
            })
            ->when($request->filled('driver_code'), function ($q) use ($request) {
                $q->where('driver_code', $request->input('driver_code'));
            })
            ->when($request->filled('status'), function ($q) use ($request) {
                if ($request->input('status') === 'unresolved') {
                    $q->whereNull('resolved_at');
                } elseif ($request->input('status') === 'resolved') {
                    $q->whereNotNull('resolved_at');
                }
            })
            ->when($request->filled('search'), function ($q) use ($request) {
                $search = $request->input('search');
                $q->where(function ($q) use ($search) {
                    $q->where('target_item_code', 'like', "%{$search}%")
                      ->orWhere('config_name', 'like', "%{$search}%");
                });
            });

        $sortMap = [
            'detected_at' => 'detected_at',
            'resolved_at' => 'resolved_at',
            'config_name' => 'config_name',
            'target_item_code' => 'target_item_code',
            'created_at' => 'created_at',
        ];

        $sortKey = $sortMap[$request->input('sort')] ?? 'detected_at';
        $sortOrder = $request->input('order', 'desc');

        return $query->orderBy($sortKey, $sortOrder)
            ->paginate($request->input('per_page', 25));
    }

    /**
     * 선택된 진열되지 않은 상품의 매핑을 삭제하고 resolved 처리
     */
    public function deleteSelectedMappings(Client $client, array $nonDisplayedItemIds): array
    {
        $items = NonDisplayedItem::where('client_id', $client->id)
            ->whereIn('id', $nonDisplayedItemIds)
            ->whereNull('resolved_at')
            ->get();

        if ($items->isEmpty()) {
            return ['deleted_mappings' => 0, 'resolved_items' => 0];
        }

        $deletedMappings = 0;
        $configIds = [];

        foreach ($items as $item) {
            $deleted = TargetItemMap::where('config_id', $item->config_id)
                ->where('target_item_code', $item->target_item_code)
                ->delete();

            $deletedMappings += $deleted;
            $configIds[$item->config_id] = true;

            $item->resolved_at = now();
            $item->save();
        }

        // 리뷰 카운트 리셋
        $this->reviewCountManager->resetClientReviewCount($client->id);
        foreach (array_keys($configIds) as $configId) {
            $this->reviewCountManager->resetDriverConfigReviewCount($configId);
        }

        return [
            'deleted_mappings' => $deletedMappings,
            'resolved_items' => $items->count(),
        ];
    }

    /**
     * 해결된 항목 일괄 삭제 (정리용)
     */
    public function deleteResolved(Client $client): int
    {
        return NonDisplayedItem::where('client_id', $client->id)
            ->whereNotNull('resolved_at')
            ->delete();
    }
}
```

- [ ] **Step 2: 커밋**

---

## Task 6: Laravel Resource + Controller + Routes

**Files:**
- Create: `SeoulVenturesGroupware/app/Http/Resources/Review/NonDisplayedItemResource.php`
- Create: `SeoulVenturesGroupware/app/Http/Controllers/Review/NonDisplayedItemController.php`
- Modify: `SeoulVenturesGroupware/routes/api.php`

- [ ] **Step 1: Resource 생성**

```php
<?php

namespace App\Http\Resources\Review;

use Illuminate\Http\Resources\Json\JsonResource;

class NonDisplayedItemResource extends JsonResource
{
    public function toArray($request): array
    {
        return [
            'id' => (int) $this->id,
            'client_id' => (int) $this->client_id,
            'config_id' => (int) $this->config_id,
            'config_name' => $this->config_name,
            'driver_code' => $this->driver_code,
            'target_item_code' => $this->target_item_code,
            'detected_at' => $this->detected_at?->toISOString(),
            'resolved_at' => $this->resolved_at?->toISOString(),
            'created_at' => $this->created_at?->toISOString(),
            'updated_at' => $this->updated_at?->toISOString(),
        ];
    }
}
```

- [ ] **Step 2: Controller 생성**

```php
<?php

namespace App\Http\Controllers\Review;

use App\Http\Controllers\Controller;
use App\Http\Resources\Review\NonDisplayedItemResource;
use App\Models\Review\Client;
use App\Services\Review\NonDisplayedItemService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class NonDisplayedItemController extends Controller
{
    public function __construct(
        private NonDisplayedItemService $nonDisplayedItemService,
    ) {}

    public function index(Client $client, Request $request): JsonResponse
    {
        $paginated = $this->nonDisplayedItemService->getPaginatedList($client, $request);

        return response()->json([
            'success' => true,
            'data' => [
                'data' => NonDisplayedItemResource::collection($paginated->items()),
                'total' => $paginated->total(),
            ],
        ]);
    }

    public function deleteMappings(Client $client, Request $request): JsonResponse
    {
        $request->validate([
            'ids' => ['required', 'array', 'min:1'],
            'ids.*' => ['required', 'integer', 'distinct', 'min:1'],
        ]);

        $result = $this->nonDisplayedItemService->deleteSelectedMappings(
            $client,
            $request->input('ids'),
        );

        return response()->json([
            'success' => true,
            'data' => $result,
        ]);
    }

    public function deleteResolved(Client $client): JsonResponse
    {
        $deleted = $this->nonDisplayedItemService->deleteResolved($client);

        return response()->json([
            'success' => true,
            'data' => ['deleted' => $deleted],
        ]);
    }
}
```

- [ ] **Step 3: 라우트 등록**

`routes/api.php`의 review 그룹 내, TargetItemMap 라우트 아래에 추가:

```php
// Non-Displayed Items (진열되지 않은 상품)
Route::get('clients/{client}/non-displayed-items', [\App\Http\Controllers\Review\NonDisplayedItemController::class, 'index']);
Route::post('clients/{client}/non-displayed-items/delete-mappings', [\App\Http\Controllers\Review\NonDisplayedItemController::class, 'deleteMappings']);
Route::delete('clients/{client}/non-displayed-items/resolved', [\App\Http\Controllers\Review\NonDisplayedItemController::class, 'deleteResolved']);
```

- [ ] **Step 4: 커밋**

---

## Task 7: Vue 프론트엔드 — API 클라이언트

**Files:**
- Create: `SeoulVenturesGroupware/frontend/resources/ts/api/entities/review/nonDisplayedItem.ts`

- [ ] **Step 1: API 클라이언트 생성**

```typescript
import { del, get, post } from '@/api'

export interface NonDisplayedItem {
  id: number
  client_id: number
  config_id: number
  config_name: string
  driver_code: string
  target_item_code: string
  detected_at: string | null
  resolved_at: string | null
  created_at: string | null
  updated_at: string | null
}

export interface NonDisplayedItemListResponse {
  data: NonDisplayedItem[]
  total: number
}

export interface DeleteMappingsResponse {
  deleted_mappings: number
  resolved_items: number
}

export const nonDisplayedItemApi = {
  list: (clientId: number, params: Record<string, string | number>) =>
    get<NonDisplayedItemListResponse>(`/api/review/clients/${clientId}/non-displayed-items`, params),

  deleteMappings: (clientId: number, ids: number[]) =>
    post<DeleteMappingsResponse>(`/api/review/clients/${clientId}/non-displayed-items/delete-mappings`, { ids }),

  deleteResolved: (clientId: number) =>
    del<{ deleted: number }>(`/api/review/clients/${clientId}/non-displayed-items/resolved`),
}
```

- [ ] **Step 2: 커밋**

---

## Task 8: Vue 프론트엔드 — 관리 페이지

**Files:**
- Create: `SeoulVenturesGroupware/frontend/resources/ts/pages/review/non-displayed-items/index.vue`

- [ ] **Step 1: 페이지 컴포넌트 생성**

VDataTableServer 기반 서버사이드 페이징 테이블 페이지. 기능:
- 검색 (상품코드/설정명)
- 상태 필터 (전체/미해결/해결됨)
- 드라이버 필터 (전체/브랜드스토어/스마트스토어)
- 정렬 (감지 시간, 상태, 설정명, 상품코드)
- 체크박스 다중 선택 + 일괄 매핑 삭제
- 개별 매핑 삭제 버튼
- 해결됨 항목 정리 버튼
- 삭제 확인 다이얼로그

(전체 Vue 컴포넌트 코드는 본문 상단 파일 구조 참고)

- [ ] **Step 2: 커밋**

---

## Task 9: 네비게이션 메뉴 추가

**Files:**
- Modify: `SeoulVenturesGroupware/frontend/resources/ts/navigation/vertical/index.ts`

- [ ] **Step 1: reviewManager 배열에 메뉴 항목 추가**

"매핑 관리" 항목(line 84-89) 아래에 추가:

```typescript
{
  title: '진열 안됨 상품',
  icon: { icon: 'tabler-alert-triangle' },
  to: 'review-non-displayed-items',
  action: 'read',
  subject: 'DriverConfig',
},
```

- [ ] **Step 2: 커밋**

---

## Task 10: 마이그레이션 실행 및 통합 확인

- [ ] **Step 1: 프로덕션 DB에 마이그레이션 실행**

- [ ] **Step 2: 프론트엔드 타입체크 및 빌드 확인**

- [ ] **Step 3: API 동작 확인**

수동으로 `review_non_displayed_items` 테이블에 테스트 데이터 삽입 후 API 호출 확인.

- [ ] **Step 4: 최종 커밋 및 PR 생성**

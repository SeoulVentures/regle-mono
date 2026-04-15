# review/data 자사몰 상품명 초기화·강제수집 — 구현 플랜

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development (권장) or superpowers:executing-plans.

**Goal:** SVGW `/review/data` 에 자사몰 상품명 **초기화**·**강제 수집** 버튼 2개 (선택/전체) 추가. `is_name_checked=1` 고착 상품 복구 수단.

**Architecture:** regle 은 `scan_client_items` 에 `flag_force` 파라미터만 추가 (채널용 대칭). SVGW 는 기존 `ReviewScanController` 확장 + 초기화 액션 신규. Dispatch 는 기존 `RegleEcsService` (ECS RunTask) 재사용.

**Spec:** `docs/superpowers/specs/2026-04-15-review-data-item-name-buttons-design.md`

## 검증된 전제 (구현 전 이미 확인)

- **regle CLI 진입점**: `regle/typer_cli/task_cli.py:55 scan_client_items(target_item_maps: str)`
- **regle 스킵 가드**: `app/drivers/BaseUploadDriver.py:494-504` — `item_name` 유효 + `item_url` 있음 + `is_name_checked=True` 일 때 skip
- **SVGW 컨트롤러**: `app/Http/Controllers/ReviewUploader/ReviewScanController.php:34 scanClientItems`
- **SVGW 서비스**: `app/Services/RegleEcsService.php:295 scanClientItems`
- **SVGW `buildArgs`** (L270 부근): bool 처리 **없음** → `--force=1` 을 토해냄. Typer `--force/--no-force` 와 불일치 → **buildArgs 수정 필요** (Task 5)
- **SVGW 테스트 DB 정책**: retaku_admin 외부 RDS, `RefreshDatabase` 미사용. 기존 패턴 → `$this->skipIfDatabaseUnavailable('retaku_admin')` + `DB::connection('retaku_admin')->table()->insert()`. 참고: `tests/Feature/Review/TargetItemMapDeleteBulkAuditTest.php`
- **SVGW factory**: `ClientFactory`, `TargetItemMapFactory` 있음. **`ClientItemFactory` 없음** → DB 직접 insert
- **SVGW 프론트 기존 드롭다운 패턴**: `frontend/resources/ts/pages/review/data/index.vue:1377` 의 `VMenu > VList > VListItem` 구조 복제

---

# Phase A — regle (review-moai-refactoring)

## Task 1: `scan_client_items` 에 `flag_force` 추가

**Files:**
- Modify `app/drivers/BaseUploadDriver.py:473-504`
- Modify `regle/services/review/client_service.py:75-80`
- Modify `regle/typer_cli/task_cli.py:55-63`
- Create `tests/unit/drivers/test_base_upload_scan_force.py`

- [ ] **Step 1: 브랜치**

```bash
cd /opt/SeoulVentures/regle/review-moai-refactoring
git checkout -b feature/scan-client-items-force
```

- [ ] **Step 2: 실패 테스트 작성** — `tests/unit/drivers/test_base_upload_scan_force.py`

```python
"""scan_client_items flag_force 검증."""
from unittest.mock import MagicMock, patch

from app.drivers.BaseUploadDriver import BaseUploadDriver


def _driver(item_name="바닐라코 상품", is_name_checked=True):
    client = MagicMock()
    client.product_url_pattern = "https://example.com/p/{product_id}"
    client.product_scan_type = "head"
    client.review_service = "crema"

    item = MagicMock()
    item.item_name = item_name
    item.is_name_checked = is_name_checked
    item.item_url = "https://example.com/p/1"
    item.item_code = "1"

    map_row = MagicMock()
    map_row.get_review_client_item.return_value = item
    client.get_review_target_item_maps.return_value = [map_row]

    d = BaseUploadDriver.__new__(BaseUploadDriver)
    d._review_client = client
    d._BaseUploadDriver__validate_and_fix_items = MagicMock()
    return d


def _with_mocks(req_status=200):
    redis = patch("app.drivers.BaseUploadDriver.get_redis_conn")
    req = patch("app.drivers.BaseUploadDriver.requests.get")
    return redis, req


def test_default_skips_when_name_checked():
    d = _driver()
    redis_mock, req_mock = _with_mocks()
    with redis_mock as rm, req_mock as qm:
        rm.return_value.__enter__.return_value.exists.return_value = True
        rm.return_value.__enter__.return_value.get.return_value = b"1"
        d.scan_client_items()
        qm.assert_not_called()


def test_force_true_overrides_skip():
    d = _driver()
    redis_mock, req_mock = _with_mocks()
    with redis_mock as rm, req_mock as qm:
        rm.return_value.__enter__.return_value.exists.return_value = True
        rm.return_value.__enter__.return_value.get.return_value = b"1"
        qm.return_value.status_code = 200
        qm.return_value.encoding = "utf-8"
        qm.return_value.apparent_encoding = "utf-8"
        qm.return_value.content = b"<html><head><title>새 상품명</title></head></html>"
        d.scan_client_items(flag_force=True)
        qm.assert_called_once()
```

실행 → 실패 확인:
```bash
.venv/bin/pytest tests/unit/drivers/test_base_upload_scan_force.py -v
```

- [ ] **Step 3: 3개 파일 동시 수정**

**a) `app/drivers/BaseUploadDriver.py:473`** — 시그니처 + 가드 우회 삽입

```python
def scan_client_items(self, target_item_maps: str = None, flag_force: bool = False):
```

기존 가드 블록 끝의 `if not flag_try: continue` 직전에 추가:

```python
                if flag_force:
                    flag_try = True

                if not flag_try:
                    continue
```

**b) `regle/services/review/client_service.py:76`**:

```python
@ToSlackClient("<@{user}> {client_name}의 자사몰 상품명 수집")
def scan_client_items(self, maps=None, flag_force: bool = False):
    upload_driver = self.client.get_upload_drvier()
    if not upload_driver:
        upload_driver = BaseUploadDriver(self.client)
    upload_driver.scan_client_items(maps, flag_force=flag_force)
```

**c) `regle/typer_cli/task_cli.py:55`**:

```python
@app.command()
def scan_client_items(
    id: Annotated[Optional[int], typer.Option()] = None,
    user: Annotated[Optional[str], typer.Option()] = None,
    map_ids: Annotated[Optional[str], typer.Option()] = None,
    force: Annotated[bool, typer.Option("--force/--no-force")] = False,
):
    print(f"상품 스캔을 시작합니다.{id} force={force}")
    ClientService(id, user).scan_client_items(map_ids, flag_force=force)
    print(f"상품 스캔이 완료되었습니다.{id}")
```

- [ ] **Step 4: 테스트 통과 + 회귀 확인**

```bash
.venv/bin/pytest tests/unit/drivers/test_base_upload_scan_force.py -v
.venv/bin/pytest tests/ -q
.venv/bin/ruff check app/drivers/BaseUploadDriver.py regle/ tests/unit/drivers/test_base_upload_scan_force.py --fix
.venv/bin/ruff format app/drivers/BaseUploadDriver.py regle/services/review/client_service.py regle/typer_cli/task_cli.py tests/unit/drivers/test_base_upload_scan_force.py
.venv/bin/python regle_cli.py scan-client-items --help | grep -- "--force"
```

기대: 신규 2 통과, 기존 회귀 없음, `--force/--no-force` 옵션 노출.

- [ ] **Step 5: 커밋 + PR**

```bash
git add app/drivers/BaseUploadDriver.py regle/services/review/client_service.py regle/typer_cli/task_cli.py tests/unit/drivers/test_base_upload_scan_force.py
git commit -m "feat(scan): scan_client_items 에 flag_force 파라미터 추가

채널용 scan_target_titles_by_review_target_item_maps 와 대칭.
default False 로 기존 호출부 동작 불변."
git push -u origin feature/scan-client-items-force

gh pr create --draft \
  --title "feat(scan): scan_client_items 에 flag_force 파라미터 추가" \
  --body "SVGW 의 자사몰 상품명 강제수집 버튼이 의존하는 워커 변경.

- BaseUploadDriver / ClientService / CLI 3계층에 flag_force 전달
- default False → 기존 호출부 (periodic, ConfigService 등) 동작 불변
- CLI: --force/--no-force 옵션 노출

관련 스펙: regle 메인 repo docs/superpowers/specs/2026-04-15-review-data-item-name-buttons-design.md"
```

PR URL 기록해둘 것 (Task 6 PR body 에서 링크).

---

## Phase Gate (regle → SVGW)

사용자 승인 후에만 진행. **자동화 금지.**

- [ ] **Step 1**: regle PR 승인/머지 (외부)
- [ ] **Step 2**: GH Actions 배포 완료 확인
  ```bash
  gh run list --workflow=deploy.yml --limit=3 --repo SeoulVentures/review-moai-refactoring
  ```
- [ ] **Step 3**: ECS 태스크 정의 revision 증가 확인
  ```bash
  aws ecs describe-task-definition --task-definition regle-worker-cli-production \
    --region ap-northeast-2 \
    --query 'taskDefinition.{revision:revision,image:containerDefinitions[0].image}'
  ```
- [ ] **Step 4**: 사용자 Phase B 착수 승인

---

# Phase B — SVGW (SeoulVenturesGroupware)

## Task 2: SVGW 브랜치 + `buildArgs` bool fix + service/controller 변경

**Files:**
- Modify `app/Services/RegleEcsService.php` (buildArgs + scanClientItems)
- Modify `app/Http/Controllers/ReviewUploader/ReviewScanController.php` (scanClientItems)

- [ ] **Step 1: 브랜치**

```bash
cd /opt/SeoulVentures/regle/SeoulVenturesGroupware
git checkout master && git pull
git checkout -b feature/review-data-item-name-reset-force
```

- [ ] **Step 2: `buildArgs` 에 bool 지원 추가**

Edit `app/Services/RegleEcsService.php` — `buildArgs` 메서드 수정:

```php
private function buildArgs(array $params): string
{
    $args = [];
    foreach ($params as $key => $value) {
        if ($value === null || $value === false) {
            continue;
        }
        $key = str_replace('_', '-', $key);
        if ($value === true) {
            $args[] = "--{$key}";
            continue;
        }
        $sanitized = str_replace(' ', '_', (string) $value);
        $args[] = "--{$key}={$sanitized}";
    }
    return implode(' ', $args);
}
```

- [ ] **Step 3: `scanClientItems` 에 `$force` 인자 추가**

Edit `app/Services/RegleEcsService.php:295`:

```php
public function scanClientItems(
    int $clientId,
    ?array $targetItemMaps = null,
    ?string $requestUser = null,
    bool $force = false,
): array {
    return $this->runTask('scan-client-items', [
        'id' => $clientId,
        'user' => $requestUser,
        'map_ids' => $targetItemMaps ? implode(',', $targetItemMaps) : null,
        'force' => $force ?: null,
    ]);
}
```

- [ ] **Step 4: Controller 의 `scanClientItems` 가 `force` 읽도록**

Edit `app/Http/Controllers/ReviewUploader/ReviewScanController.php:62-70`:

```php
        $targetItemMaps = $request->has('target_item_maps')
            ? explode(',', $request->get('target_item_maps'))
            : null;

        $force = filter_var($request->input('force', false), FILTER_VALIDATE_BOOLEAN);

        $result = $this->ecsService->scanClientItems(
            $clientId,
            $targetItemMaps,
            $request->header('X-Request-User'),
            $force,
        );
```

**Note**: 라우트는 기존 GET 유지. `force=true` 는 query string 으로 전달됨 (`GET /scan-client-items?force=true`).

- [ ] **Step 5: 회귀 확인**

```bash
vendor/bin/phpunit --filter="RegleEcsService|ReviewScan" 2>&1 | tail
```

기존 테스트가 있다면 통과, 없다면 no tests run — OK.

- [ ] **Step 6: 커밋**

```bash
git add app/Services/RegleEcsService.php app/Http/Controllers/ReviewUploader/ReviewScanController.php
git commit -m "feat(review-scan): scan-client-items 에 force 파라미터 수용

buildArgs 가 bool true 를 --key 단일 토큰으로 변환하도록 수정.
regle Typer 의 --force/--no-force 와 호환.
force=true query 전달 시 regle 워커에 --force 전달."
```

---

## Task 3: 초기화 API — `resetClientItemNames`

**Files:**
- Modify `app/Http/Controllers/ReviewUploader/ReviewScanController.php` (메서드 추가)
- Modify `routes/api.php` (reset 라우트 등록)
- Create `tests/Feature/Review/ResetClientItemNamesTest.php`

- [ ] **Step 1: 실패 테스트 작성** — `tests/Feature/Review/ResetClientItemNamesTest.php`

기존 `TargetItemMapDeleteBulkAuditTest` 패턴 복제. `Sanctum::actingAs` + `DB::connection('retaku_admin')` 직접 seed/cleanup.

```php
<?php

namespace Tests\Feature\Review;

use App\Models\Review\Client;
use App\Models\User;
use Illuminate\Support\Facades\DB;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class ResetClientItemNamesTest extends TestCase
{
    private function seedItem(int $clientId, string $code, string $name = '바닐라닷컴'): int
    {
        return DB::connection('retaku_admin')->table('review_client_items')->insertGetId([
            'client_id' => $clientId,
            'item_code' => $code,
            'item_name' => $name,
            'is_name_checked' => 1,
            'created_at' => now(),
            'updated_at' => now(),
        ]);
    }

    private function seedMap(int $clientId, string $clientItemCode, int $configId = 1): int
    {
        return DB::connection('retaku_admin')->table('review_target_item_map')->insertGetId([
            'client_id' => $clientId,
            'config_id' => $configId,
            'driver_code' => 'coupang_rocket',
            'target_item_code' => 'T-'.$clientItemCode,
            'client_item_code' => $clientItemCode,
            'created_at' => now(),
            'updated_at' => now(),
        ]);
    }

    private function cleanup(array $itemIds, array $mapIds, int $clientId): void
    {
        DB::connection('retaku_admin')->table('review_target_item_map')->whereIn('id', $mapIds)->delete();
        DB::connection('retaku_admin')->table('review_client_items')->whereIn('id', $itemIds)->delete();
        Client::destroy($clientId);
    }

    public function test_reset_selected_clears_name_and_flag(): void
    {
        $this->skipIfDatabaseUnavailable('retaku_admin');
        Sanctum::actingAs(User::factory()->create(['email' => 'r1-'.uniqid().'@example.com']));

        $client = Client::factory()->create(['name' => '테스트']);
        $itemId = $this->seedItem($client->id, 'c1');
        $mapId = $this->seedMap($client->id, 'c1');

        try {
            $res = $this->postJson("/api/review-uploader/clients/{$client->id}/reset-client-item-names", [
                'map_ids' => [$mapId], 'all' => false,
            ]);
            $res->assertOk()->assertJson(['success' => true, 'reset_count' => 1]);

            $row = DB::connection('retaku_admin')->table('review_client_items')->where('id', $itemId)->first();
            $this->assertNull($row->item_name);
            $this->assertSame(0, (int) $row->is_name_checked);
        } finally {
            $this->cleanup([$itemId], [$mapId], $client->id);
        }
    }

    public function test_reset_all_mode_covers_every_mapped_item(): void
    {
        $this->skipIfDatabaseUnavailable('retaku_admin');
        Sanctum::actingAs(User::factory()->create(['email' => 'r2-'.uniqid().'@example.com']));

        $client = Client::factory()->create(['name' => '테스트']);
        $ids = [$this->seedItem($client->id, 'a'), $this->seedItem($client->id, 'b')];
        $maps = [$this->seedMap($client->id, 'a'), $this->seedMap($client->id, 'b')];

        try {
            $res = $this->postJson("/api/review-uploader/clients/{$client->id}/reset-client-item-names", ['all' => true]);
            $res->assertOk()->assertJson(['reset_count' => 2]);
        } finally {
            $this->cleanup($ids, $maps, $client->id);
        }
    }

    public function test_reset_does_not_touch_other_clients(): void
    {
        $this->skipIfDatabaseUnavailable('retaku_admin');
        Sanctum::actingAs(User::factory()->create(['email' => 'r3-'.uniqid().'@example.com']));

        $own = Client::factory()->create(['name' => '자기']);
        $other = Client::factory()->create(['name' => '남']);
        $otherItem = $this->seedItem($other->id, 'zz', 'keep');
        $otherMap = $this->seedMap($other->id, 'zz');

        try {
            $this->postJson("/api/review-uploader/clients/{$own->id}/reset-client-item-names", ['all' => true])->assertOk();

            $row = DB::connection('retaku_admin')->table('review_client_items')->where('id', $otherItem)->first();
            $this->assertSame('keep', $row->item_name);
            $this->assertSame(1, (int) $row->is_name_checked);
        } finally {
            $this->cleanup([$otherItem], [$otherMap], $other->id);
            Client::destroy($own->id);
        }
    }

    public function test_missing_map_ids_and_all_false_returns_422(): void
    {
        Sanctum::actingAs(User::factory()->create(['email' => 'r4-'.uniqid().'@example.com']));
        $this->postJson('/api/review-uploader/clients/1/reset-client-item-names', ['all' => false])
            ->assertStatus(422);
    }
}
```

실행 → 실패 확인:
```bash
vendor/bin/phpunit --filter=ResetClientItemNamesTest
```

- [ ] **Step 2: Controller 메서드 추가**

Edit `app/Http/Controllers/ReviewUploader/ReviewScanController.php` — use 구문 추가:

```php
use App\Models\Review\ClientItem;
use App\Models\Review\TargetItemMap;
```

클래스 내부에 메서드 추가:

```php
    /**
     * 자사몰 상품명 초기화
     *
     * 선택 매핑 또는 전체 매핑의 연결 자사몰 상품에 대해
     * item_name=NULL, is_name_checked=0 으로 리셋. 수집 트리거 없음.
     */
    public function resetClientItemNames(Request $request, int $clientId): JsonResponse
    {
        $validated = $request->validate([
            'all' => ['required', 'boolean'],
            'map_ids' => ['required_unless:all,true', 'array'],
            'map_ids.*' => ['integer'],
        ]);

        if (!Client::find($clientId)) {
            return response()->json(['success' => false, 'error' => 'Client not found'], 404);
        }

        $mapTable = (new TargetItemMap())->getTable();

        $query = ClientItem::query()
            ->where('client_id', $clientId)
            ->whereIn('item_code', function ($q) use ($mapTable, $clientId, $validated) {
                $q->select('client_item_code')->from($mapTable)->where('client_id', $clientId);
                if (empty($validated['all'])) {
                    $q->whereIn('id', $validated['map_ids']);
                }
            });

        $total = 0;
        $query->chunkById(1000, function ($items) use (&$total) {
            $ids = $items->pluck('id')->all();
            $total += ClientItem::whereIn('id', $ids)->update([
                'item_name' => null,
                'is_name_checked' => 0,
            ]);
        });

        return response()->json(['success' => true, 'reset_count' => $total]);
    }
```

- [ ] **Step 3: 라우트 등록**

Edit `routes/api.php` — 기존 `scan-client-items` 라우트 (`:402` 및 `:255` 구간) 직후에 각각 추가:

```php
Route::post('review-uploader/clients/{clientId}/reset-client-item-names', [ReviewScanController::class, 'resetClientItemNames']);
```

- [ ] **Step 4: 테스트 통과 + 커밋**

```bash
vendor/bin/phpunit --filter=ResetClientItemNamesTest
git add app/Http/Controllers/ReviewUploader/ReviewScanController.php routes/api.php tests/Feature/Review/ResetClientItemNamesTest.php
git commit -m "feat(review-scan): 자사몰 상품명 초기화 API 추가

POST /review-uploader/clients/{id}/reset-client-item-names
client_id scope 에서 item_name=NULL, is_name_checked=0 리셋.
chunkById(1000) 로 대량 처리, 다른 클라이언트 영향 없음."
```

---

## Task 4: 프론트엔드 — API 엔티티 + 버튼

**Files:**
- Modify `frontend/resources/ts/api/entities/review/clientItems.ts`
- Modify `frontend/resources/ts/pages/review/data/index.vue` (L540-594 부근 핸들러, L1377 부근 template)

- [ ] **Step 1: clientItems.ts 확장**

Edit `frontend/resources/ts/api/entities/review/clientItems.ts` 전체 교체:

```typescript
import { type ApiResponse, get, post } from '@/api'

export interface ClientItem {
  id: number
  client_id: number
  item_code: string | null
  item_name: string | null
  item_url: string | null
  created_at: string | null
  updated_at: string | null
}

export const clientItemsApi = {
  resolveProductNames: (clientId: number | string, opts?: { force?: boolean }): Promise<ApiResponse> =>
    get(`/review-uploader/clients/${clientId}/scan-client-items`, opts?.force ? { force: 'true' } : undefined),

  resolveProductNamesByTargetItemMapIds: (
    clientId: number | string,
    targetItemMapIds: number[],
    opts?: { force?: boolean },
  ): Promise<ApiResponse> =>
    get(`/review-uploader/clients/${clientId}/scan-client-items`, {
      target_item_maps: targetItemMapIds.join(','),
      ...(opts?.force ? { force: 'true' } : {}),
    }),

  resetProductNames: (clientId: number | string): Promise<ApiResponse> =>
    post(`/review-uploader/clients/${clientId}/reset-client-item-names`, { all: true }),

  resetProductNamesByTargetItemMapIds: (
    clientId: number | string,
    targetItemMapIds: number[],
  ): Promise<ApiResponse> =>
    post(`/review-uploader/clients/${clientId}/reset-client-item-names`, {
      all: false,
      map_ids: targetItemMapIds,
    }),
}

export default clientItemsApi
```

- [ ] **Step 2: index.vue 핸들러 4개 추가**

Edit `index.vue` L594 (`resolveClientProductNamesForMappings` 끝) 직후:

```typescript
// 자사몰 상품명 초기화 - 전체
const resetClientProductNames = () => {
  if (!selectedClient.value?.id) return
  showConfirm('전체 매핑의 자사몰 상품명을 초기화하시겠습니까? (item_name=NULL, is_name_checked=0)', async () => {
    try {
      const { success, reset_count } = await clientItemsApi.resetProductNames(selectedClient.value!.id)
      if (success) snackbar.success(`자사몰 상품명 ${reset_count}건 초기화됨.`)
      else snackbar.error('자사몰 상품명 초기화에 실패했습니다.')
    } catch (error) {
      handleError(error, { notificationMessage: '자사몰 상품명 초기화에 실패했습니다.' })
    }
  })
}

// 자사몰 상품명 초기화 - 선택된 매핑
const resetClientProductNamesForMappings = () => {
  if (!selectedClient.value?.id || selectedMappings.value.length === 0) return
  showConfirm(`선택된 ${selectedMappings.value.length}건 매핑의 자사몰 상품명을 초기화하시겠습니까?`, async () => {
    try {
      const mappingIds = selectedMappings.value.map(m => m.id)
      const { success, reset_count } = await clientItemsApi.resetProductNamesByTargetItemMapIds(selectedClient.value!.id, mappingIds)
      if (success) snackbar.success(`자사몰 상품명 ${reset_count}건 초기화됨.`)
      else snackbar.error('자사몰 상품명 초기화에 실패했습니다.')
    } catch (error) {
      handleError(error, { notificationMessage: '자사몰 상품명 초기화에 실패했습니다.' })
    }
  })
}

// 자사몰 상품명 강제 수집 - 전체
const forceResolveClientProductNames = () => {
  if (!selectedClient.value?.id) return
  showConfirm('전체 매핑의 자사몰 상품명 강제 수집을 요청하시겠습니까? (기존 값 덮어씀)', async () => {
    try {
      const { success } = await clientItemsApi.resolveProductNames(selectedClient.value!.id, { force: true })
      if (success) snackbar.success('자사몰 상품명 강제 수집이 요청되었습니다. 완료 시 슬랙으로 알려드립니다.')
      else snackbar.error('자사몰 상품명 강제 수집 요청에 실패했습니다.')
    } catch (error) {
      handleError(error, { notificationMessage: MSG_PRODUCT_NAME_COLLECT_FAILED })
    }
  })
}

// 자사몰 상품명 강제 수집 - 선택된 매핑
const forceResolveClientProductNamesForMappings = () => {
  if (!selectedClient.value?.id || selectedMappings.value.length === 0) return
  showConfirm(`선택된 ${selectedMappings.value.length}건 매핑의 자사몰 상품명 강제 수집을 요청하시겠습니까? (기존 값 덮어씀)`, async () => {
    try {
      const mappingIds = selectedMappings.value.map(m => m.id)
      const { success } = await clientItemsApi.resolveProductNamesByTargetItemMapIds(selectedClient.value!.id, mappingIds, { force: true })
      if (success) snackbar.success('선택된 매핑의 자사몰 상품명 강제 수집이 요청되었습니다.')
      else snackbar.error('자사몰 상품명 강제 수집 요청에 실패했습니다.')
    } catch (error) {
      handleError(error, { notificationMessage: MSG_PRODUCT_NAME_COLLECT_FAILED })
    }
  })
}
```

- [ ] **Step 3: 템플릿 버튼 추가** — `index.vue:1377` 근처의 기존 `<VListItem @click="resolveClientProductNames">` 가 포함된 `VMenu` 를 확인 후, 동일 툴바 그룹에 신규 `VMenu` 2개 삽입. 예:

```vue
<!-- 기존 '자사몰 상품명 수집' VMenu 옆에 추가 -->

<VMenu>
  <template #activator="{ props: activatorProps }">
    <VBtn v-bind="activatorProps" variant="outlined" prepend-icon="mdi-restore" :disabled="!selectedClient">
      자사몰 상품명 초기화
    </VBtn>
  </template>
  <VList>
    <VListItem :disabled="selectedMappings.length === 0" @click="resetClientProductNamesForMappings">
      <VListItemTitle>선택된 {{ selectedMappings.length }}건</VListItemTitle>
    </VListItem>
    <VListItem @click="resetClientProductNames">
      <VListItemTitle>전체 매핑</VListItemTitle>
    </VListItem>
  </VList>
</VMenu>

<VMenu>
  <template #activator="{ props: activatorProps }">
    <VBtn v-bind="activatorProps" variant="outlined" color="warning" prepend-icon="mdi-reload-alert" :disabled="!selectedClient">
      자사몰 상품명 강제 수집
    </VBtn>
  </template>
  <VList>
    <VListItem :disabled="selectedMappings.length === 0" @click="forceResolveClientProductNamesForMappings">
      <VListItemTitle>선택된 {{ selectedMappings.length }}건</VListItemTitle>
    </VListItem>
    <VListItem @click="forceResolveClientProductNames">
      <VListItemTitle>전체 매핑</VListItemTitle>
    </VListItem>
  </VList>
</VMenu>
```

- [ ] **Step 4: 린트/타입/스모크 + 커밋**

```bash
cd frontend
bun run typecheck && bun run lint
bun run dev  # 별도 터미널 — 브라우저에서 버튼 4경로 동작 확인
```

스모크 체크리스트:
- 클라이언트 미선택 시 두 신규 버튼 disabled
- 체크박스 0건 시 "선택된 N건" disabled
- 각 경로 클릭 → confirm dialog → snackbar 정상

```bash
cd ..
git add frontend/resources/ts/api/entities/review/clientItems.ts frontend/resources/ts/pages/review/data/index.vue
git commit -m "feat(review-data): 자사몰 상품명 초기화·강제수집 버튼 추가

선택/전체 모드 드롭다운. 초기화=DB 리셋, 강제수집=force=true 로
is_name_checked 우회."
```

---

## Task 5: SVGW PR 생성

- [ ] **Step 1: 전체 테스트 + 푸시**

```bash
vendor/bin/phpunit --filter="Review"
git push -u origin feature/review-data-item-name-reset-force
```

- [ ] **Step 2: Draft PR**

```bash
gh pr create --draft \
  --title "feat(review-data): 자사몰 상품명 초기화·강제수집 버튼 추가" \
  --body "## Summary
- /review/data 에 버튼 2개: 자사몰 상품명 초기화 / 강제 수집 (선택·전체 드롭다운)
- 초기화: item_name=NULL, is_name_checked=0 리셋만
- 강제 수집: 기존 scan-client-items 에 force=true → regle 워커 --force

## Depends on
- regle PR: <Task 1 Step 5 에서 기록한 URL>
- regle 이 먼저 prod 배포되어야 --force 실효 (구버전은 unknown option 거부 가능)

## Spec
regle 메인 repo docs/superpowers/specs/2026-04-15-review-data-item-name-buttons-design.md

## 변경
- RegleEcsService: buildArgs bool 지원 + scanClientItems(\$force)
- ReviewScanController: scanClientItems query force + resetClientItemNames 신규
- routes: reset 라우트 POST 등록 (2 구간)
- frontend clientItemsApi: force 옵션 + reset 메서드
- index.vue: 핸들러 4개 + 드롭다운 VMenu 2개

## Test plan
- [x] ResetClientItemNamesTest (4 cases)
- [x] 기존 phpunit 회귀
- [x] 프론트 typecheck + lint
- [ ] staging 스모크 (바닐라코 1538 / item_code=1177 시나리오)

## 배포
1. regle PR 머지 → ECS 이미지 빌드 (revision 증가 확인)
2. 이 PR ready → 머지
3. gh release create --target \"\$(git ls-remote <repo> refs/heads/master | awk '{print \$1}')\" v<x.y.z>
4. git ls-remote <repo> refs/tags/v<x.y.z> 로 SHA 일치 확인"
```

---

## Task 6: Staging 검증 (사용자 승인 후)

- [ ] PR 머지 + 배포 완료 확인
- [ ] `/review/data` 에서 바닐라코 선택 → item_code=1177 매핑 체크 → 초기화 → DB 에서 `item_name=NULL, is_name_checked=0` 직접 쿼리로 확인
- [ ] 강제 수집 → CloudWatch `/ecs/regle-worker-cli-production` 에서 `force=True` 로그 확인 → 5-10분 후 DB 재확인
- [ ] 메모리 업데이트 (`memory/MEMORY.md` 에 한 줄)

---

## Follow-up (플랜 범위 외, 별도 이슈)

- review-moai: `review_clients.product_url_pattern` vs 실제 `item_url` 형식 불일치 검증 (바닐라코 루트 원인)
- review-moai: 올리브영 403 우회
- SVGW: `review_clients.upload_driver_config` / `Authorization` NULL 감지 & 알림

---

## Self-Review 체크리스트

- [ ] 스펙 4개 축 (초기화·강제수집 × 선택·전체) 모두 Task 매핑
- [ ] regle `flag_force` default False → 기존 호출부 회귀 없음 (Task 1 Step 4)
- [ ] SVGW 기존 `resolveProductNames` (GET 1-인자) 호출부 호환 — `opts` optional
- [ ] `(new Model())->getTable()` + `chunkById` (Task 3 Step 2)
- [ ] Client scope 격리 테스트 (Task 3 Step 1 `test_reset_does_not_touch_other_clients`)
- [ ] gh release SHA 명시 (Task 5 Step 2 PR body)
- [ ] Phase Gate 로 regle → SVGW 배포 순서 강제

# sv-nova-master 마이그레이션 Phase 5 구현 계획

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** sv-nova-master Nova의 드라이버/클라이언트 핵심 운영 액션들을 SVGW REST API + 프론트엔드 액션 버튼으로 이관한다.

**Architecture:** DriverConfigActionController와 ClientActionController를 신규 추가하고, 기존 드라이버/클라이언트 상세 페이지에 액션 버튼 그룹을 추가한다. 복잡한 Excel 내보내기(ImWebExcel)는 Queue Job으로 처리한다.

**Tech Stack:** Laravel 12, PHP 8.4, Vue 3 + TypeScript + Vuetify 3, Bun, retaku_admin DB (DriverConfig/Target), sv_nova DB, MongoDB (ImWeb Excel)

---

## 참고 파일

| 역할 | 경로 |
|------|------|
| sv-nova-master 원본 액션들 | `sv-nova-master/app/Nova/Actions/` |
| SVGW ECS 서비스 | `SeoulVenturesGroupware/app/Services/RegleEcsService.php` |
| SVGW DriverConfig 모델 | `SeoulVenturesGroupware/app/Models/Review/DriverConfig.php` |
| SVGW Target 모델 | `SeoulVenturesGroupware/app/Models/Review/Target.php` |
| SVGW TargetItemMap 모델 | `SeoulVenturesGroupware/app/Models/Review/TargetItemMap.php` |
| SVGW 라우트 패턴 | `SeoulVenturesGroupware/routes/api.php` |
| 기존 컨트롤러 패턴 | `SeoulVenturesGroupware/app/Http/Controllers/Review/DriverConfigController.php` |
| 기존 collect-reviews 라우트 | `SeoulVenturesGroupware/routes/api.php:209` |

## 엣지 케이스

- `ClearLastCrawledDate`: Target의 `target_option` JSON에서 `last_crawled_date` 키 제거 + DriverConfig의 `driver_config` JSON에서도 제거. 트랜잭션으로 처리. chunk(50)으로 메모리 보호.
- `UnlockSoldoutAction`: DriverConfig 선택 시 → 해당 DriverConfig의 모든 Target에서 `target_option.status == 'not_for_sale'` 제거. DriverConfig 자체의 target_option도 확인.
- `BulkDeleteZzExpressFromDriverConfig`: fulfillment_type이 `zz_express`인 Target + 연관 TargetItemMap 삭제. 트랜잭션.
- `BulkUpdateMonthlyState`: 선택된 Client들의 `monthly_state` 변경 + `update_drivers: true`이면 연관 DriverConfig도 함께 변경.
- `RunPeriodicEcsTask` / `RunWidgetEcsTask`: SVGW RegleEcsService에 해당 메서드 없음 → 추가 필요. ECS 커맨드: `process-periodic`, `process-widget`.
- `collectReviewsByDriverConfig`: 이미 `GET /driver-configs/{id}/collect-reviews` 라우트 존재 → 재활용.
- `ImWebExcelAction`: MongoDB에서 리뷰+이미지 다운로드 후 Excel 생성 → 시간이 오래 걸려 Queue Job으로 처리.
- `UpdateReviewUploadReportAction` / `ClearUploadReadyState`: MongoDB `review_upload_target_list` 컬렉션 접근 필요. MongoDBConnection 서비스 사용.

---

## Task 1: RegleEcsService에 runPeriodicTask / runWidgetTask 추가

**Files:**
- Modify: `SeoulVenturesGroupware/app/Services/RegleEcsService.php`
- Create: `SeoulVenturesGroupware/tests/Unit/Services/RegleEcsServicePeriodicTest.php`

**Step 1: 테스트 작성**

```php
<?php

namespace Tests\Unit\Services;

use App\Services\RegleEcsService;
use Tests\TestCase;
use Mockery;

class RegleEcsServicePeriodicTest extends TestCase
{
    public function test_run_periodic_task_calls_run_task_with_correct_params(): void
    {
        $service = Mockery::mock(RegleEcsService::class)->makePartial();
        $service->shouldReceive('runTask')
            ->once()
            ->with('process-periodic', ['config_id' => 42], null)
            ->andReturn(['status' => 'running', 'task_id' => 'task-abc']);

        $result = $service->runPeriodicTask(42);
        $this->assertEquals('running', $result['status']);
    }

    public function test_run_widget_task_calls_run_task_with_correct_params(): void
    {
        $service = Mockery::mock(RegleEcsService::class)->makePartial();
        $service->shouldReceive('runTask')
            ->once()
            ->with('process-widget', ['config_id' => 99], null)
            ->andReturn(['status' => 'running', 'task_id' => 'task-xyz']);

        $result = $service->runWidgetTask(99);
        $this->assertEquals('running', $result['status']);
    }

    public function test_run_periodic_task_throws_on_invalid_config_id(): void
    {
        $service = new RegleEcsService();
        $this->expectException(\InvalidArgumentException::class);
        $service->runPeriodicTask(0);
    }

    public function test_run_widget_task_throws_on_invalid_config_id(): void
    {
        $service = new RegleEcsService();
        $this->expectException(\InvalidArgumentException::class);
        $service->runWidgetTask(0);
    }
}
```

**Step 2: 테스트 실행 (실패 확인)**

```bash
cd SeoulVenturesGroupware && vendor/bin/phpunit tests/Unit/Services/RegleEcsServicePeriodicTest.php --no-coverage
```
Expected: FAIL - "Method runPeriodicTask not found"

**Step 3: RegleEcsService 말미에 메서드 추가**

`RegleEcsService.php`의 마지막 `}` 직전에 추가:

```php
    public function runPeriodicTask(int $driverConfigId): array
    {
        if ($driverConfigId <= 0) {
            throw new \InvalidArgumentException("Invalid driver config ID: {$driverConfigId}");
        }

        return $this->runTask('process-periodic', ['config_id' => $driverConfigId]);
    }

    public function runWidgetTask(int $driverConfigId): array
    {
        if ($driverConfigId <= 0) {
            throw new \InvalidArgumentException("Invalid driver config ID: {$driverConfigId}");
        }

        return $this->runTask('process-widget', ['config_id' => $driverConfigId]);
    }
```

**Step 4: 테스트 실행 (통과 확인)**

```bash
cd SeoulVenturesGroupware && vendor/bin/phpunit tests/Unit/Services/RegleEcsServicePeriodicTest.php --no-coverage
```
Expected: 4 tests PASS

**Step 5: 커밋**

```bash
cd SeoulVenturesGroupware && git add app/Services/RegleEcsService.php tests/Unit/Services/RegleEcsServicePeriodicTest.php
git commit -m "feat(phase5): RegleEcsService에 runPeriodicTask/runWidgetTask 추가"
```

---

## Task 2: DriverConfigActionController

**Files:**
- Create: `SeoulVenturesGroupware/app/Http/Controllers/Review/DriverConfigActionController.php`
- Create: `SeoulVenturesGroupware/tests/Feature/Review/DriverConfigActionControllerTest.php`

**컨텍스트:**
- DriverConfig: `retaku_admin` DB, `review_driver_configs` 테이블
- Target: `retaku_admin` DB, `review_targets` 테이블, `target_option` JSON cast
- TargetItemMap: `retaku_admin` DB
- 라우트 바인딩: `{driverConfig}` → `App\Models\Review\DriverConfig`

**Step 1: 테스트 작성**

```php
<?php

namespace Tests\Feature\Review;

use Tests\TestCase;

class DriverConfigActionControllerTest extends TestCase
{
    public function test_clear_last_crawled_date_requires_auth(): void
    {
        $response = $this->postJson('/api/review/driver-configs/1/actions/clear-last-crawled-date');
        $response->assertStatus(401);
    }

    public function test_run_periodic_ecs_requires_auth(): void
    {
        $response = $this->postJson('/api/review/driver-configs/1/actions/run-periodic-ecs');
        $response->assertStatus(401);
    }

    public function test_run_widget_ecs_requires_auth(): void
    {
        $response = $this->postJson('/api/review/driver-configs/1/actions/run-widget-ecs');
        $response->assertStatus(401);
    }

    public function test_unlock_soldout_requires_auth(): void
    {
        $response = $this->postJson('/api/review/driver-configs/1/actions/unlock-soldout');
        $response->assertStatus(401);
    }

    public function test_delete_zz_express_requires_auth(): void
    {
        $response = $this->postJson('/api/review/driver-configs/1/actions/delete-zz-express');
        $response->assertStatus(401);
    }

    public function test_update_last_crawled_date_requires_auth(): void
    {
        $response = $this->postJson('/api/review/driver-configs/1/actions/update-last-crawled-date');
        $response->assertStatus(401);
    }
}
```

**Step 2: 테스트 실행 (실패 확인)**

```bash
cd SeoulVenturesGroupware && vendor/bin/phpunit tests/Feature/Review/DriverConfigActionControllerTest.php --no-coverage
```
Expected: FAIL - 404 (라우트 없음)

**Step 3: 컨트롤러 구현**

```php
<?php

namespace App\Http\Controllers\Review;

use App\Http\Controllers\Controller;
use App\Models\Review\DriverConfig;
use App\Models\Review\Target;
use App\Models\Review\TargetItemMap;
use App\Services\RegleEcsService;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

class DriverConfigActionController extends Controller
{
    public function __construct(private RegleEcsService $ecsService) {}

    /**
     * Target의 last_crawled_date 초기화 (target_option JSON + driver_config JSON)
     */
    public function clearLastCrawledDate(DriverConfig $driverConfig): JsonResponse
    {
        $totalTargets = 0;

        DB::connection('retaku_admin')->transaction(function () use ($driverConfig, &$totalTargets) {
            $driverConfig->targets()->chunk(50, function ($targets) use (&$totalTargets) {
                foreach ($targets as $target) {
                    $option = $target->target_option ?? [];
                    if (isset($option['last_crawled_date'])) {
                        unset($option['last_crawled_date']);
                        $target->target_option = $option;
                        $target->save();
                        $totalTargets++;
                    }
                }
            });

            $driverConfigJson = $driverConfig->driver_config ?? [];
            if (isset($driverConfigJson['last_crawled_date'])) {
                unset($driverConfigJson['last_crawled_date']);
                $driverConfig->driver_config = $driverConfigJson;
                $driverConfig->save();
            }
        });

        return response()->json([
            'message' => "last_crawled_date 초기화 완료",
            'cleared_targets' => $totalTargets,
        ]);
    }

    /**
     * 정기 이관 ECS 태스크 강제 실행
     */
    public function runPeriodicEcs(DriverConfig $driverConfig): JsonResponse
    {
        try {
            $result = $this->ecsService->runPeriodicTask($driverConfig->id);
            return response()->json(['message' => '정기 이관 ECS 태스크가 실행되었습니다.', 'result' => $result]);
        } catch (\Throwable $e) {
            Log::error('DriverConfigActionController: runPeriodicEcs 실패', ['id' => $driverConfig->id, 'error' => $e->getMessage()]);
            return response()->json(['message' => $e->getMessage()], 422);
        }
    }

    /**
     * 위젯 처리 ECS 태스크 강제 실행
     */
    public function runWidgetEcs(DriverConfig $driverConfig): JsonResponse
    {
        try {
            $result = $this->ecsService->runWidgetTask($driverConfig->id);
            return response()->json(['message' => '위젯 ECS 태스크가 실행되었습니다.', 'result' => $result]);
        } catch (\Throwable $e) {
            Log::error('DriverConfigActionController: runWidgetEcs 실패', ['id' => $driverConfig->id, 'error' => $e->getMessage()]);
            return response()->json(['message' => $e->getMessage()], 422);
        }
    }

    /**
     * 품절(not_for_sale) 상태 해제
     */
    public function unlockSoldout(DriverConfig $driverConfig): JsonResponse
    {
        $unlockedCount = 0;

        DB::connection('retaku_admin')->transaction(function () use ($driverConfig, &$unlockedCount) {
            $driverConfig->targets()->chunk(50, function ($targets) use (&$unlockedCount) {
                foreach ($targets as $target) {
                    $option = $target->target_option ?? [];
                    if (($option['status'] ?? null) === 'not_for_sale') {
                        unset($option['status']);
                        $target->target_option = $option;
                        $target->save();
                        $unlockedCount++;
                    }
                }
            });

            $option = $driverConfig->target_option ?? [];
            if (($option['status'] ?? null) === 'not_for_sale') {
                unset($option['status']);
                $driverConfig->target_option = $option;
                $driverConfig->save();
            }
        });

        return response()->json(['message' => "품절 상태 해제 완료", 'unlocked_count' => $unlockedCount]);
    }

    /**
     * Zigzag 직진배송(zz_express) Target + TargetItemMap 일괄 삭제
     */
    public function deleteZzExpress(DriverConfig $driverConfig): JsonResponse
    {
        $deletedCount = 0;

        DB::connection('retaku_admin')->transaction(function () use ($driverConfig, &$deletedCount) {
            $driverConfig->targets()
                ->where('fulfillment_type', 'zz_express')
                ->chunk(50, function ($targets) use (&$deletedCount) {
                    foreach ($targets as $target) {
                        TargetItemMap::where('target_id', $target->id)->delete();
                        $target->delete();
                        $deletedCount++;
                    }
                });
        });

        return response()->json(['message' => "직진배송 Target 삭제 완료", 'deleted_count' => $deletedCount]);
    }

    /**
     * Target 중 최신 last_crawled_date를 DriverConfig driver_config JSON에 기록
     */
    public function updateLastCrawledDate(DriverConfig $driverConfig): JsonResponse
    {
        $latestDate = null;

        $driverConfig->targets()
            ->get(['target_option'])
            ->each(function ($target) use (&$latestDate) {
                $date = $target->target_option['last_crawled_date'] ?? null;
                if ($date && (!$latestDate || $date > $latestDate)) {
                    $latestDate = $date;
                }
            });

        if ($latestDate) {
            $driverConfigJson = $driverConfig->driver_config ?? [];
            $driverConfigJson['last_crawled_date'] = $latestDate;
            $driverConfig->driver_config = $driverConfigJson;
            $driverConfig->save();
        }

        return response()->json([
            'message' => '최신 크롤링 날짜 업데이트 완료',
            'last_crawled_date' => $latestDate,
        ]);
    }
}
```

**Step 4: 라우트 추가**

`routes/api.php`에서 인증된 review 라우트 그룹 내 driver-configs 라우트 근처에 추가:

```php
// DriverConfig 운영 액션 (Phase 5)
Route::prefix('review/driver-configs/{driverConfig}/actions')->group(function () {
    Route::post('clear-last-crawled-date', [\App\Http\Controllers\Review\DriverConfigActionController::class, 'clearLastCrawledDate']);
    Route::post('run-periodic-ecs', [\App\Http\Controllers\Review\DriverConfigActionController::class, 'runPeriodicEcs']);
    Route::post('run-widget-ecs', [\App\Http\Controllers\Review\DriverConfigActionController::class, 'runWidgetEcs']);
    Route::post('unlock-soldout', [\App\Http\Controllers\Review\DriverConfigActionController::class, 'unlockSoldout']);
    Route::post('delete-zz-express', [\App\Http\Controllers\Review\DriverConfigActionController::class, 'deleteZzExpress']);
    Route::post('update-last-crawled-date', [\App\Http\Controllers\Review\DriverConfigActionController::class, 'updateLastCrawledDate']);
});
```

> `routes/api.php`를 직접 읽어 인증 미들웨어 그룹 안에 올바르게 배치할 것.

**Step 5: 테스트 실행 (통과 확인)**

```bash
cd SeoulVenturesGroupware && vendor/bin/phpunit tests/Feature/Review/DriverConfigActionControllerTest.php --no-coverage
```
Expected: 6 tests PASS (모두 401)

**Step 6: 전체 테스트 확인**

```bash
cd SeoulVenturesGroupware && vendor/bin/phpunit --no-coverage 2>&1 | tail -5
```
Expected: 기존 테스트 모두 PASS

**Step 7: 커밋**

```bash
cd SeoulVenturesGroupware && git add app/Http/Controllers/Review/DriverConfigActionController.php routes/api.php tests/Feature/Review/DriverConfigActionControllerTest.php
git commit -m "feat(phase5): DriverConfigActionController 추가 (clear-last-crawled-date, ECS 실행, unlock-soldout 등)"
```

---

## Task 3: ClientActionController

**Files:**
- Create: `SeoulVenturesGroupware/app/Http/Controllers/Review/ClientActionController.php`
- Create: `SeoulVenturesGroupware/tests/Feature/Review/ClientActionControllerTest.php`

**컨텍스트:**
- Client: `retaku_admin` DB
- `BulkUpdateMonthlyState`: 복수 client id 받아서 일괄 업데이트, `update_drivers: bool`
- `UpdateReviewUploadReportAction`: MongoDB `review_upload_target_list`에서 finished/failed/ready 카운트 집계 → `ReviewUploadReport` 모델 갱신
- `ClearUploadReadyState`: MongoDB에서 state='ready' 문서 삭제 후 집계 갱신
- `ReviewUploadReport` 모델이 SVGW에 있는지 확인 필요 (`/review/upload-summary`에서 사용)

**Step 1: 테스트 작성**

```php
<?php

namespace Tests\Feature\Review;

use Tests\TestCase;

class ClientActionControllerTest extends TestCase
{
    public function test_bulk_update_monthly_state_requires_auth(): void
    {
        $response = $this->postJson('/api/review/clients/actions/bulk-update-monthly-state');
        $response->assertStatus(401);
    }

    public function test_update_upload_report_requires_auth(): void
    {
        $response = $this->postJson('/api/review/clients/1/actions/update-upload-report');
        $response->assertStatus(401);
    }

    public function test_clear_upload_ready_state_requires_auth(): void
    {
        $response = $this->postJson('/api/review/clients/1/actions/clear-upload-ready-state');
        $response->assertStatus(401);
    }
}
```

**Step 2: 테스트 실행 (실패 확인)**

```bash
cd SeoulVenturesGroupware && vendor/bin/phpunit tests/Feature/Review/ClientActionControllerTest.php --no-coverage
```
Expected: FAIL - 404

**Step 3: ReviewUploadReport 모델 확인**

`SeoulVenturesGroupware/app/Models/Review/` 또는 `app/Models/`에서 `ReviewUploadReport` 모델을 찾아 connection과 테이블명 확인. 없으면 `app/Models/Review/ReviewUploadReport.php` 신규 생성:

```php
<?php

namespace App\Models\Review;

use Illuminate\Database\Eloquent\Model;

class ReviewUploadReport extends Model
{
    protected $connection = 'sv_nova';
    protected $table = 'review_upload_reports';

    protected $fillable = ['client_id', 'total_count', 'ready_count', 'finished_count', 'failed_count'];
}
```

**Step 4: 컨트롤러 구현**

```php
<?php

namespace App\Http\Controllers\Review;

use App\Http\Controllers\Controller;
use App\Models\Review\Client;
use App\Models\Review\DriverConfig;
use App\Models\Review\ReviewUploadReport;
use App\Services\MongoDB\MongoDBConnection;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;

class ClientActionController extends Controller
{
    /**
     * 복수 클라이언트의 monthly_state 일괄 변경
     * Body: { ids: number[], state: 'Y'|'N', update_drivers: bool }
     */
    public function bulkUpdateMonthlyState(Request $request): JsonResponse
    {
        $request->validate([
            'ids' => ['required', 'array', 'min:1'],
            'ids.*' => ['integer'],
            'state' => ['required', 'in:Y,N'],
            'update_drivers' => ['boolean'],
        ]);

        $ids = $request->input('ids');
        $state = $request->input('state');
        $updateDrivers = $request->boolean('update_drivers', false);

        $updated = 0;
        $failed = 0;

        Client::whereIn('id', $ids)->chunk(50, function ($clients) use ($state, $updateDrivers, &$updated, &$failed) {
            foreach ($clients as $client) {
                try {
                    $client->monthly_state = $state;
                    $client->save();

                    if ($updateDrivers) {
                        DriverConfig::where('client_id', $client->id)->update(['monthly_state' => $state]);
                    }
                    $updated++;
                } catch (\Throwable $e) {
                    Log::error('bulkUpdateMonthlyState 실패', ['client_id' => $client->id, 'error' => $e->getMessage()]);
                    $failed++;
                }
            }
        });

        return response()->json([
            'message' => "monthly_state 일괄 변경 완료",
            'updated' => $updated,
            'failed' => $failed,
        ]);
    }

    /**
     * MongoDB review_upload_target_list 상태 재집계 → ReviewUploadReport 갱신
     */
    public function updateUploadReport(Client $client): JsonResponse
    {
        try {
            $mongoConnection = app(MongoDBConnection::class);
            $conn = $mongoConnection->getConnectionFor($client);
            $collection = $conn->collection('review_upload_target_list');

            $counts = [
                'total_count'    => $collection->count(),
                'finished_count' => $collection->where('state', 'finished')->count(),
                'failed_count'   => $collection->where('state', 'failed')->count(),
                'ready_count'    => $collection->where('state', 'ready')->count(),
            ];

            ReviewUploadReport::updateOrCreate(
                ['client_id' => $client->id],
                $counts
            );

            return response()->json(['message' => '업로드 리포트 갱신 완료', 'counts' => $counts]);
        } catch (\Throwable $e) {
            Log::error('updateUploadReport 실패', ['client_id' => $client->id, 'error' => $e->getMessage()]);
            return response()->json(['message' => $e->getMessage()], 422);
        }
    }

    /**
     * MongoDB review_upload_target_list에서 state='ready' 문서 삭제 후 집계 갱신
     */
    public function clearUploadReadyState(Client $client): JsonResponse
    {
        try {
            $mongoConnection = app(MongoDBConnection::class);
            $conn = $mongoConnection->getConnectionFor($client);
            $collection = $conn->collection('review_upload_target_list');

            $deletedCount = $collection->where('state', 'ready')->count();
            $collection->where('state', 'ready')->delete();

            // 갱신 요청 재활용
            (new self)->updateUploadReport($client);

            return response()->json(['message' => "ready 상태 문서 삭제 완료", 'deleted_count' => $deletedCount]);
        } catch (\Throwable $e) {
            Log::error('clearUploadReadyState 실패', ['client_id' => $client->id, 'error' => $e->getMessage()]);
            return response()->json(['message' => $e->getMessage()], 422);
        }
    }
}
```

> MongoDBConnection 서비스의 실제 인터페이스를 `SeoulVenturesGroupware/app/Services/MongoDB/MongoDBConnection.php`에서 읽어 확인 후 사용할 것.

**Step 5: 라우트 추가**

```php
// Client 운영 액션 (Phase 5)
Route::post('review/clients/actions/bulk-update-monthly-state', [\App\Http\Controllers\Review\ClientActionController::class, 'bulkUpdateMonthlyState']);
Route::post('review/clients/{client}/actions/update-upload-report', [\App\Http\Controllers\Review\ClientActionController::class, 'updateUploadReport']);
Route::post('review/clients/{client}/actions/clear-upload-ready-state', [\App\Http\Controllers\Review\ClientActionController::class, 'clearUploadReadyState']);
```

**Step 6: 테스트 실행 (통과 확인)**

```bash
cd SeoulVenturesGroupware && vendor/bin/phpunit tests/Feature/Review/ClientActionControllerTest.php --no-coverage
```
Expected: 3 tests PASS (모두 401)

**Step 7: 전체 테스트 확인**

```bash
cd SeoulVenturesGroupware && vendor/bin/phpunit --no-coverage 2>&1 | tail -5
```

**Step 8: 커밋**

```bash
cd SeoulVenturesGroupware && git add app/Http/Controllers/Review/ClientActionController.php routes/api.php tests/Feature/Review/ClientActionControllerTest.php
git commit -m "feat(phase5): ClientActionController 추가 (bulk-update-monthly-state, update-upload-report, clear-upload-ready-state)"
```

---

## Task 4: ImWebExcelAction (Queue Job)

**Files:**
- Create: `SeoulVenturesGroupware/app/Jobs/ImWebExcelExportJob.php`
- Create: `SeoulVenturesGroupware/app/Http/Controllers/Review/ImWebExcelController.php`
- Create: `SeoulVenturesGroupware/tests/Feature/Review/ImWebExcelControllerTest.php`

**컨텍스트:**
- MongoDB `standard_review_target`에서 리뷰 조회 → Excel 생성 + 이미지 Zip 생성 → S3 저장
- `XlsFile` 모델이 필요 (sv_nova DB). sv-nova-master의 `XlsFile` 모델/마이그레이션 참고
- 비동기 처리: POST 요청 시 Job dispatch → 즉시 202 반환 → 완료 시 XlsFile 레코드 생성
- 이미지 다운로드 실패 시 해당 이미지 skip, 나머지 계속 진행
- 참고: `sv-nova-master/app/Nova/Actions/ImWebExcelAction.php`

**Step 1: XlsFile 모델 생성**

sv-nova-master의 XlsFile 모델을 참고하여 SVGW에 생성:

```php
<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class XlsFile extends Model
{
    protected $connection = 'sv_nova';
    protected $table = 'xls_files';

    protected $fillable = [
        'file_name', 'disk', 'type', 'description',
        'path', 'zip_path', 'user_id',
    ];

    protected $casts = [
        'disk' => 'string',
    ];
}
```

**Step 2: 테스트 작성**

```php
<?php

namespace Tests\Feature\Review;

use Tests\TestCase;

class ImWebExcelControllerTest extends TestCase
{
    public function test_export_requires_auth(): void
    {
        $response = $this->postJson('/api/review/clients/1/actions/imweb-excel-export');
        $response->assertStatus(401);
    }
}
```

**Step 3: 테스트 실행 (실패 확인)**

```bash
cd SeoulVenturesGroupware && vendor/bin/phpunit tests/Feature/Review/ImWebExcelControllerTest.php --no-coverage
```
Expected: FAIL - 404

**Step 4: Job + Controller 구현**

`app/Jobs/ImWebExcelExportJob.php`:

```php
<?php

namespace App\Jobs;

use App\Models\Review\Client;
use App\Models\XlsFile;
use App\Services\MongoDB\MongoDBConnection;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Storage;
use PhpOffice\PhpSpreadsheet\Spreadsheet;
use PhpOffice\PhpSpreadsheet\Writer\Xlsx;
use ZipArchive;

class ImWebExcelExportJob implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    public int $timeout = 600;
    public int $tries = 1;

    public function __construct(
        public readonly int $clientId,
        public readonly ?int $userId = null,
    ) {}

    public function handle(MongoDBConnection $mongoConnection): void
    {
        $client = Client::findOrFail($this->clientId);
        $conn = $mongoConnection->getConnectionFor($client);

        $reviews = $conn->collection('standard_review_target')
            ->where('deleted', '!=', true)
            ->get()
            ->toArray();

        // Excel 생성
        $spreadsheet = new Spreadsheet();
        $sheet = $spreadsheet->getActiveSheet();
        $headers = ['ID', '상품코드', '작성자', '평점', '리뷰내용', '작성일', '수집일'];
        $sheet->fromArray($headers, null, 'A1');

        $row = 2;
        $imageUrls = [];
        foreach ($reviews as $review) {
            $sheet->fromArray([
                (string) ($review['_id'] ?? ''),
                $review['client_item_code'] ?? '',
                $review['review_user_name'] ?? '',
                $review['review_score'] ?? '',
                $review['review_content'] ?? '',
                $review['review_reg_date'] ?? '',
                $review['crawling_date'] ?? '',
            ], null, "A{$row}");
            foreach ($review['review_images'] ?? [] as $url) {
                $imageUrls[(string) ($review['_id'] ?? '')] = $url;
            }
            $row++;
        }

        // S3에 Excel 저장
        $timestamp = now()->format('YmdHis');
        $xlsPath = "imweb-excel/{$this->clientId}/{$timestamp}.xlsx";
        $writer = new Xlsx($spreadsheet);
        ob_start();
        $writer->save('php://output');
        $xlsContent = ob_get_clean();
        Storage::disk('s3')->put($xlsPath, $xlsContent);

        // 이미지 Zip 생성
        $zipPath = null;
        if (!empty($imageUrls)) {
            $tmpZip = tempnam(sys_get_temp_dir(), 'imweb_') . '.zip';
            $zip = new ZipArchive();
            if ($zip->open($tmpZip, ZipArchive::CREATE) === true) {
                foreach ($imageUrls as $reviewId => $url) {
                    try {
                        $imageContent = Http::timeout(10)->get($url)->body();
                        $ext = pathinfo(parse_url($url, PHP_URL_PATH), PATHINFO_EXTENSION) ?: 'jpg';
                        $zip->addFromString("{$reviewId}.{$ext}", $imageContent);
                    } catch (\Throwable $e) {
                        Log::warning('ImWebExcel: 이미지 다운로드 실패', ['url' => $url, 'error' => $e->getMessage()]);
                    }
                }
                $zip->close();
                $zipS3Path = "imweb-excel/{$this->clientId}/{$timestamp}-images.zip";
                Storage::disk('s3')->put($zipS3Path, file_get_contents($tmpZip));
                @unlink($tmpZip);
                $zipPath = $zipS3Path;
            }
        }

        XlsFile::create([
            'file_name'   => "{$client->name}-{$timestamp}.xlsx",
            'disk'        => 's3',
            'type'        => 'xlsx',
            'description' => "ImWeb 리뷰 내보내기 - {$client->name}",
            'path'        => $xlsPath,
            'zip_path'    => $zipPath,
            'user_id'     => $this->userId,
        ]);
    }
}
```

`app/Http/Controllers/Review/ImWebExcelController.php`:

```php
<?php

namespace App\Http\Controllers\Review;

use App\Http\Controllers\Controller;
use App\Jobs\ImWebExcelExportJob;
use App\Models\Review\Client;
use Illuminate\Http\JsonResponse;

class ImWebExcelController extends Controller
{
    public function export(Client $client): JsonResponse
    {
        ImWebExcelExportJob::dispatch($client->id, auth()->id());

        return response()->json([
            'message' => 'Excel 내보내기 작업이 시작되었습니다. 완료 후 /admin/xls-files에서 다운로드하세요.',
        ], 202);
    }
}
```

**Step 5: 라우트 추가**

```php
Route::post('review/clients/{client}/actions/imweb-excel-export', [\App\Http\Controllers\Review\ImWebExcelController::class, 'export']);
```

**Step 6: 테스트 실행 (통과 확인)**

```bash
cd SeoulVenturesGroupware && vendor/bin/phpunit tests/Feature/Review/ImWebExcelControllerTest.php --no-coverage
```
Expected: 1 test PASS (401)

**Step 7: 커밋**

```bash
cd SeoulVenturesGroupware && git add app/Jobs/ImWebExcelExportJob.php app/Http/Controllers/Review/ImWebExcelController.php app/Models/XlsFile.php routes/api.php tests/Feature/Review/ImWebExcelControllerTest.php
git commit -m "feat(phase5): ImWebExcel 내보내기 Queue Job + Controller 추가"
```

---

## Task 5: 프론트엔드 — 드라이버 상세 페이지 액션 버튼

**Files:**
- Modify: `SeoulVenturesGroupware/frontend/resources/ts/pages/review/download-driver/[id].vue` (또는 드라이버 상세 페이지 실제 경로 확인 후)
- Create: `SeoulVenturesGroupware/frontend/resources/ts/api/entities/review/driverConfigActions.ts`

**컨텍스트:**
- 드라이버 상세 페이지 실제 경로를 `frontend/resources/ts/pages/review/` 디렉토리에서 확인할 것
- 기존 페이지의 액션 버튼 패턴 참고 (confirm dialog 패턴)
- Zigzag 드라이버 전용 버튼(deleteZzExpress)은 `driver_type === 'zigzag'`일 때만 표시

**Step 1: API 엔티티 작성**

`frontend/resources/ts/api/entities/review/driverConfigActions.ts`:

```typescript
import { post } from '@/api'

export const driverConfigActionsApi = {
  clearLastCrawledDate: (driverConfigId: number) =>
    post(`/review/driver-configs/${driverConfigId}/actions/clear-last-crawled-date`, {}),

  runPeriodicEcs: (driverConfigId: number) =>
    post(`/review/driver-configs/${driverConfigId}/actions/run-periodic-ecs`, {}),

  runWidgetEcs: (driverConfigId: number) =>
    post(`/review/driver-configs/${driverConfigId}/actions/run-widget-ecs`, {}),

  unlockSoldout: (driverConfigId: number) =>
    post(`/review/driver-configs/${driverConfigId}/actions/unlock-soldout`, {}),

  deleteZzExpress: (driverConfigId: number) =>
    post(`/review/driver-configs/${driverConfigId}/actions/delete-zz-express`, {}),

  updateLastCrawledDate: (driverConfigId: number) =>
    post(`/review/driver-configs/${driverConfigId}/actions/update-last-crawled-date`, {}),
}
```

**Step 2: 드라이버 상세 페이지에 액션 섹션 추가**

드라이버 상세 페이지에서 `VCard` 하나를 추가하여 액션 버튼들을 배치:

```vue
<!-- 드라이버 운영 액션 카드 (드라이버 상세 페이지 하단에 추가) -->
<VCard class="mt-4">
  <VCardTitle>운영 액션</VCardTitle>
  <VCardText>
    <div class="d-flex flex-wrap gap-2">
      <VBtn
        color="warning"
        :loading="actionLoading === 'clearLastCrawledDate'"
        @click="confirmAction('last_crawled_date를 초기화하시겠습니까?', () => runAction('clearLastCrawledDate'))"
      >
        크롤링 날짜 초기화
      </VBtn>
      <VBtn
        color="primary"
        :loading="actionLoading === 'runPeriodicEcs'"
        @click="confirmAction('정기 이관 ECS를 강제 실행하시겠습니까?', () => runAction('runPeriodicEcs'))"
      >
        정기 이관 실행
      </VBtn>
      <VBtn
        color="primary"
        :loading="actionLoading === 'runWidgetEcs'"
        @click="confirmAction('위젯 ECS를 강제 실행하시겠습니까?', () => runAction('runWidgetEcs'))"
      >
        위젯 실행
      </VBtn>
      <VBtn
        color="secondary"
        :loading="actionLoading === 'unlockSoldout'"
        @click="confirmAction('품절 상태를 해제하시겠습니까?', () => runAction('unlockSoldout'))"
      >
        품절 해제
      </VBtn>
      <VBtn
        color="secondary"
        :loading="actionLoading === 'updateLastCrawledDate'"
        @click="runAction('updateLastCrawledDate')"
      >
        크롤링 날짜 동기화
      </VBtn>
      <VBtn
        v-if="driverConfig?.driver_type === 'zigzag'"
        color="error"
        :loading="actionLoading === 'deleteZzExpress'"
        @click="confirmAction('직진배송 Target을 모두 삭제하시겠습니까?', () => runAction('deleteZzExpress'))"
      >
        직진배송 삭제
      </VBtn>
    </div>
  </VCardText>
</VCard>
```

script에 추가할 로직:

```typescript
const actionLoading = ref<string | null>(null)

const runAction = async (actionName: keyof typeof driverConfigActionsApi) => {
  actionLoading.value = actionName
  try {
    const { success, data } = await driverConfigActionsApi[actionName](driverConfigId)
    if (success) snackbar(data?.message ?? '완료되었습니다.')
  }
  catch (error) {
    handleError(error)
  }
  finally {
    actionLoading.value = null
  }
}
```

**Step 3: 타입 체크**

```bash
cd SeoulVenturesGroupware/frontend && bun run typecheck 2>&1 | tail -10
```
Expected: 타입 오류 없음 (또는 기존 오류만)

**Step 4: 커밋**

```bash
cd SeoulVenturesGroupware && git add frontend/resources/ts/api/entities/review/driverConfigActions.ts frontend/resources/ts/pages/review/
git commit -m "feat(phase5): 드라이버 상세 페이지에 운영 액션 버튼 추가"
```

---

## Task 6: 프론트엔드 — 클라이언트 목록/상세 페이지 액션

**Files:**
- Modify: `SeoulVenturesGroupware/frontend/resources/ts/pages/review/client/index.vue`
- Modify: `SeoulVenturesGroupware/frontend/resources/ts/pages/review/client/[id].vue` (또는 상세 페이지 실제 경로)
- Create: `SeoulVenturesGroupware/frontend/resources/ts/api/entities/review/clientActions.ts`

**Step 1: API 엔티티 작성**

```typescript
import { post } from '@/api'

export const clientActionsApi = {
  bulkUpdateMonthlyState: (ids: number[], state: 'Y' | 'N', updateDrivers = false) =>
    post('/review/clients/actions/bulk-update-monthly-state', { ids, state, update_drivers: updateDrivers }),

  updateUploadReport: (clientId: number) =>
    post(`/review/clients/${clientId}/actions/update-upload-report`, {}),

  clearUploadReadyState: (clientId: number) =>
    post(`/review/clients/${clientId}/actions/clear-upload-ready-state`, {}),

  imwebExcelExport: (clientId: number) =>
    post(`/review/clients/${clientId}/actions/imweb-excel-export`, {}),
}
```

**Step 2: 클라이언트 목록 페이지에 일괄 액션 추가**

- 체크박스로 복수 선택 후 "monthly_state Y로 변경" / "monthly_state N으로 변경" 버튼 표시
- 드라이버도 함께 변경할지 체크박스 옵션 제공

**Step 3: 클라이언트 상세 페이지에 액션 버튼 추가**

드라이버 상세와 동일한 패턴으로 `운영 액션` 카드 추가:
- 업로드 리포트 갱신
- ready 상태 초기화
- ImWeb Excel 내보내기 (비동기, 완료 후 /admin/xls-files 안내)

**Step 4: 타입 체크 및 커밋**

```bash
cd SeoulVenturesGroupware/frontend && bun run typecheck 2>&1 | tail -10
cd SeoulVenturesGroupware && git add frontend/ && git commit -m "feat(phase5): 클라이언트 목록/상세 페이지에 운영 액션 추가"
```

---

## Task 7: sv-nova-master 해당 Actions 비활성화

**Files:**
- Modify: `sv-nova-master/app/Nova/Review/DriverConfig.php`
- Modify: `sv-nova-master/app/Nova/Review/Client.php`

**Step 1: DriverConfig actions() 배열에서 이관 완료된 항목 제거**

`sv-nova-master/app/Nova/Review/DriverConfig.php`의 `actions()` 반환 배열에서 다음 제거:
- `ClearLastCrawledDate`
- `RunPeriodicEcsTask`
- `RunWidgetEcsTask`
- `UnlockSoldoutAction`
- `BulkDeleteZzExpressFromDriverConfig`
- `UpdateLastCrawledDateToDriverConfig`

**Step 2: Client actions() 배열에서 이관 완료된 항목 제거**

`sv-nova-master/app/Nova/Review/Client.php`의 `actions()` 반환 배열에서 다음 제거:
- `BulkUpdateMonthlyState`
- `UpdateReviewUploadReportAction`
- `ClearUploadReadyState`

ImWebExcelAction은 Queue Job이 안정화된 후 제거.

**Step 3: 커밋 (sv-nova-master)**

```bash
cd /opt/SeoulVentures/regle/sv-nova-master && git add app/Nova/Review/DriverConfig.php app/Nova/Review/Client.php
git commit -m "chore(phase5): 이관 완료된 Nova Actions 제거 (SVGW 이관)"
```

**Step 4: 서브모듈 업데이트 커밋 (regle-mono)**

```bash
cd /opt/SeoulVentures/regle && git add sv-nova-master SeoulVenturesGroupware
git commit -m "chore: Phase 5 - 드라이버/클라이언트 운영 액션 이관 완료"
```

---

## Task 8: PR 생성

**Step 1: 전체 테스트 실행**

```bash
cd SeoulVenturesGroupware && vendor/bin/phpunit --no-coverage 2>&1 | tail -5
```
Expected: 전체 PASS

**Step 2: 브랜치 푸시 및 PR 생성**

```bash
cd SeoulVenturesGroupware && git push -u origin feat/phase5-driver-client-actions

gh pr create \
  --title "feat(phase5): 드라이버/클라이언트 핵심 운영 액션 이관 (sv-nova-master → SVGW)" \
  --body "$(cat <<'EOF'
## Summary
- RegleEcsService에 runPeriodicTask / runWidgetTask 추가
- DriverConfigActionController: clear-last-crawled-date, run-periodic-ecs, run-widget-ecs, unlock-soldout, delete-zz-express, update-last-crawled-date
- ClientActionController: bulk-update-monthly-state, update-upload-report, clear-upload-ready-state
- ImWebExcelExportJob: MongoDB 리뷰 → Excel + 이미지 Zip 비동기 생성
- 드라이버/클라이언트 상세 페이지에 운영 액션 버튼 추가
- sv-nova-master 해당 Nova Actions 제거

## Test Plan
- [ ] 각 액션 API 401 인증 확인
- [ ] clearLastCrawledDate: Target last_crawled_date 제거 확인
- [ ] runPeriodicEcs / runWidgetEcs: ECS 태스크 트리거 확인
- [ ] bulkUpdateMonthlyState: 복수 클라이언트 상태 일괄 변경 확인
- [ ] ImWebExcel: Job dispatch 후 xls-files에서 다운로드 확인
- [ ] 드라이버/클라이언트 페이지에서 버튼 동작 확인

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

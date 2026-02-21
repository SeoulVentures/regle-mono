# Phase 2: 일일 리포트 생성 이관 구현 계획

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** sv-nova-master의 `report:generate-daily` 명령어와 관련 서비스를 SVGW로 이관하고 sv-nova-master 스케줄러에서 즉시 제거한다.

**Architecture:** SVGW의 기존 `MongoDBCollectionResolver`에 report용 컬렉션 이름 메서드를 추가하고, `ReviewDataCollectionService`(MongoDB 집계) → `ReportGenerationService`(MySQL 쓰기) → `GenerateDailyReportCommand`(Artisan) 순서로 구현한다. 실패 시 Slack 알림을 전송한다.

**Tech Stack:** Laravel 12, PHP 8.4, sv_nova MySQL 연결(read/write 분리), MongoDB(클라이언트별 동적 DB), `mongodb/laravel-mongodb` 5.x

---

## 사전 확인 사항

- 작업 디렉토리: `/opt/SeoulVentures/regle/SeoulVenturesGroupware`
- 테스트 실행: `vendor/bin/phpunit --testdox`
- sv-nova-master 디렉토리: `/opt/SeoulVentures/regle/sv-nova-master`
- 모델 `DailyReport`, `DailyClientStatistic`, `DailyDriverStatistic`는 이미 존재 (`protected $connection = 'sv_nova'`)
- `MongoDBConnection`, `MongoDBCollectionResolver`는 `app/Services/MongoDB/`에 존재

---

### Task 1: MongoDBCollectionResolver에 report용 컬렉션 이름 메서드 추가

**Files:**
- Modify: `app/Services/MongoDB/MongoDBCollectionResolver.php`
- Test: `tests/Unit/Services/MongoDB/MongoDBCollectionResolverTest.php`

**Step 1: 실패하는 테스트 작성**

`tests/Unit/Services/MongoDB/MongoDBCollectionResolverTest.php` 를 신규 생성:

```php
<?php

namespace Tests\Unit\Services\MongoDB;

use App\Services\MongoDB\MongoDBCollectionResolver;
use Tests\TestCase;

class MongoDBCollectionResolverTest extends TestCase
{
    private MongoDBCollectionResolver $resolver;

    protected function setUp(): void
    {
        parent::setUp();
        $this->resolver = new MongoDBCollectionResolver();
    }

    public function test_resolves_standard_review_collection_name(): void
    {
        $this->assertSame('standard_review_target', $this->resolver->resolveStandardReview());
    }

    public function test_resolves_upload_status_collection_name(): void
    {
        $this->assertSame('review_upload_target_list', $this->resolver->resolveUploadStatus());
    }
}
```

**Step 2: 테스트 실행 — 실패 확인**

```bash
cd /opt/SeoulVentures/regle/SeoulVenturesGroupware
vendor/bin/phpunit tests/Unit/Services/MongoDB/MongoDBCollectionResolverTest.php --testdox
```

Expected: FAIL — `Call to undefined method resolveStandardReview()`

**Step 3: 구현**

`app/Services/MongoDB/MongoDBCollectionResolver.php` 끝에 두 메서드 추가:

```php
    public function resolveStandardReview(): string
    {
        return 'standard_review_target';
    }

    public function resolveUploadStatus(): string
    {
        return 'review_upload_target_list';
    }
```

최종 파일:

```php
<?php

namespace App\Services\MongoDB;

use App\Models\Review\DriverConfig;

class MongoDBCollectionResolver
{
    private array $irregularDriverNames = [
        'smart_store' => 'naver_smart_store',
        '11st' => 'eleven_street',
        'ten_by_ten' => 'tenbyten',
        '29cm' => 'twentynine_cm',
        'gsshop_brand_shop' => 'gsshop',
        'hmall_brand_shop' => 'hmall',
    ];

    public function resolve(DriverConfig $driverConfig): string
    {
        $driverCode = $driverConfig->downloadDriver->code;

        return ($this->irregularDriverNames[$driverCode] ?? $driverCode) . '_review';
    }

    public function resolveStandardReview(): string
    {
        return 'standard_review_target';
    }

    public function resolveUploadStatus(): string
    {
        return 'review_upload_target_list';
    }
}
```

**Step 4: 테스트 통과 확인**

```bash
vendor/bin/phpunit tests/Unit/Services/MongoDB/MongoDBCollectionResolverTest.php --testdox
```

Expected: PASS (2 tests)

**Step 5: 커밋**

```bash
git add app/Services/MongoDB/MongoDBCollectionResolver.php \
        tests/Unit/Services/MongoDB/MongoDBCollectionResolverTest.php
git commit -m "feat(report): MongoDBCollectionResolver에 report용 컬렉션 이름 메서드 추가"
```

---

### Task 2: ReviewDataCollectionService 구현

MongoDB에서 클라이언트별 업로드 통계를 집계하는 서비스.

**Files:**
- Create: `app/Services/Report/ReviewDataCollectionService.php`
- Test: `tests/Unit/Services/Report/ReviewDataCollectionServiceTest.php`

**Step 1: 실패하는 테스트 작성**

`tests/Unit/Services/Report/ReviewDataCollectionServiceTest.php` 신규 생성:

```php
<?php

namespace Tests\Unit\Services\Report;

use App\Models\Review\Client;
use App\Services\MongoDB\MongoDBCollectionResolver;
use App\Services\MongoDB\MongoDBConnection;
use App\Services\Report\ReviewDataCollectionService;
use Carbon\Carbon;
use Mockery;
use Tests\TestCase;

class ReviewDataCollectionServiceTest extends TestCase
{
    public function test_collect_client_data_returns_empty_when_no_upload_documents(): void
    {
        $client = Mockery::mock(Client::class);
        $client->shouldReceive('getAttribute')->with('id')->andReturn(1);
        $client->shouldReceive('getAttribute')->with('name')->andReturn('테스트고객사');

        $mockCollection = Mockery::mock(\MongoDB\Collection::class);
        $mockCollection->shouldReceive('countDocuments')->andReturn(0);

        $mockConnection = Mockery::mock(\Illuminate\Database\ConnectionInterface::class);
        $mockConnection->shouldReceive('getMongoClient')->andReturnSelf();
        $mockConnection->shouldReceive('table')
            ->with('review_upload_target_list')
            ->andReturn($mockCollection);

        $mongoDBConnection = Mockery::mock(MongoDBConnection::class);
        $mongoDBConnection->shouldReceive('getConnectionFor')
            ->with($client)
            ->andReturn($mockConnection);

        $resolver = new MongoDBCollectionResolver();

        $service = new ReviewDataCollectionService($mongoDBConnection, $resolver);

        $result = $service->collectClientData($client, Carbon::parse('2026-02-20'));

        $this->assertSame(0, $result['total_reviews']);
        $this->assertSame(0, $result['transferred_reviews']);
        $this->assertSame(0, $result['failed_reviews']);
    }
}
```

**Step 2: 테스트 실행 — 실패 확인**

```bash
vendor/bin/phpunit tests/Unit/Services/Report/ReviewDataCollectionServiceTest.php --testdox
```

Expected: FAIL — `Class ReviewDataCollectionService not found`

**Step 3: 구현**

`app/Services/Report/ReviewDataCollectionService.php` 신규 생성:

```php
<?php

namespace App\Services\Report;

use App\Models\Review\Client;
use App\Models\Review\DriverConfig;
use App\Services\MongoDB\MongoDBCollectionResolver;
use App\Services\MongoDB\MongoDBConnection;
use Carbon\Carbon;
use Illuminate\Support\Facades\Log;
use MongoDB\Collection as MongoCollection;
use MongoDB\Model\BSONArray;

class ReviewDataCollectionService
{
    public function __construct(
        private MongoDBConnection $mongoDBConnection,
        private MongoDBCollectionResolver $collectionResolver,
    ) {}

    /**
     * 활성 클라이언트 전체의 리뷰 데이터를 수집한다.
     */
    public function collectAllClientsData(Carbon $date): array
    {
        $clients = Client::active()->get();
        $results = [];

        foreach ($clients as $client) {
            $results[$client->id] = $this->collectClientData($client, $date);
        }

        return $results;
    }

    /**
     * 단일 클라이언트의 지정 날짜 리뷰 통계를 집계한다.
     */
    public function collectClientData(Client $client, Carbon $date): array
    {
        $result = $this->emptyResult($client, $date);

        $driverConfigs = DriverConfig::where('client_id', $client->id)
            ->where('monthly_state', 'Y')
            ->where('auto_migration_start_date', '<=', $date)
            ->where('auto_migration_end_date', '>=', $date)
            ->get();

        if ($driverConfigs->isEmpty()) {
            return $result;
        }

        foreach ($driverConfigs as $driverConfig) {
            $driverResult = $this->collectDriverData($client, $driverConfig, $date);

            $result['total_reviews'] += $driverResult['total_reviews'];
            $result['transferred_reviews'] += $driverResult['transferred_reviews'];
            $result['failed_reviews'] += $driverResult['failed_reviews'];

            foreach ($driverResult['status_counts'] as $status => $count) {
                $result['status_counts'][$status] = ($result['status_counts'][$status] ?? 0) + $count;
            }
            foreach ($driverResult['service_counts'] as $service => $count) {
                $result['service_counts'][$service] = ($result['service_counts'][$service] ?? 0) + $count;
            }
            if (!empty($driverResult['error_details'])) {
                $result['error_details'] = array_merge($result['error_details'], $driverResult['error_details']);
            }

            $result['driver_results'][$driverConfig->id] = $driverResult;
        }

        return $result;
    }

    private function collectDriverData(Client $client, DriverConfig $driverConfig, Carbon $date): array
    {
        $result = [
            'driver_id'           => $driverConfig->id,
            'driver_name'         => $driverConfig->name,
            'driver_code'         => $driverConfig->driver_code,
            'total_reviews'       => 0,
            'transferred_reviews' => 0,
            'failed_reviews'      => 0,
            'status_counts'       => [],
            'service_counts'      => [],
            'error_details'       => [],
        ];

        try {
            $connection  = $this->mongoDBConnection->getConnectionFor($client);
            $dateString  = $date->format('Y-m-d');
            $driverCode  = $driverConfig->driver_code;

            // 업로드 상태 컬렉션에서 해당 날짜/드라이버 문서 수 확인
            $uploadCount = $connection
                ->table($this->collectionResolver->resolveUploadStatus())
                ->where('driver_code', $driverCode)
                ->where('finished_at', '>=', $dateString . ' 00:00:00')
                ->where('finished_at', '<=', $dateString . ' 23:59:59')
                ->count();

            if ($uploadCount === 0) {
                return $result;
            }

            $stats = $this->aggregateDriverStats($connection, $driverCode, $dateString);

            return array_merge($result, $stats);
        } catch (\Exception $e) {
            Log::error("ReviewDataCollectionService: 드라이버 데이터 수집 실패", [
                'client_id' => $client->id,
                'driver_id' => $driverConfig->id,
                'error'     => $e->getMessage(),
            ]);
            $result['error_details'][] = $e->getMessage();

            return $result;
        }
    }

    private function aggregateDriverStats(
        \Illuminate\Database\ConnectionInterface $connection,
        string $driverCode,
        string $dateString
    ): array {
        $uploadStatusCollection = $this->collectionResolver->resolveUploadStatus();

        $pipeline = [
            ['$lookup' => [
                'from'         => $uploadStatusCollection,
                'localField'   => 'upload_key',
                'foreignField' => 'upload_key',
                'as'           => 'upload_status',
            ]],
            ['$unwind' => ['path' => '$upload_status', 'preserveNullAndEmptyArrays' => true]],
            ['$match' => [
                'review_driver'              => $driverCode,
                'upload_status.finished_at'  => [
                    '$gte' => $dateString . ' 00:00:00',
                    '$lte' => $dateString . ' 23:59:59',
                ],
            ]],
            ['$project' => [
                'review_driver' => 1,
                'status'        => '$upload_status.state',
                'error_message' => '$upload_status.error_message',
            ]],
            ['$group' => [
                '_id'                 => null,
                'total_reviews'       => ['$sum' => 1],
                'transferred_reviews' => ['$sum' => ['$cond' => [['$eq' => ['$status', 'finished']], 1, 0]]],
                'failed_reviews'      => ['$sum' => ['$cond' => [['$eq' => ['$status', 'failed']], 1, 0]]],
                'status_counts'       => ['$push' => '$status'],
                'service_counts'      => ['$push' => '$review_driver'],
                'error_messages'      => ['$push' => ['$cond' => [
                    ['$eq' => ['$status', 'failed']], '$error_message', '$$REMOVE',
                ]]],
            ]],
        ];

        $raw     = $connection->table($this->collectionResolver->resolveStandardReview())->raw();
        $results = iterator_to_array($raw->aggregate($pipeline));

        if (empty($results)) {
            return [];
        }

        $data = $results[0];

        $toArray = fn($v) => $v instanceof BSONArray ? iterator_to_array($v) : (array) $v;

        return [
            'total_reviews'       => $data['total_reviews'],
            'transferred_reviews' => $data['transferred_reviews'],
            'failed_reviews'      => $data['failed_reviews'],
            'status_counts'       => array_count_values(array_filter($toArray($data['status_counts']))),
            'service_counts'      => array_count_values(array_filter($toArray($data['service_counts']))),
            'error_details'       => array_values(array_filter($toArray($data['error_messages']))),
        ];
    }

    private function emptyResult(Client $client, Carbon $date): array
    {
        return [
            'client_id'           => $client->id,
            'client_name'         => $client->name,
            'date'                => $date->format('Y-m-d'),
            'total_reviews'       => 0,
            'transferred_reviews' => 0,
            'failed_reviews'      => 0,
            'status_counts'       => [],
            'service_counts'      => [],
            'error_details'       => [],
            'driver_results'      => [],
        ];
    }
}
```

**Step 4: 테스트 통과 확인**

```bash
vendor/bin/phpunit tests/Unit/Services/Report/ReviewDataCollectionServiceTest.php --testdox
```

Expected: PASS

**Step 5: 커밋**

```bash
git add app/Services/Report/ReviewDataCollectionService.php \
        tests/Unit/Services/Report/ReviewDataCollectionServiceTest.php
git commit -m "feat(report): ReviewDataCollectionService 구현 - MongoDB 업로드 통계 집계"
```

---

### Task 3: ReportGenerationService 구현

MongoDB 집계 결과를 sv_nova DB(daily_reports 등)에 저장하는 서비스.

**Files:**
- Create: `app/Services/Report/ReportGenerationService.php`
- Test: `tests/Unit/Services/Report/ReportGenerationServiceTest.php`

**Step 1: 실패하는 테스트 작성**

`tests/Unit/Services/Report/ReportGenerationServiceTest.php` 신규 생성:

```php
<?php

namespace Tests\Unit\Services\Report;

use App\Models\Report\DailyReport;
use App\Services\Report\ReportGenerationService;
use App\Services\Report\ReviewDataCollectionService;
use Carbon\Carbon;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Mockery;
use Tests\TestCase;

class ReportGenerationServiceTest extends TestCase
{
    use RefreshDatabase;

    public function test_check_report_exists_returns_false_when_no_report(): void
    {
        $mockCollectionService = Mockery::mock(ReviewDataCollectionService::class);
        $service = new ReportGenerationService($mockCollectionService);

        $this->assertFalse($service->checkReportExists(Carbon::parse('2026-02-20')));
    }

    public function test_generate_daily_report_returns_null_when_no_transferred_reviews(): void
    {
        $mockCollectionService = Mockery::mock(ReviewDataCollectionService::class);
        $mockCollectionService->shouldReceive('collectAllClientsData')
            ->andReturn([
                1 => [
                    'total_reviews'       => 0,
                    'transferred_reviews' => 0,
                    'failed_reviews'      => 0,
                    'status_counts'       => [],
                    'service_counts'      => [],
                    'error_details'       => [],
                    'driver_results'      => [],
                ],
            ]);

        $service = new ReportGenerationService($mockCollectionService);

        $result = $service->generateDailyReport(Carbon::parse('2026-02-20'));

        $this->assertNull($result);
    }
}
```

**Step 2: 테스트 실행 — 실패 확인**

```bash
vendor/bin/phpunit tests/Unit/Services/Report/ReportGenerationServiceTest.php --testdox
```

Expected: FAIL — `Class ReportGenerationService not found`

**Step 3: 구현**

`app/Services/Report/ReportGenerationService.php` 신규 생성:

```php
<?php

namespace App\Services\Report;

use App\Models\Report\DailyClientStatistic;
use App\Models\Report\DailyDriverStatistic;
use App\Models\Report\DailyReport;
use App\Models\Review\Client;
use App\Models\Review\DriverConfig;
use Carbon\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;

class ReportGenerationService
{
    public function __construct(
        private ReviewDataCollectionService $dataCollectionService,
    ) {}

    public function generateDailyReport(Carbon $date, bool $forceRebuild = false): ?DailyReport
    {
        $dateStr = $date->format('Y-m-d');

        $existing = DailyReport::on('sv_nova')->where('report_date', $dateStr)->first();

        if ($existing && !$forceRebuild) {
            return $existing;
        }

        if ($existing && $forceRebuild) {
            DB::connection('sv_nova')->transaction(function () use ($existing) {
                $existing->clientStatistics()->delete();
                $existing->driverStatistics()->delete();
                $existing->delete();
            });
        }

        return $this->buildReport($date, $forceRebuild);
    }

    public function checkReportExists(Carbon $date): bool
    {
        return DailyReport::on('sv_nova')
            ->where('report_date', $date->format('Y-m-d'))
            ->exists();
    }

    private function buildReport(Carbon $date, bool $forceRebuild): ?DailyReport
    {
        $clientsData = $this->dataCollectionService->collectAllClientsData($date);
        $totals      = $this->calculateTotals($clientsData);

        if ($totals['total_transferred'] === 0 && !$forceRebuild) {
            Log::info("ReportGenerationService: 이관 건수 0 — 리포트 생성 skip", ['date' => $date->format('Y-m-d')]);
            return null;
        }

        return DB::connection('sv_nova')->transaction(function () use ($date, $clientsData, $totals) {
            $report = DailyReport::on('sv_nova')->create([
                'report_date'         => $date->format('Y-m-d'),
                'total_clients'       => $totals['total_clients'],
                'active_clients'      => $totals['active_clients'],
                'total_reviews'       => $totals['total_reviews'],
                'transferred_reviews' => $totals['total_transferred'],
                'failed_reviews'      => $totals['total_failed'],
                'success_rate'        => $totals['success_rate'],
                'status_summary'      => json_encode($totals['status_counts']),
                'service_summary'     => json_encode($totals['service_counts']),
                'top_clients'         => json_encode($this->topClients($clientsData)),
                'top_failure_clients' => json_encode($this->topFailureClients($clientsData)),
            ]);

            $this->createClientStatistics($report, $clientsData);
            $this->createDriverStatistics($report, $clientsData);

            return $report;
        });
    }

    private function calculateTotals(array $clientsData): array
    {
        $totals = [
            'total_clients'   => count($clientsData),
            'active_clients'  => 0,
            'total_reviews'   => 0,
            'total_transferred' => 0,
            'total_failed'    => 0,
            'success_rate'    => 0.0,
            'status_counts'   => [],
            'service_counts'  => [],
        ];

        foreach ($clientsData as $data) {
            if ($data['total_reviews'] > 0) {
                $totals['active_clients']++;
            }
            $totals['total_reviews']    += $data['total_reviews'];
            $totals['total_transferred'] += $data['transferred_reviews'];
            $totals['total_failed']     += $data['failed_reviews'];

            foreach ($data['status_counts'] as $k => $v) {
                $totals['status_counts'][$k] = ($totals['status_counts'][$k] ?? 0) + $v;
            }
            foreach ($data['service_counts'] as $k => $v) {
                $totals['service_counts'][$k] = ($totals['service_counts'][$k] ?? 0) + $v;
            }
        }

        if ($totals['total_reviews'] > 0) {
            $totals['success_rate'] = round(
                ($totals['total_transferred'] / $totals['total_reviews']) * 100, 2
            );
        }

        return $totals;
    }

    private function topClients(array $clientsData): array
    {
        return collect($clientsData)
            ->map(fn($data, $id) => [
                'client_id'           => (int) $id,
                'client_name'         => $data['client_name'] ?? "고객사 ID: {$id}",
                'transferred_reviews' => $data['transferred_reviews'],
            ])
            ->filter(fn($d) => $d['transferred_reviews'] > 0)
            ->sortByDesc('transferred_reviews')
            ->take(5)
            ->values()
            ->toArray();
    }

    private function topFailureClients(array $clientsData): array
    {
        return collect($clientsData)
            ->map(fn($data, $id) => [
                'client_id'    => (int) $id,
                'client_name'  => $data['client_name'] ?? "고객사 ID: {$id}",
                'failed_reviews' => $data['failed_reviews'],
            ])
            ->filter(fn($d) => $d['failed_reviews'] > 0)
            ->sortByDesc('failed_reviews')
            ->take(5)
            ->values()
            ->toArray();
    }

    private function createClientStatistics(DailyReport $report, array $clientsData): void
    {
        foreach ($clientsData as $clientId => $data) {
            if ($data['transferred_reviews'] === 0) {
                continue;
            }

            $client = Client::find($clientId);
            if (!$client) {
                continue;
            }

            $successRate = $data['total_reviews'] > 0
                ? round(($data['transferred_reviews'] / $data['total_reviews']) * 100, 2)
                : 0.0;

            $report->clientStatistics()->updateOrCreate(
                ['client_id' => $client->id],
                [
                    'client_name'         => $client->name,
                    'total_reviews'       => $data['total_reviews'],
                    'transferred_reviews' => $data['transferred_reviews'],
                    'failed_reviews'      => $data['failed_reviews'],
                    'success_rate'        => $successRate,
                    'status_summary'      => $data['status_counts'],
                    'service_summary'     => $data['service_counts'],
                    'driver_summary'      => $data['driver_results'],
                    'error_details'       => !empty($data['error_details']) ? $data['error_details'] : null,
                ]
            );
        }
    }

    private function createDriverStatistics(DailyReport $report, array $clientsData): void
    {
        foreach ($clientsData as $clientId => $data) {
            $client = Client::find($clientId);
            if (!$client) {
                continue;
            }

            $clientStat = $report->clientStatistics->where('client_id', $client->id)->first();
            if (!$clientStat) {
                continue;
            }

            foreach ($data['driver_results'] ?? [] as $driverId => $driverData) {
                if (($driverData['transferred_reviews'] ?? 0) === 0) {
                    continue;
                }

                $driverConfig = DriverConfig::find($driverId);
                $successRate  = ($driverData['total_reviews'] ?? 0) > 0
                    ? round(($driverData['transferred_reviews'] / $driverData['total_reviews']) * 100, 2)
                    : 0.0;

                $clientStat->driverStatistics()->updateOrCreate(
                    [
                        'driver_id'       => $driverId,
                        'client_id'       => $client->id,
                        'daily_report_id' => $report->id,
                    ],
                    [
                        'driver_name'         => $driverConfig?->name ?? "드라이버 ID {$driverId}",
                        'total_reviews'       => $driverData['total_reviews'] ?? 0,
                        'transferred_reviews' => $driverData['transferred_reviews'] ?? 0,
                        'failed_reviews'      => $driverData['failed_reviews'] ?? 0,
                        'success_rate'        => $successRate,
                        'status_summary'      => $driverData['status_counts'] ?? null,
                        'error_details'       => $driverData['error_details'] ?? null,
                        'report_date'         => $report->report_date,
                    ]
                );
            }
        }
    }
}
```

**Step 4: 테스트 통과 확인**

```bash
vendor/bin/phpunit tests/Unit/Services/Report/ReportGenerationServiceTest.php --testdox
```

Expected: PASS (2 tests)

**Step 5: 커밋**

```bash
git add app/Services/Report/ReportGenerationService.php \
        tests/Unit/Services/Report/ReportGenerationServiceTest.php
git commit -m "feat(report): ReportGenerationService 구현 - daily_reports 생성"
```

---

### Task 4: GenerateDailyReportCommand 구현

**Files:**
- Create: `app/Console/Commands/GenerateDailyReportCommand.php`
- Test: `tests/Feature/GenerateDailyReportCommandTest.php`

**Step 1: 실패하는 테스트 작성**

`tests/Feature/GenerateDailyReportCommandTest.php` 신규 생성:

```php
<?php

namespace Tests\Feature;

use App\Services\Report\ReportGenerationService;
use Carbon\Carbon;
use Illuminate\Support\Facades\Http;
use Mockery;
use Tests\TestCase;

class GenerateDailyReportCommandTest extends TestCase
{
    public function test_command_skips_when_report_already_exists(): void
    {
        $mockService = Mockery::mock(ReportGenerationService::class);
        $mockService->shouldReceive('checkReportExists')->andReturn(true);
        $mockService->shouldNotReceive('generateDailyReport');
        $this->app->instance(ReportGenerationService::class, $mockService);

        $this->artisan('report:generate-daily', ['date' => '2026-02-20'])
            ->assertSuccessful();
    }

    public function test_command_generates_report_for_given_date(): void
    {
        $mockReport = Mockery::mock(\App\Models\Report\DailyReport::class)->makePartial();
        $mockReport->id = 1;
        $mockReport->report_date = '2026-02-20';
        $mockReport->transferred_reviews = 100;
        $mockReport->failed_reviews = 5;
        $mockReport->shouldReceive('clientStatistics->count')->andReturn(3);

        $mockService = Mockery::mock(ReportGenerationService::class);
        $mockService->shouldReceive('checkReportExists')->andReturn(false);
        $mockService->shouldReceive('generateDailyReport')
            ->with(Mockery::type(Carbon::class), false)
            ->andReturn($mockReport);
        $this->app->instance(ReportGenerationService::class, $mockService);

        $this->artisan('report:generate-daily', ['date' => '2026-02-20'])
            ->assertSuccessful();
    }

    public function test_command_sends_slack_alert_on_failure(): void
    {
        Http::fake();

        config(['services.slack.webhook_url' => 'https://hooks.slack.com/test']);

        $mockService = Mockery::mock(ReportGenerationService::class);
        $mockService->shouldReceive('checkReportExists')->andReturn(false);
        $mockService->shouldReceive('generateDailyReport')
            ->andThrow(new \Exception('MongoDB 연결 실패'));
        $this->app->instance(ReportGenerationService::class, $mockService);

        $this->artisan('report:generate-daily', ['date' => '2026-02-20'])
            ->assertFailed();

        Http::assertSent(fn($request) => str_contains($request->url(), 'hooks.slack.com'));
    }

    public function test_command_uses_yesterday_when_no_date_given(): void
    {
        $yesterday = Carbon::yesterday()->format('Y-m-d');

        $mockService = Mockery::mock(ReportGenerationService::class);
        $mockService->shouldReceive('checkReportExists')
            ->with(Mockery::on(fn(Carbon $d) => $d->format('Y-m-d') === $yesterday))
            ->andReturn(true);
        $this->app->instance(ReportGenerationService::class, $mockService);

        $this->artisan('report:generate-daily')
            ->assertSuccessful();
    }
}
```

**Step 2: 테스트 실행 — 실패 확인**

```bash
vendor/bin/phpunit tests/Feature/GenerateDailyReportCommandTest.php --testdox
```

Expected: FAIL — `Command report:generate-daily not found`

**Step 3: 구현**

`app/Console/Commands/GenerateDailyReportCommand.php` 신규 생성:

```php
<?php

namespace App\Console\Commands;

use App\Services\Report\ReportGenerationService;
use Carbon\Carbon;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;

class GenerateDailyReportCommand extends Command
{
    protected $signature = 'report:generate-daily
                            {date? : 리포트 생성 날짜 (Y-m-d). 미지정 시 어제}
                            {--force : 기존 리포트가 있어도 강제 재생성}';

    protected $description = '지정 날짜의 일간 리포트를 생성합니다.';

    public function handle(ReportGenerationService $reportService): int
    {
        $date         = $this->resolveDate();
        $forceRebuild = (bool) $this->option('force');

        $this->info("일간 리포트 생성 시작 [{$date->format('Y-m-d')}]");

        if ($reportService->checkReportExists($date) && !$forceRebuild) {
            $this->info("리포트가 이미 존재합니다. skip (--force 옵션으로 재생성 가능)");
            return self::SUCCESS;
        }

        try {
            $report = $reportService->generateDailyReport($date, $forceRebuild);

            if (!$report) {
                $this->warn("이관 건수 0 — 리포트를 생성하지 않았습니다.");
                return self::SUCCESS;
            }

            $this->info("리포트 생성 완료 [ID: {$report->id}, 이관: {$report->transferred_reviews}, 실패: {$report->failed_reviews}]");
            $this->info("고객사 수: {$report->clientStatistics()->count()}");

            return self::SUCCESS;
        } catch (\Exception $e) {
            $message = $e->getMessage();
            Log::error("GenerateDailyReportCommand: 실패", ['date' => $date->format('Y-m-d'), 'error' => $message]);
            $this->error("리포트 생성 실패: {$message}");

            $this->notifySlack($date, $message);

            return self::FAILURE;
        }
    }

    private function resolveDate(): Carbon
    {
        $dateStr = $this->argument('date');

        if (!$dateStr) {
            return Carbon::yesterday();
        }

        return Carbon::createFromFormat('Y-m-d', $dateStr)->startOfDay();
    }

    private function notifySlack(Carbon $date, string $errorMessage): void
    {
        $webhookUrl = config('services.slack.webhook_url');

        if (!$webhookUrl) {
            return;
        }

        Http::post($webhookUrl, [
            'text' => implode("\n", [
                '❌ 일일 리포트 생성 실패',
                "날짜: {$date->format('Y-m-d')}",
                "오류: {$errorMessage}",
                '서버: ' . config('app.url'),
            ]),
        ]);
    }
}
```

**Step 4: `config/services.php`에 Slack webhook 추가**

`config/services.php`를 열어서 기존 서비스 배열 안에 추가:

```php
'slack' => [
    'webhook_url' => env('SLACK_WEBHOOK'),
],
```

**Step 5: `.env.example`에 SLACK_WEBHOOK 추가**

이미 없다면 `.env.example` 하단에 추가:

```
SLACK_WEBHOOK=
```

**Step 6: 테스트 통과 확인**

```bash
vendor/bin/phpunit tests/Feature/GenerateDailyReportCommandTest.php --testdox
```

Expected: PASS (4 tests)

**Step 7: 커밋**

```bash
git add app/Console/Commands/GenerateDailyReportCommand.php \
        tests/Feature/GenerateDailyReportCommandTest.php \
        config/services.php \
        .env.example
git commit -m "feat(report): GenerateDailyReportCommand 구현 - 실패 시 Slack 알림 포함"
```

---

### Task 5: SVGW 스케줄러 등록

**Files:**
- Modify: `app/Console/Kernel.php:27-37`

**Step 1: 스케줄 추가**

`app/Console/Kernel.php`의 `schedule()` 메서드 안에 추가:

```php
        // 일간 리포트 생성 (매일 새벽 3시) — Phase 2 이관
        $schedule->command('report:generate-daily')
            ->dailyAt('03:00')
            ->withoutOverlapping()
            ->appendOutputTo(storage_path('logs/daily-report-generation.log'));
```

**Step 2: 전체 테스트 통과 확인**

```bash
vendor/bin/phpunit --testdox
```

Expected: 모든 테스트 PASS

**Step 3: 커밋**

```bash
git add app/Console/Kernel.php
git commit -m "feat(report): 일간 리포트 생성 스케줄러 등록 (매일 03:00)"
```

---

### Task 6: sv-nova-master 스케줄러 제거

**중요:** SVGW 배포 완료 후 즉시 실행. 중복 실행 방지.

**Files:**
- Modify: `/opt/SeoulVentures/regle/sv-nova-master/app/Console/Kernel.php`

**Step 1: sv-nova-master Kernel.php에서 report:generate-daily 스케줄 제거**

`sv-nova-master/app/Console/Kernel.php`에서 아래 블록을 삭제:

```php
        // 매일 새벽 3시에 어제 날짜의 일간 리포트 생성
        $schedule->command('report:generate-daily')
            ->dailyAt('03:00')
            ->withoutOverlapping()
            ->appendOutputTo(storage_path('logs/daily-report-generation.log'));
```

삭제 후 `schedule()` 메서드는 `report:send-notification`만 남는다:

```php
    protected function schedule(Schedule $schedule): void
    {
        // 월요일과 목요일 오전 9시에 일간 리포트 알림톡 발송
        $schedule->command('report:send-notification')
            ->weekdays()
            ->at('09:00')
            ->withoutOverlapping()
            ->appendOutputTo(storage_path('logs/daily-report-notification.log'));
    }
```

**Step 2: sv-nova-master 커밋 및 푸시**

```bash
cd /opt/SeoulVentures/regle/sv-nova-master
git add app/Console/Kernel.php
git commit -m "chore: report:generate-daily 스케줄 제거 (SVGW로 이관됨)"
git push
```

**Step 3: regle 모노레포에서 sv-nova-master 서브모듈 업데이트**

```bash
cd /opt/SeoulVentures/regle
git add sv-nova-master
git commit -m "chore: sv-nova-master 서브모듈 업데이트 - report:generate-daily 스케줄 제거"
git push
```

---

### Task 7: SVGW PR 생성 및 배포

**Step 1: SeoulVenturesGroupware 브랜치 확인**

```bash
cd /opt/SeoulVentures/regle/SeoulVenturesGroupware
git log --oneline master..HEAD
```

**Step 2: PR 생성**

```bash
gh pr create \
  --title "feat(report): Phase 2 - 일간 리포트 생성 이관 (report:generate-daily)" \
  --body "$(cat <<'EOF'
## Summary

- sv-nova-master의 \`report:generate-daily\` 스케줄 명령어를 SVGW로 이관
- \`MongoDBCollectionResolver\`에 report용 컬렉션 이름 메서드 추가
- \`ReviewDataCollectionService\`: MongoDB 업로드 통계 집계
- \`ReportGenerationService\`: sv_nova DB에 daily_reports 생성/갱신
- 실패 시 Slack 알림 (SLACK_WEBHOOK)
- sv-nova-master 스케줄러에서 즉시 제거

## Test plan

- [ ] PHPUnit 전체 통과 확인
- [ ] dev 배포 후 \`php artisan report:generate-daily 2026-02-19\` 수동 실행
- [ ] daily_reports 테이블에 레코드 생성 확인
- [ ] 03:00 스케줄 등록 확인 (\`php artisan schedule:list\`)

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

**Step 3: 배포 완료 후 수동 검증**

```bash
# EC2에 SSH 접속 후
ssh -i ~/.ssh/SeoulVentures.pem ubuntu@3.34.97.42

# dev 환경에서 어제 날짜 리포트 수동 생성
cd /var/www/groupware-dev-current
sudo -u www-data php artisan report:generate-daily

# 스케줄 목록 확인
sudo -u www-data php artisan schedule:list
```

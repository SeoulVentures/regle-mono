# sv-nova-master 마이그레이션 Phase 1: 통계 대시보드 구현 계획

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** sv-nova-master의 ReviewReportDashboard를 SeoulVenturesGroupware의 `/dashboard` 페이지로 이관하여, 운영팀이 리뷰 수집 통계를 SVGW에서 확인할 수 있게 한다.

**Architecture:**
- SVGW 백엔드에 sv_nova_master DB 읽기 전용 연결을 추가하여 `daily_reports`, `daily_client_statistics`, `daily_driver_statistics` 테이블에 접근한다.
- 신규 `DashboardController`가 통계 API를 제공하고, 프론트엔드 `dashboard.vue`가 ApexCharts로 시각화한다.
- 날짜 범위 필터(기본: 최근 30일)를 지원한다.

**Tech Stack:**
- Backend: Laravel 12, PHP 8.2, MySQL (sv_nova_master DB 읽기 전용 연결)
- Frontend: Vue 3 + TypeScript, Vuetify 3, ApexCharts (vue3-apexcharts 1.5.3)
- Test: PHPUnit (Feature tests, SQLite in-memory)

---

## 사전 지식

### 프로젝트 경로
- **SVGW 루트:** `/opt/SeoulVentures/regle/SeoulVenturesGroupware/`
- **프론트엔드 루트:** `/opt/SeoulVentures/regle/SeoulVenturesGroupware/frontend/`

### SVGW 패턴 참고 파일
- **API 엔티티 패턴:** `frontend/resources/ts/api/entities/review/uploadSummary.ts`
- **Vue 페이지 패턴:** `frontend/resources/ts/pages/review/upload-summary/index.vue`
- **ApexCharts 사용 예:** `frontend/resources/ts/pages/review/error-stats/index.vue`
- **네비게이션 메뉴:** `frontend/resources/ts/navigation/vertical/index.ts`

### daily_reports 테이블 스키마 (sv_nova_master DB)
```
id, report_date (date, unique), total_clients, active_clients,
total_reviews, transferred_reviews, failed_reviews,
success_rate (decimal 5,2), status_summary (json),
service_summary (json), top_clients (json),
top_failure_clients (json), created_at, updated_at
```

### daily_client_statistics 테이블 스키마 (sv_nova_master DB)
```
id, daily_report_id (FK→daily_reports), client_id, client_name,
total_reviews, transferred_reviews, failed_reviews,
success_rate (decimal 5,2), status_summary, service_summary,
driver_summary, error_details (json), created_at, updated_at
```

### daily_driver_statistics 테이블 스키마 (sv_nova_master DB)
```
id, daily_report_id (FK→daily_reports), driver_name,
total_reviews, transferred_reviews, failed_reviews,
success_rate (decimal 5,2), created_at, updated_at
```

---

## Task 1: sv_nova DB 연결 추가

**Files:**
- Modify: `config/database.php`
- Modify: `.env.example`

### Step 1: config/database.php 수정

`config/database.php`의 `connections` 배열에 추가:

```php
'sv_nova' => [
    'driver' => 'mysql',
    'url' => env('SV_NOVA_DATABASE_URL'),
    'host' => env('SV_NOVA_DB_HOST', '127.0.0.1'),
    'port' => env('SV_NOVA_DB_PORT', '3306'),
    'database' => env('SV_NOVA_DB_DATABASE', 'sv_nova_master'),
    'username' => env('SV_NOVA_DB_USERNAME', 'forge'),
    'password' => env('SV_NOVA_DB_PASSWORD', ''),
    'unix_socket' => env('SV_NOVA_DB_SOCKET', ''),
    'charset' => 'utf8mb4',
    'collation' => 'utf8mb4_unicode_ci',
    'prefix' => '',
    'prefix_indexes' => true,
    'strict' => false,
    'engine' => null,
    'options' => extension_loaded('pdo_mysql') ? array_filter([
        PDO::MYSQL_ATTR_SSL_CA => env('MYSQL_ATTR_SSL_CA'),
    ]) : [],
],
```

위치: `'mysql' => [...]` 블록 바로 아래에 추가.

### Step 2: .env.example 수정

`.env.example`에 아래 항목 추가:

```
SV_NOVA_DB_HOST=127.0.0.1
SV_NOVA_DB_PORT=3306
SV_NOVA_DB_DATABASE=sv_nova_master
SV_NOVA_DB_USERNAME=forge
SV_NOVA_DB_PASSWORD=
```

### Step 3: 커밋

```bash
git -C /opt/SeoulVentures/regle/SeoulVenturesGroupware add config/database.php .env.example
git -C /opt/SeoulVentures/regle/SeoulVenturesGroupware commit -m "feat(dashboard): sv_nova DB 연결 추가"
```

---

## Task 2: 읽기 전용 모델 추가

**Files:**
- Create: `app/Models/Report/DailyReport.php`
- Create: `app/Models/Report/DailyClientStatistic.php`
- Create: `app/Models/Report/DailyDriverStatistic.php`

### Step 1: DailyReport 모델 작성

`app/Models/Report/DailyReport.php`:

```php
<?php

namespace App\Models\Report;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

class DailyReport extends Model
{
    protected $connection = 'sv_nova';
    protected $table = 'daily_reports';

    protected $casts = [
        'report_date' => 'date',
        'total_clients' => 'integer',
        'active_clients' => 'integer',
        'total_reviews' => 'integer',
        'transferred_reviews' => 'integer',
        'failed_reviews' => 'integer',
        'success_rate' => 'float',
        'status_summary' => 'json',
        'service_summary' => 'json',
        'top_clients' => 'json',
        'top_failure_clients' => 'json',
    ];

    public function clientStatistics(): HasMany
    {
        return $this->hasMany(DailyClientStatistic::class, 'daily_report_id');
    }

    public function driverStatistics(): HasMany
    {
        return $this->hasMany(DailyDriverStatistic::class, 'daily_report_id');
    }
}
```

### Step 2: DailyClientStatistic 모델 작성

`app/Models/Report/DailyClientStatistic.php`:

```php
<?php

namespace App\Models\Report;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class DailyClientStatistic extends Model
{
    protected $connection = 'sv_nova';
    protected $table = 'daily_client_statistics';

    protected $casts = [
        'total_reviews' => 'integer',
        'transferred_reviews' => 'integer',
        'failed_reviews' => 'integer',
        'success_rate' => 'float',
        'status_summary' => 'json',
        'service_summary' => 'json',
        'driver_summary' => 'json',
        'error_details' => 'json',
    ];

    public function dailyReport(): BelongsTo
    {
        return $this->belongsTo(DailyReport::class, 'daily_report_id');
    }
}
```

### Step 3: DailyDriverStatistic 모델 작성

`app/Models/Report/DailyDriverStatistic.php`:

```php
<?php

namespace App\Models\Report;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class DailyDriverStatistic extends Model
{
    protected $connection = 'sv_nova';
    protected $table = 'daily_driver_statistics';

    protected $casts = [
        'total_reviews' => 'integer',
        'transferred_reviews' => 'integer',
        'failed_reviews' => 'integer',
        'success_rate' => 'float',
    ];

    public function dailyReport(): BelongsTo
    {
        return $this->belongsTo(DailyReport::class, 'daily_report_id');
    }
}
```

### Step 4: 커밋

```bash
git -C /opt/SeoulVentures/regle/SeoulVenturesGroupware add app/Models/Report/
git -C /opt/SeoulVentures/regle/SeoulVenturesGroupware commit -m "feat(dashboard): DailyReport 읽기 전용 모델 추가"
```

---

## Task 3: DashboardController 추가 (백엔드 API)

**Files:**
- Create: `app/Http/Controllers/DashboardController.php`
- Create: `tests/Feature/DashboardControllerTest.php`

### Step 1: 테스트 파일 작성 (TDD - RED)

`tests/Feature/DashboardControllerTest.php`:

```php
<?php

namespace Tests\Feature;

use Tests\TestCase;

class DashboardControllerTest extends TestCase
{
    public function test_metrics_endpoint_returns_expected_structure(): void
    {
        // 인증 없이 접근 시 401
        $response = $this->getJson('/api/dashboard/metrics');
        $response->assertStatus(401);
    }

    public function test_collection_chart_endpoint_requires_auth(): void
    {
        $response = $this->getJson('/api/dashboard/charts/collection');
        $response->assertStatus(401);
    }

    public function test_success_rate_chart_endpoint_requires_auth(): void
    {
        $response = $this->getJson('/api/dashboard/charts/success-rate');
        $response->assertStatus(401);
    }

    public function test_client_distribution_endpoint_requires_auth(): void
    {
        $response = $this->getJson('/api/dashboard/charts/client-distribution');
        $response->assertStatus(401);
    }

    public function test_driver_distribution_endpoint_requires_auth(): void
    {
        $response = $this->getJson('/api/dashboard/charts/driver-distribution');
        $response->assertStatus(401);
    }
}
```

### Step 2: 테스트 실행 (실패 확인)

```bash
cd /opt/SeoulVentures/regle/SeoulVenturesGroupware && php artisan test tests/Feature/DashboardControllerTest.php
```

Expected: FAIL (라우트 없음으로 404)

### Step 3: DashboardController 구현

`app/Http/Controllers/DashboardController.php`:

```php
<?php

namespace App\Http\Controllers;

use App\Models\Report\DailyClientStatistic;
use App\Models\Report\DailyDriverStatistic;
use App\Models\Report\DailyReport;
use App\Models\Review\Client;
use Carbon\Carbon;
use Illuminate\Http\Request;

class DashboardController extends Controller
{
    /**
     * 요약 메트릭 반환
     * - 오늘/주간/월간 수집량
     * - 활성 클라이언트 수
     * - 전일/전주/전월 대비 수치
     */
    public function metrics(): array
    {
        $today = now()->format('Y-m-d');
        $yesterday = now()->subDay()->format('Y-m-d');

        $todayCount = DailyReport::where('report_date', $today)->sum('total_reviews');
        $yesterdayCount = DailyReport::where('report_date', $yesterday)->sum('total_reviews');

        $currentWeek = DailyReport::whereBetween('report_date', [
            now()->startOfWeek()->format('Y-m-d'),
            $today,
        ])->sum('total_reviews');

        $previousWeek = DailyReport::whereBetween('report_date', [
            now()->subWeek()->startOfWeek()->format('Y-m-d'),
            now()->subWeek()->endOfWeek()->format('Y-m-d'),
        ])->sum('total_reviews');

        $currentMonth = DailyReport::whereBetween('report_date', [
            now()->startOfMonth()->format('Y-m-d'),
            $today,
        ])->sum('total_reviews');

        $previousMonth = DailyReport::whereMonth('report_date', now()->subMonth()->month)
            ->whereYear('report_date', now()->subMonth()->year)
            ->sum('total_reviews');

        $activeClients = Client::where('monthly_state', 'Y')
            ->where('widget_enabled', 'Y')
            ->count();

        return [
            'today' => ['count' => $todayCount, 'previous' => $yesterdayCount],
            'weekly' => ['count' => $currentWeek, 'previous' => $previousWeek],
            'monthly' => ['count' => $currentMonth, 'previous' => $previousMonth],
            'active_clients' => $activeClients,
        ];
    }

    /**
     * 수집량 추이 차트 데이터 (Bar)
     * Query params: start_date, end_date (Y-m-d)
     */
    public function collectionChart(Request $request): array
    {
        $query = DailyReport::query();
        $this->applyDateFilters($query, $request);

        $reports = $query->orderBy('report_date')
            ->select('transferred_reviews', 'report_date')
            ->get();

        return [
            'labels' => $reports->pluck('report_date')
                ->map(fn ($date) => Carbon::parse($date)->format('m-d'))
                ->toArray(),
            'series' => [
                [
                    'name' => '이관 리뷰 수',
                    'data' => $reports->pluck('transferred_reviews')->toArray(),
                ],
            ],
        ];
    }

    /**
     * 성공률 추이 차트 데이터 (Line)
     * Query params: start_date, end_date (Y-m-d)
     */
    public function successRateChart(Request $request): array
    {
        $query = DailyReport::query();
        $this->applyDateFilters($query, $request);

        $reports = $query->selectRaw(
            'report_date, CASE WHEN total_reviews = 0 THEN 0 ELSE (transferred_reviews / total_reviews) * 100 END as success_rate'
        )->orderBy('report_date')->get();

        return [
            'labels' => $reports->pluck('report_date')
                ->map(fn ($date) => Carbon::parse($date)->format('m-d'))
                ->toArray(),
            'series' => [
                [
                    'name' => '성공률 (%)',
                    'data' => $reports->pluck('success_rate')
                        ->map(fn ($v) => round((float) $v, 2))
                        ->toArray(),
                ],
            ],
        ];
    }

    /**
     * 클라이언트별 분포 차트 데이터 (Donut)
     * Query params: start_date, end_date (Y-m-d)
     */
    public function clientDistributionChart(Request $request): array
    {
        $query = DailyClientStatistic::query();

        $startDate = $request->query('start_date', now()->subDays(30)->format('Y-m-d'));
        $endDate = $request->query('end_date', now()->format('Y-m-d'));

        $query->whereHas('dailyReport', function ($q) use ($startDate, $endDate) {
            $q->whereBetween('report_date', [$startDate, $endDate]);
        });

        $statistics = $query->selectRaw('client_name, SUM(transferred_reviews) as total')
            ->groupBy('client_name')
            ->orderByDesc('total')
            ->limit(10)
            ->get();

        return [
            'labels' => $statistics->pluck('client_name')->toArray(),
            'series' => $statistics->pluck('total')->map(fn ($v) => (int) $v)->toArray(),
        ];
    }

    /**
     * 드라이버별 분포 차트 데이터 (Donut)
     * Query params: start_date, end_date (Y-m-d)
     */
    public function driverDistributionChart(Request $request): array
    {
        $query = DailyDriverStatistic::query();

        $startDate = $request->query('start_date', now()->subDays(30)->format('Y-m-d'));
        $endDate = $request->query('end_date', now()->format('Y-m-d'));

        $query->whereHas('dailyReport', function ($q) use ($startDate, $endDate) {
            $q->whereBetween('report_date', [$startDate, $endDate]);
        });

        $statistics = $query->selectRaw('driver_name, SUM(transferred_reviews) as total')
            ->groupBy('driver_name')
            ->orderByDesc('total')
            ->limit(10)
            ->get();

        return [
            'labels' => $statistics->pluck('driver_name')->toArray(),
            'series' => $statistics->pluck('total')->map(fn ($v) => (int) $v)->toArray(),
        ];
    }

    private function applyDateFilters($query, Request $request): void
    {
        $startDate = $request->query('start_date', now()->subDays(30)->format('Y-m-d'));
        $endDate = $request->query('end_date', now()->format('Y-m-d'));

        $query->whereBetween('report_date', [$startDate, $endDate]);
    }
}
```

### Step 4: API 라우트 추가

`routes/api.php`의 `Route::middleware('auth:sanctum')->group` 블록 안에 추가:

```php
// Dashboard
Route::prefix('dashboard')->group(function () {
    Route::get('metrics', [DashboardController::class, 'metrics']);
    Route::get('charts/collection', [DashboardController::class, 'collectionChart']);
    Route::get('charts/success-rate', [DashboardController::class, 'successRateChart']);
    Route::get('charts/client-distribution', [DashboardController::class, 'clientDistributionChart']);
    Route::get('charts/driver-distribution', [DashboardController::class, 'driverDistributionChart']);
});
```

`routes/api.php` 상단 use 블록에 추가:
```php
use App\Http\Controllers\DashboardController;
```

### Step 5: 테스트 재실행 (통과 확인)

```bash
cd /opt/SeoulVentures/regle/SeoulVenturesGroupware && php artisan test tests/Feature/DashboardControllerTest.php
```

Expected: PASS (5개 테스트 모두 401 응답 확인)

### Step 6: 커밋

```bash
git -C /opt/SeoulVentures/regle/SeoulVenturesGroupware add \
  app/Http/Controllers/DashboardController.php \
  routes/api.php \
  tests/Feature/DashboardControllerTest.php
git -C /opt/SeoulVentures/regle/SeoulVenturesGroupware commit -m "feat(dashboard): 통계 대시보드 API 추가"
```

---

## Task 4: 프론트엔드 API 엔티티 추가

**Files:**
- Create: `frontend/resources/ts/api/entities/review/dashboard.ts`

### Step 1: dashboard.ts 작성

`frontend/resources/ts/api/entities/review/dashboard.ts`:

```typescript
import { type ApiResponse, get } from '@/api'

export interface DashboardMetric {
  count: number
  previous: number
}

export interface DashboardMetrics {
  today: DashboardMetric
  weekly: DashboardMetric
  monthly: DashboardMetric
  active_clients: number
}

export interface ChartSeries {
  name: string
  data: number[]
}

export interface TimeSeriesChartData {
  labels: string[]
  series: ChartSeries[]
}

export interface DistributionChartData {
  labels: string[]
  series: number[]
}

export interface DashboardChartParams {
  start_date?: string
  end_date?: string
}

export const dashboardApi = {
  getMetrics: (): Promise<ApiResponse<DashboardMetrics>> =>
    get('/dashboard/metrics'),

  getCollectionChart: (params?: DashboardChartParams): Promise<ApiResponse<TimeSeriesChartData>> =>
    get('/dashboard/charts/collection', params),

  getSuccessRateChart: (params?: DashboardChartParams): Promise<ApiResponse<TimeSeriesChartData>> =>
    get('/dashboard/charts/success-rate', params),

  getClientDistributionChart: (params?: DashboardChartParams): Promise<ApiResponse<DistributionChartData>> =>
    get('/dashboard/charts/client-distribution', params),

  getDriverDistributionChart: (params?: DashboardChartParams): Promise<ApiResponse<DistributionChartData>> =>
    get('/dashboard/charts/driver-distribution', params),
}

export default dashboardApi
```

### Step 2: 커밋

```bash
git -C /opt/SeoulVentures/regle/SeoulVenturesGroupware add frontend/resources/ts/api/entities/review/dashboard.ts
git -C /opt/SeoulVentures/regle/SeoulVenturesGroupware commit -m "feat(dashboard): 대시보드 API 엔티티 추가"
```

---

## Task 5: dashboard.vue 페이지 업데이트

**Files:**
- Modify: `frontend/resources/ts/pages/dashboard.vue`

### Step 1: 기존 dashboard.vue 전체 교체

`frontend/resources/ts/pages/dashboard.vue`:

```vue
<script setup lang="ts">
import { onMounted, ref } from 'vue'
import { useTheme } from 'vuetify'
import { hexToRgb } from '@core/utils/colorConverter'
import {
  type DashboardMetrics,
  type DistributionChartData,
  type TimeSeriesChartData,
  dashboardApi,
} from '@/api/entities/review/dashboard'

definePage({
  meta: {
    title: '대시보드',
    action: 'read',
    subject: 'Dashboard',
  },
})

const { handleError } = useErrorHandler()
const vuetifyTheme = useTheme()

// 날짜 필터
const startDate = ref(
  new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString().split('T')[0],
)
const endDate = ref(new Date().toISOString().split('T')[0])

// 상태
const metricsLoading = ref(false)
const chartsLoading = ref(false)

const metrics = ref<DashboardMetrics | null>(null)
const collectionChart = ref<TimeSeriesChartData | null>(null)
const successRateChart = ref<TimeSeriesChartData | null>(null)
const clientChart = ref<DistributionChartData | null>(null)
const driverChart = ref<DistributionChartData | null>(null)

// 색상 팔레트
const CHART_COLORS = [
  '#0EA5E9', '#F59E0B', '#10B981', '#6366F1', '#EC4899',
  '#8B5CF6', '#0891B2', '#16A34A', '#D97706', '#DC2626',
]

// 메트릭 변화율 계산
function getChangeRate(current: number, previous: number): number {
  if (previous === 0)
    return 0
  return Math.round(((current - previous) / previous) * 100)
}

function getChangeColor(current: number, previous: number): string {
  if (current > previous)
    return 'success'
  if (current < previous)
    return 'error'
  return 'secondary'
}

// Bar 차트 옵션 (수집량 추이)
function getBarChartOptions(data: TimeSeriesChartData) {
  const colors = `rgba(${hexToRgb(vuetifyTheme.current.value.colors['on-surface'])},0.87)`

  return {
    chart: { type: 'bar', toolbar: { show: false }, zoom: { enabled: false } },
    plotOptions: { bar: { borderRadius: 4, columnWidth: '60%' } },
    xaxis: {
      categories: data.labels,
      labels: { style: { colors } },
    },
    yaxis: { labels: { style: { colors } } },
    colors: ['#3B82F6'],
    dataLabels: { enabled: false },
    tooltip: { theme: vuetifyTheme.name.value },
    grid: { borderColor: `rgba(${hexToRgb(vuetifyTheme.current.value.colors['on-surface'])},0.12)` },
  }
}

// Line 차트 옵션 (성공률)
function getLineChartOptions(data: TimeSeriesChartData) {
  const colors = `rgba(${hexToRgb(vuetifyTheme.current.value.colors['on-surface'])},0.87)`

  return {
    chart: { type: 'line', toolbar: { show: false }, zoom: { enabled: false } },
    stroke: { curve: 'smooth', width: 3 },
    xaxis: {
      categories: data.labels,
      labels: { style: { colors } },
    },
    yaxis: {
      min: 0,
      max: 100,
      labels: {
        style: { colors },
        formatter: (v: number) => `${v.toFixed(0)}%`,
      },
    },
    colors: ['#10B981'],
    dataLabels: { enabled: false },
    tooltip: {
      theme: vuetifyTheme.name.value,
      y: { formatter: (v: number) => `${v.toFixed(2)}%` },
    },
    fill: {
      type: 'gradient',
      gradient: { shadeIntensity: 0.8, opacityFrom: 0.4, opacityTo: 0.1 },
    },
    grid: { borderColor: `rgba(${hexToRgb(vuetifyTheme.current.value.colors['on-surface'])},0.12)` },
  }
}

// Donut 차트 옵션 (분포)
function getDonutChartOptions(data: DistributionChartData) {
  const secondaryText = `rgba(${hexToRgb(vuetifyTheme.current.value.colors['on-surface'])},0.6)`

  return {
    chart: { type: 'donut' },
    labels: data.labels,
    colors: CHART_COLORS.slice(0, data.labels.length),
    legend: {
      position: 'bottom',
      fontSize: '13px',
      labels: { colors: secondaryText },
    },
    dataLabels: {
      formatter: (val: number) => `${Math.round(val)}%`,
    },
    stroke: { width: 0 },
    tooltip: { theme: vuetifyTheme.name.value },
  }
}

// 데이터 로드
async function loadMetrics() {
  metricsLoading.value = true
  try {
    const res = await dashboardApi.getMetrics()
    metrics.value = res.data
  }
  catch (e) {
    handleError(e)
  }
  finally {
    metricsLoading.value = false
  }
}

async function loadCharts() {
  chartsLoading.value = true
  const params = { start_date: startDate.value, end_date: endDate.value }

  try {
    const [collection, successRate, clientDist, driverDist] = await Promise.all([
      dashboardApi.getCollectionChart(params),
      dashboardApi.getSuccessRateChart(params),
      dashboardApi.getClientDistributionChart(params),
      dashboardApi.getDriverDistributionChart(params),
    ])

    collectionChart.value = collection.data
    successRateChart.value = successRate.data
    clientChart.value = clientDist.data
    driverChart.value = driverDist.data
  }
  catch (e) {
    handleError(e)
  }
  finally {
    chartsLoading.value = false
  }
}

async function refresh() {
  await Promise.all([loadMetrics(), loadCharts()])
}

onMounted(refresh)
</script>

<template>
  <div>
    <!-- 날짜 필터 -->
    <VRow class="mb-4">
      <VCol
        cols="12"
        md="4"
      >
        <AppDateTimePicker
          v-model="startDate"
          label="시작일"
          :config="{ dateFormat: 'Y-m-d' }"
        />
      </VCol>
      <VCol
        cols="12"
        md="4"
      >
        <AppDateTimePicker
          v-model="endDate"
          label="종료일"
          :config="{ dateFormat: 'Y-m-d' }"
        />
      </VCol>
      <VCol
        cols="12"
        md="4"
        class="d-flex align-center"
      >
        <VBtn
          color="primary"
          :loading="chartsLoading"
          @click="loadCharts"
        >
          조회
        </VBtn>
      </VCol>
    </VRow>

    <!-- 메트릭 카드 -->
    <VRow class="mb-4">
      <VCol
        v-if="metricsLoading"
        cols="12"
      >
        <VProgressLinear indeterminate />
      </VCol>
      <template v-else-if="metrics">
        <!-- 오늘 수집량 -->
        <VCol
          cols="12"
          sm="6"
          md="3"
        >
          <VCard>
            <VCardText>
              <div class="d-flex justify-space-between align-center mb-2">
                <span class="text-body-2 text-medium-emphasis">오늘 수집량</span>
                <VIcon
                  icon="tabler-download"
                  size="24"
                  color="primary"
                />
              </div>
              <div class="text-h5 font-weight-bold mb-1">
                {{ metrics.today.count.toLocaleString() }}
              </div>
              <VChip
                :color="getChangeColor(metrics.today.count, metrics.today.previous)"
                size="small"
                variant="tonal"
              >
                {{ getChangeRate(metrics.today.count, metrics.today.previous) > 0 ? '+' : '' }}{{ getChangeRate(metrics.today.count, metrics.today.previous) }}% vs 전일
              </VChip>
            </VCardText>
          </VCard>
        </VCol>

        <!-- 주간 수집량 -->
        <VCol
          cols="12"
          sm="6"
          md="3"
        >
          <VCard>
            <VCardText>
              <div class="d-flex justify-space-between align-center mb-2">
                <span class="text-body-2 text-medium-emphasis">주간 수집량</span>
                <VIcon
                  icon="tabler-calendar-week"
                  size="24"
                  color="info"
                />
              </div>
              <div class="text-h5 font-weight-bold mb-1">
                {{ metrics.weekly.count.toLocaleString() }}
              </div>
              <VChip
                :color="getChangeColor(metrics.weekly.count, metrics.weekly.previous)"
                size="small"
                variant="tonal"
              >
                {{ getChangeRate(metrics.weekly.count, metrics.weekly.previous) > 0 ? '+' : '' }}{{ getChangeRate(metrics.weekly.count, metrics.weekly.previous) }}% vs 전주
              </VChip>
            </VCardText>
          </VCard>
        </VCol>

        <!-- 월간 수집량 -->
        <VCol
          cols="12"
          sm="6"
          md="3"
        >
          <VCard>
            <VCardText>
              <div class="d-flex justify-space-between align-center mb-2">
                <span class="text-body-2 text-medium-emphasis">월간 수집량</span>
                <VIcon
                  icon="tabler-calendar-month"
                  size="24"
                  color="success"
                />
              </div>
              <div class="text-h5 font-weight-bold mb-1">
                {{ metrics.monthly.count.toLocaleString() }}
              </div>
              <VChip
                :color="getChangeColor(metrics.monthly.count, metrics.monthly.previous)"
                size="small"
                variant="tonal"
              >
                {{ getChangeRate(metrics.monthly.count, metrics.monthly.previous) > 0 ? '+' : '' }}{{ getChangeRate(metrics.monthly.count, metrics.monthly.previous) }}% vs 전월
              </VChip>
            </VCardText>
          </VCard>
        </VCol>

        <!-- 활성 클라이언트 -->
        <VCol
          cols="12"
          sm="6"
          md="3"
        >
          <VCard>
            <VCardText>
              <div class="d-flex justify-space-between align-center mb-2">
                <span class="text-body-2 text-medium-emphasis">활성 클라이언트</span>
                <VIcon
                  icon="tabler-users"
                  size="24"
                  color="warning"
                />
              </div>
              <div class="text-h5 font-weight-bold">
                {{ metrics.active_clients.toLocaleString() }}
              </div>
            </VCardText>
          </VCard>
        </VCol>
      </template>
    </VRow>

    <!-- 차트 행 1: 수집량 추이 + 성공률 -->
    <VRow class="mb-4">
      <VCol
        cols="12"
        md="8"
      >
        <VCard>
          <VCardTitle class="pa-4">
            일별 이관 리뷰 수
          </VCardTitle>
          <VDivider />
          <VCardText>
            <div
              v-if="chartsLoading"
              class="d-flex justify-center align-center"
              style="height: 300px;"
            >
              <VProgressCircular indeterminate />
            </div>
            <VueApexCharts
              v-else-if="collectionChart && collectionChart.series[0]?.data.length"
              type="bar"
              height="300"
              :options="getBarChartOptions(collectionChart)"
              :series="collectionChart.series"
            />
            <div
              v-else
              class="text-center text-medium-emphasis py-8"
            >
              데이터 없음
            </div>
          </VCardText>
        </VCard>
      </VCol>

      <VCol
        cols="12"
        md="4"
      >
        <VCard>
          <VCardTitle class="pa-4">
            이관 성공률 (%)
          </VCardTitle>
          <VDivider />
          <VCardText>
            <div
              v-if="chartsLoading"
              class="d-flex justify-center align-center"
              style="height: 300px;"
            >
              <VProgressCircular indeterminate />
            </div>
            <VueApexCharts
              v-else-if="successRateChart && successRateChart.series[0]?.data.length"
              type="line"
              height="300"
              :options="getLineChartOptions(successRateChart)"
              :series="successRateChart.series"
            />
            <div
              v-else
              class="text-center text-medium-emphasis py-8"
            >
              데이터 없음
            </div>
          </VCardText>
        </VCard>
      </VCol>
    </VRow>

    <!-- 차트 행 2: 클라이언트별 + 드라이버별 분포 -->
    <VRow>
      <VCol
        cols="12"
        md="6"
      >
        <VCard>
          <VCardTitle class="pa-4">
            클라이언트별 분포 (상위 10)
          </VCardTitle>
          <VDivider />
          <VCardText>
            <div
              v-if="chartsLoading"
              class="d-flex justify-center align-center"
              style="height: 300px;"
            >
              <VProgressCircular indeterminate />
            </div>
            <VueApexCharts
              v-else-if="clientChart && clientChart.series.length"
              type="donut"
              height="300"
              :options="getDonutChartOptions(clientChart)"
              :series="clientChart.series"
            />
            <div
              v-else
              class="text-center text-medium-emphasis py-8"
            >
              데이터 없음
            </div>
          </VCardText>
        </VCard>
      </VCol>

      <VCol
        cols="12"
        md="6"
      >
        <VCard>
          <VCardTitle class="pa-4">
            드라이버별 분포 (상위 10)
          </VCardTitle>
          <VDivider />
          <VCardText>
            <div
              v-if="chartsLoading"
              class="d-flex justify-center align-center"
              style="height: 300px;"
            >
              <VProgressCircular indeterminate />
            </div>
            <VueApexCharts
              v-else-if="driverChart && driverChart.series.length"
              type="donut"
              height="300"
              :options="getDonutChartOptions(driverChart)"
              :series="driverChart.series"
            />
            <div
              v-else
              class="text-center text-medium-emphasis py-8"
            >
              데이터 없음
            </div>
          </VCardText>
        </VCard>
      </VCol>
    </VRow>
  </div>
</template>
```

### Step 2: VueApexCharts 플러그인 등록 확인

`frontend/resources/ts/plugins/` 디렉토리에 apexcharts 플러그인이 등록되어 있는지 확인:

```bash
grep -r "VueApexCharts\|apexcharts" /opt/SeoulVentures/regle/SeoulVenturesGroupware/frontend/resources/ts/plugins/ --include="*.ts" -l
```

없으면 `frontend/resources/ts/plugins/apexcharts.ts` 생성:

```typescript
import VueApexCharts from 'vue3-apexcharts'
import type { App } from 'vue'

export default function (app: App) {
  app.component('VueApexCharts', VueApexCharts)
}
```

그리고 `frontend/resources/ts/plugins/index.ts`에 등록:
```typescript
import apexcharts from './apexcharts'
// ...
app.use(apexcharts) // 또는 플러그인 등록 방식에 맞게
```

기존 error-stats 페이지에서 이미 VueApexCharts를 사용 중이므로, 기존 등록 방식을 따르면 됨.

### Step 3: 빌드 확인

```bash
cd /opt/SeoulVentures/regle/SeoulVenturesGroupware && bun run build 2>&1 | tail -20
```

Expected: 에러 없이 빌드 완료

### Step 4: 커밋

```bash
git -C /opt/SeoulVentures/regle/SeoulVenturesGroupware add \
  frontend/resources/ts/pages/dashboard.vue
git -C /opt/SeoulVentures/regle/SeoulVenturesGroupware commit -m "feat(dashboard): 통계 대시보드 Vue 페이지 구현"
```

---

## Task 6: 수동 검증

### Step 1: 로컬 환경에서 .env 설정

`.env`에 sv_nova DB 연결 정보 추가:
```
SV_NOVA_DB_HOST=<실제 DB 호스트>
SV_NOVA_DB_DATABASE=sv_nova_master
SV_NOVA_DB_USERNAME=<유저>
SV_NOVA_DB_PASSWORD=<패스워드>
```

### Step 2: API 직접 확인

```bash
# 인증 토큰 획득 후
curl -H "Authorization: Bearer {token}" \
  http://localhost:8000/api/dashboard/metrics

curl -H "Authorization: Bearer {token}" \
  "http://localhost:8000/api/dashboard/charts/collection?start_date=2026-01-01&end_date=2026-02-20"
```

### Step 3: 브라우저에서 확인

- SVGW 개발 서버 실행 후 `/dashboard` 접속
- 날짜 필터 변경 → 차트 갱신 확인
- 메트릭 카드 수치 확인 (sv-nova-master ReviewReportDashboard와 수치 비교)

### Step 4: 최종 커밋 및 서브모듈 업데이트

```bash
# SeoulVenturesGroupware 서브모듈 커밋/푸시
git -C /opt/SeoulVentures/regle/SeoulVenturesGroupware push origin master

# 모노리포에서 서브모듈 참조 업데이트
git -C /opt/SeoulVentures/regle add SeoulVenturesGroupware
git -C /opt/SeoulVentures/regle commit -m "chore: SeoulVenturesGroupware 서브모듈 업데이트 - 통계 대시보드 Phase 1"
git -C /opt/SeoulVentures/regle push origin master
```

---

## 완료 기준

- [ ] `/dashboard` 접속 시 메트릭 카드 4개 표시 (오늘/주간/월간 수집량, 활성 클라이언트)
- [ ] 날짜 필터 적용 후 차트 4개 정상 렌더링
- [ ] sv-nova-master ReviewReportDashboard와 동일한 수치 확인
- [ ] PHPUnit Feature 테스트 5개 PASS
- [ ] bun run build 에러 없음

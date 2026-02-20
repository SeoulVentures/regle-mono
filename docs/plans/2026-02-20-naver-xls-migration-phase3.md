# Phase 3: NaverXls 임포트 이관 구현 계획

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** sv-nova-master의 NaverXls 파일 업로드 + ECS 임포트 기능을 SVGW로 이관하여 `/review/naver-xls` 페이지에서 운영 가능하게 한다.

**Architecture:** NaverXlsFile 모델을 sv_nova DB에 연결하고, RegleEcsService에 `importNaverFileS3()` 메서드를 추가한다. 백엔드 NaverXlsController는 S3 업로드·ECS 트리거·목록 조회·삭제를 담당하며, 프론트엔드는 Vue 3 + Vuetify 3 페이지로 구현한다.

**Tech Stack:** Laravel 12, PHP 8.4, Vue 3 + TypeScript + Vuetify 3, AWS S3 (`s3` disk), AWS ECS (`RegleEcsService`), sv_nova MySQL DB

---

## 참고 파일

| 역할 | 경로 |
|------|------|
| sv-nova-master 원본 모델 | `sv-nova-master/app/Models/NaverXlsFile.php` |
| sv-nova-master 원본 Nova Resource | `sv-nova-master/app/Nova/NaverXlsFileResource.php` |
| sv-nova-master 원본 Action | `sv-nova-master/app/Nova/Actions/ImportNaverXlsFile.php` |
| sv-nova-master ECS 메서드 | `sv-nova-master/app/Services/EcsTaskService.php:364-389` |
| SVGW ECS 서비스 | `SeoulVenturesGroupware/app/Services/RegleEcsService.php` |
| SVGW 컨트롤러 패턴 | `SeoulVenturesGroupware/app/Http/Controllers/Review/UploadSummaryController.php` |
| SVGW 라우트 | `SeoulVenturesGroupware/routes/api.php` |
| SVGW API 엔티티 패턴 | `SeoulVenturesGroupware/frontend/resources/ts/api/entities/review/upload.ts` |
| SVGW 페이지 패턴 | `SeoulVenturesGroupware/frontend/resources/ts/pages/review/upload/index.vue` |

## 엣지 케이스

- DriverConfig가 sv_nova DB에 있으므로 NaverXlsFile.driverConfig() 관계는 같은 DB 연결 사용
- S3 업로드 경로: `naver-xls/{configId}/{YmdHis}-{originalName}` 형식으로 충돌 방지
- 파일 확장자 제한: xls, xlsx만 허용
- ECS 트리거 실패 시 NaverXlsFile 레코드에 error를 import_result에 기록하고 HTTP 422 반환
- 이미 임포트된 파일(imported_at != null)을 재임포트하는 것은 허용 (force re-import)
- 파일 삭제 시 S3 파일도 함께 삭제

---

## Task 1: NaverXlsFile 모델

**Files:**
- Create: `SeoulVenturesGroupware/app/Models/NaverXlsFile.php`
- Create: `SeoulVenturesGroupware/tests/Unit/Models/NaverXlsFileTest.php`

**컨텍스트:**
- `sv_nova` DB 연결 사용 (DailyReport 등과 동일 패턴)
- `import_result`는 JSON cast (임포트 결과: task_id, task_arn, status, error 등)
- `driverConfig()` 관계: sv_nova DB의 `driver_configs` 테이블 → `App\Models\Review\DriverConfig`
  - 단, DriverConfig 모델의 실제 `$connection`이 sv_nova인지 확인 필요
  - `SeoulVenturesGroupware/app/Models/Review/DriverConfig.php` 참고

**Step 1: 테스트 작성**

```php
<?php

namespace Tests\Unit\Models;

use App\Models\NaverXlsFile;
use Tests\TestCase;

class NaverXlsFileTest extends TestCase
{
    public function test_uses_sv_nova_connection(): void
    {
        $model = new NaverXlsFile();
        $this->assertEquals('sv_nova', $model->getConnectionName());
    }

    public function test_import_result_is_cast_to_array(): void
    {
        $model = new NaverXlsFile();
        $model->import_result = json_encode(['status' => 'running', 'task_id' => 'abc-123']);
        $this->assertIsArray($model->import_result);
        $this->assertEquals('running', $model->import_result['status']);
    }

    public function test_has_driver_config_relation(): void
    {
        $model = new NaverXlsFile();
        $relation = $model->driverConfig();
        $this->assertInstanceOf(\Illuminate\Database\Eloquent\Relations\BelongsTo::class, $relation);
    }
}
```

**Step 2: 테스트 실행 (실패 확인)**

```bash
cd SeoulVenturesGroupware && vendor/bin/phpunit tests/Unit/Models/NaverXlsFileTest.php --no-coverage
```
Expected: FAIL - "Class App\Models\NaverXlsFile not found"

**Step 3: 모델 구현**

```php
<?php

namespace App\Models;

use App\Models\Review\DriverConfig;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class NaverXlsFile extends Model
{
    protected $connection = 'sv_nova';

    protected $fillable = [
        'file_name',
        'disk',
        'path',
        'config_id',
        'imported_at',
        'import_result',
    ];

    protected $casts = [
        'imported_at' => 'datetime',
        'import_result' => 'array',
    ];

    public function driverConfig(): BelongsTo
    {
        return $this->belongsTo(DriverConfig::class, 'config_id', 'id');
    }
}
```

> ⚠️ DriverConfig 모델 `$connection` 확인: `SeoulVenturesGroupware/app/Models/Review/DriverConfig.php`를 읽어 connection이 `sv_nova`인지 확인. 다르면 관계 쿼리 시 DB 분리 문제 없도록 `$connection` 맞추거나 raw join 사용.

**Step 4: 테스트 실행 (통과 확인)**

```bash
cd SeoulVenturesGroupware && vendor/bin/phpunit tests/Unit/Models/NaverXlsFileTest.php --no-coverage
```
Expected: 3 tests, 3 assertions, PASS

**Step 5: 커밋**

```bash
cd SeoulVenturesGroupware && git add app/Models/NaverXlsFile.php tests/Unit/Models/NaverXlsFileTest.php
git commit -m "feat(naver-xls): NaverXlsFile 모델 추가"
```

---

## Task 2: RegleEcsService — importNaverFileS3() 추가

**Files:**
- Modify: `SeoulVenturesGroupware/app/Services/RegleEcsService.php`
- Create: `SeoulVenturesGroupware/tests/Unit/Services/RegleEcsServiceNaverXlsTest.php`

**컨텍스트:**
- ECS 커맨드: `import-naver-file-s3-with-driver-config`
- 파라미터: `path` (S3 경로), `config_id` (DriverConfig ID)
- sv-nova-master의 `EcsTaskService::importNaverFileS3()` 로직 그대로 이식
- SVGW `runTask()` 메서드 시그니처: `runTask(string $command, array $params, ?string $requestUser)`

**Step 1: 테스트 작성**

```php
<?php

namespace Tests\Unit\Services;

use App\Services\RegleEcsService;
use Tests\TestCase;
use Mockery;

class RegleEcsServiceNaverXlsTest extends TestCase
{
    public function test_import_naver_file_s3_calls_run_task_with_correct_params(): void
    {
        $service = Mockery::mock(RegleEcsService::class)->makePartial();
        $service->shouldReceive('runTask')
            ->once()
            ->with('import-naver-file-s3-with-driver-config', [
                'path' => 'naver-xls/1/20260220120000-test.xlsx',
                'config_id' => 42,
            ], null)
            ->andReturn(['status' => 'running', 'task_id' => 'task-abc']);

        $result = $service->importNaverFileS3('naver-xls/1/20260220120000-test.xlsx', 42);
        $this->assertEquals('running', $result['status']);
    }

    public function test_import_naver_file_s3_throws_on_empty_path(): void
    {
        $service = new RegleEcsService();
        $this->expectException(\InvalidArgumentException::class);
        $service->importNaverFileS3('', 1);
    }

    public function test_import_naver_file_s3_throws_on_invalid_config_id(): void
    {
        $service = new RegleEcsService();
        $this->expectException(\InvalidArgumentException::class);
        $service->importNaverFileS3('some/path.xlsx', 0);
    }
}
```

**Step 2: 테스트 실행 (실패 확인)**

```bash
cd SeoulVenturesGroupware && vendor/bin/phpunit tests/Unit/Services/RegleEcsServiceNaverXlsTest.php --no-coverage
```
Expected: FAIL - "Method importNaverFileS3 not found"

**Step 3: RegleEcsService 맨 마지막에 메서드 추가**

`RegleEcsService.php`의 마지막 `}` 직전에 추가:

```php
    /**
     * ECS 태스크를 실행하여 S3의 Naver XLS 파일을 임포트한다.
     */
    public function importNaverFileS3(string $s3Path, int $configId): array
    {
        if (empty($s3Path)) {
            throw new \InvalidArgumentException('S3 path is required');
        }
        if ($configId <= 0) {
            throw new \InvalidArgumentException("Invalid driver config ID: {$configId}");
        }

        return $this->runTask('import-naver-file-s3-with-driver-config', [
            'path' => $s3Path,
            'config_id' => $configId,
        ]);
    }
```

**Step 4: 테스트 실행 (통과 확인)**

```bash
cd SeoulVenturesGroupware && vendor/bin/phpunit tests/Unit/Services/RegleEcsServiceNaverXlsTest.php --no-coverage
```
Expected: 3 tests PASS (첫 번째 테스트는 Mockery로 통과, 나머지 2개는 InvalidArgumentException으로 통과)

**Step 5: 커밋**

```bash
cd SeoulVenturesGroupware && git add app/Services/RegleEcsService.php tests/Unit/Services/RegleEcsServiceNaverXlsTest.php
git commit -m "feat(naver-xls): RegleEcsService에 importNaverFileS3() 추가"
```

---

## Task 3: NaverXlsController + 라우트

**Files:**
- Create: `SeoulVenturesGroupware/app/Http/Controllers/Review/NaverXlsController.php`
- Modify: `SeoulVenturesGroupware/routes/api.php`
- Create: `SeoulVenturesGroupware/tests/Feature/NaverXlsControllerTest.php`

**컨텍스트:**
- 인증 필요 (기존 `auth:api` 미들웨어 그룹 내에 추가)
- `routes/api.php`에서 `Review\` 네임스페이스 컨트롤러 그룹 위치: `Route::prefix('review')` 블록 확인
- S3 업로드 경로: `naver-xls/{configId}/{YmdHis}-{original_filename}`
- ECS 실패 시 `import_result`에 error 기록 후 422 반환
- index 응답: paginate(20), with('driverConfig')

**Step 1: 테스트 작성**

```php
<?php

namespace Tests\Feature;

use App\Models\NaverXlsFile;
use App\Services\RegleEcsService;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Mockery;
use Tests\TestCase;

class NaverXlsControllerTest extends TestCase
{
    public function test_index_requires_auth(): void
    {
        $response = $this->getJson('/api/review/naver-xls');
        $response->assertStatus(401);
    }

    public function test_store_requires_auth(): void
    {
        $response = $this->postJson('/api/review/naver-xls', []);
        $response->assertStatus(401);
    }

    public function test_import_requires_auth(): void
    {
        $response = $this->postJson('/api/review/naver-xls/1/import');
        $response->assertStatus(401);
    }

    public function test_destroy_requires_auth(): void
    {
        $response = $this->deleteJson('/api/review/naver-xls/1');
        $response->assertStatus(401);
    }
}
```

**Step 2: 테스트 실행 (실패 확인)**

```bash
cd SeoulVenturesGroupware && vendor/bin/phpunit tests/Feature/NaverXlsControllerTest.php --no-coverage
```
Expected: FAIL - 404 (라우트 없음)

**Step 3: 컨트롤러 구현**

```php
<?php

namespace App\Http\Controllers\Review;

use App\Http\Controllers\Controller;
use App\Models\NaverXlsFile;
use App\Services\RegleEcsService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Storage;

class NaverXlsController extends Controller
{
    public function __construct(private RegleEcsService $regleEcsService)
    {
    }

    /**
     * NaverXls 파일 목록 조회 (paginated, driverConfig 포함)
     */
    public function index(Request $request): JsonResponse
    {
        $query = NaverXlsFile::with('driverConfig')
            ->orderBy('created_at', 'desc');

        if ($request->filled('config_id')) {
            $query->where('config_id', $request->integer('config_id'));
        }

        return response()->json($query->paginate(20));
    }

    /**
     * S3에 XLS 파일 업로드 후 NaverXlsFile 레코드 생성
     */
    public function store(Request $request): JsonResponse
    {
        $request->validate([
            'file'      => ['required', 'file', 'mimes:xls,xlsx', 'max:10240'],
            'config_id' => ['required', 'integer', 'min:1'],
        ]);

        $file = $request->file('file');
        $configId = $request->integer('config_id');
        $timestamp = now()->format('YmdHis');
        $originalName = $file->getClientOriginalName();
        $s3Path = "naver-xls/{$configId}/{$timestamp}-{$originalName}";

        Storage::disk('s3')->put($s3Path, file_get_contents($file->getRealPath()));

        $naverXlsFile = NaverXlsFile::create([
            'file_name'  => $originalName,
            'disk'       => 's3',
            'path'       => $s3Path,
            'config_id'  => $configId,
        ]);

        return response()->json($naverXlsFile->load('driverConfig'), 201);
    }

    /**
     * ECS import-naver-file-s3-with-driver-config 태스크 트리거
     */
    public function import(NaverXlsFile $naverXlsFile): JsonResponse
    {
        try {
            $result = $this->regleEcsService->importNaverFileS3(
                $naverXlsFile->path,
                $naverXlsFile->config_id
            );

            $naverXlsFile->update([
                'imported_at'   => now(),
                'import_result' => $result,
            ]);

            return response()->json([
                'message' => '임포트 태스크가 시작되었습니다.',
                'result'  => $result,
            ]);
        } catch (\Throwable $e) {
            Log::error('NaverXlsController: ECS 태스크 실행 실패', [
                'naver_xls_file_id' => $naverXlsFile->id,
                'exception'         => $e,
            ]);

            $naverXlsFile->update([
                'imported_at'   => now(),
                'import_result' => ['error' => $e->getMessage()],
            ]);

            return response()->json([
                'message' => 'ECS 태스크 실행에 실패했습니다: ' . $e->getMessage(),
            ], 422);
        }
    }

    /**
     * S3 파일 삭제 + NaverXlsFile 레코드 삭제
     */
    public function destroy(NaverXlsFile $naverXlsFile): JsonResponse
    {
        Storage::disk('s3')->delete($naverXlsFile->path);
        $naverXlsFile->delete();

        return response()->json(['message' => '삭제되었습니다.'], 200);
    }
}
```

**Step 4: 라우트 추가**

`routes/api.php`에서 인증된 review 라우트 그룹 내 적절한 위치(upload-summary 등과 같은 블록)에 추가:

```php
Route::get('review/naver-xls', [\App\Http\Controllers\Review\NaverXlsController::class, 'index']);
Route::post('review/naver-xls', [\App\Http\Controllers\Review\NaverXlsController::class, 'store']);
Route::post('review/naver-xls/{naverXlsFile}/import', [\App\Http\Controllers\Review\NaverXlsController::class, 'import']);
Route::delete('review/naver-xls/{naverXlsFile}', [\App\Http\Controllers\Review\NaverXlsController::class, 'destroy']);
```

> `routes/api.php`를 실제로 읽고 인증 미들웨어가 걸린 그룹 내 적절한 위치를 찾아서 추가할 것.

**Step 5: 테스트 실행 (통과 확인)**

```bash
cd SeoulVenturesGroupware && vendor/bin/phpunit tests/Feature/NaverXlsControllerTest.php --no-coverage
```
Expected: 4 tests PASS (모두 401)

**Step 6: 전체 테스트 확인**

```bash
cd SeoulVenturesGroupware && vendor/bin/phpunit --no-coverage
```
Expected: 기존 테스트 모두 PASS

**Step 7: 커밋**

```bash
cd SeoulVenturesGroupware && git add app/Http/Controllers/Review/NaverXlsController.php routes/api.php tests/Feature/NaverXlsControllerTest.php
git commit -m "feat(naver-xls): NaverXlsController 및 라우트 추가"
```

---

## Task 4: 프론트엔드 — API 엔티티 + 페이지

**Files:**
- Create: `SeoulVenturesGroupware/frontend/resources/ts/api/entities/review/naverXls.ts`
- Create: `SeoulVenturesGroupware/frontend/resources/ts/pages/review/naver-xls/index.vue`

**컨텍스트:**
- API 엔티티는 `upload.ts` 패턴 그대로 (`get`, `post`, `del` from `@/api`)
- 페이지는 `review/upload/index.vue` 패턴 (clientStore, driverConfigs, 확인 다이얼로그)
- 파일 업로드는 `FormData` + `post` 함수 (multipart)
- 임포트 완료 후 테이블 새로고침
- 삭제 시 확인 다이얼로그 표시

**Step 1: API 엔티티 작성**

`frontend/resources/ts/api/entities/review/naverXls.ts`:

```typescript
import { type ApiResponse, del, get, post } from '@/api'

export interface NaverXlsFile {
  id: number
  file_name: string | null
  disk: string
  path: string
  config_id: number
  imported_at: string | null
  import_result: Record<string, unknown> | null
  created_at: string
  driver_config?: {
    id: number
    name?: string
  }
}

export interface NaverXlsPaginated {
  data: NaverXlsFile[]
  total: number
  per_page: number
  current_page: number
  last_page: number
}

export const naverXlsApi = {
  list: (configId?: number): Promise<ApiResponse<NaverXlsPaginated>> =>
    get('/review/naver-xls', { params: configId ? { config_id: configId } : {} }),

  upload: (file: File, configId: number): Promise<ApiResponse<NaverXlsFile>> => {
    const formData = new FormData()
    formData.append('file', file)
    formData.append('config_id', String(configId))
    return post('/review/naver-xls', formData)
  },

  import: (id: number): Promise<ApiResponse> =>
    post(`/review/naver-xls/${id}/import`, {}),

  remove: (id: number): Promise<ApiResponse> =>
    del(`/review/naver-xls/${id}`),
}
```

**Step 2: 페이지 작성**

`frontend/resources/ts/pages/review/naver-xls/index.vue`:

```vue
<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { useClientStore } from '@/stores/client'
import { type DriverConfig, driverConfigsApi } from '@/api/entities/review/driverConfigs'
import { type NaverXlsFile, naverXlsApi } from '@/api/entities/review/naverXls'

definePage({
  meta: {
    title: 'Naver XLS 임포트',
    action: 'read',
    subject: 'review',
  },
})

const { snackbar, handleError } = useErrorHandler()
const clientStore = useClientStore()
const selectedClient = computed(() => clientStore.selectedClient)

// 상태
const loading = ref(false)
const uploading = ref(false)
const files = ref<NaverXlsFile[]>([])
const driverConfigs = ref<DriverConfig[]>([])
const selectedConfigId = ref<number | null>(null)
const selectedFile = ref<File | null>(null)
const confirmDialog = ref(false)
const confirmMessage = ref('')
const confirmAction = ref<(() => Promise<void>) | null>(null)

const headers = [
  { title: '파일명', key: 'file_name', sortable: true },
  { title: '드라이버', key: 'driver_config', sortable: false },
  { title: '업로드 일시', key: 'created_at', sortable: true },
  { title: '임포트 일시', key: 'imported_at', sortable: true },
  { title: '결과', key: 'import_result', sortable: false },
  { title: '작업', key: 'actions', sortable: false, width: '200px' },
]

const loadDriverConfigs = async () => {
  if (!selectedClient.value) return
  const { success, data } = await driverConfigsApi.listDriverConfigs(selectedClient.value.id, { per_page: 100 })
  if (success && data)
    driverConfigs.value = data.data || []
}

const loadFiles = async () => {
  loading.value = true
  try {
    const params = selectedConfigId.value ? selectedConfigId.value : undefined
    const { success, data } = await naverXlsApi.list(params)
    if (success && data)
      files.value = data.data
  }
  catch (error) {
    handleError(error, { silent: true })
  }
  finally {
    loading.value = false
  }
}

const uploadFile = async () => {
  if (!selectedFile.value || !selectedConfigId.value) return
  uploading.value = true
  try {
    const { success } = await naverXlsApi.upload(selectedFile.value, selectedConfigId.value)
    if (success) {
      snackbar('파일이 업로드되었습니다.')
      selectedFile.value = null
      await loadFiles()
    }
  }
  catch (error) {
    handleError(error)
  }
  finally {
    uploading.value = false
  }
}

const showConfirm = (message: string, action: () => Promise<void>) => {
  confirmMessage.value = message
  confirmAction.value = action
  confirmDialog.value = true
}

const executeConfirm = async () => {
  if (confirmAction.value)
    await confirmAction.value()
  confirmDialog.value = false
}

const triggerImport = (file: NaverXlsFile) => {
  showConfirm(`"${file.file_name}" 파일을 임포트하시겠습니까?`, async () => {
    try {
      const { success } = await naverXlsApi.import(file.id)
      if (success) {
        snackbar('임포트 태스크가 시작되었습니다.')
        await loadFiles()
      }
    }
    catch (error) {
      handleError(error)
    }
  })
}

const deleteFile = (file: NaverXlsFile) => {
  showConfirm(`"${file.file_name}" 파일을 삭제하시겠습니까?`, async () => {
    try {
      const { success } = await naverXlsApi.remove(file.id)
      if (success) {
        snackbar('삭제되었습니다.')
        await loadFiles()
      }
    }
    catch (error) {
      handleError(error)
    }
  })
}

const importStatusText = (file: NaverXlsFile): string => {
  if (!file.import_result) return '-'
  if (file.import_result.error) return `오류: ${file.import_result.error}`
  if (file.import_result.status) return String(file.import_result.status)
  return JSON.stringify(file.import_result)
}

watch(selectedClient, () => {
  loadDriverConfigs()
  loadFiles()
})

onMounted(() => {
  loadDriverConfigs()
  loadFiles()
})
</script>

<template>
  <VRow>
    <VCol cols="12">
      <VCard>
        <VCardTitle class="pa-4">Naver XLS 임포트</VCardTitle>
        <VCardText>
          <!-- 업로드 영역 -->
          <VRow class="mb-4">
            <VCol cols="12" md="4">
              <VSelect
                v-model="selectedConfigId"
                :items="driverConfigs"
                item-title="name"
                item-value="id"
                label="드라이버 선택"
                clearable
              />
            </VCol>
            <VCol cols="12" md="5">
              <VFileInput
                v-model="selectedFile"
                label="XLS/XLSX 파일 선택"
                accept=".xls,.xlsx"
                :show-size="true"
                prepend-icon="mdi-file-excel"
              />
            </VCol>
            <VCol cols="12" md="3" class="d-flex align-center">
              <VBtn
                color="primary"
                :loading="uploading"
                :disabled="!selectedFile || !selectedConfigId"
                @click="uploadFile"
              >
                업로드
              </VBtn>
            </VCol>
          </VRow>

          <!-- 파일 목록 -->
          <VDataTable
            :headers="headers"
            :items="files"
            :loading="loading"
            item-value="id"
          >
            <template #item.driver_config="{ item }">
              {{ item.driver_config?.name ?? `Config #${item.config_id}` }}
            </template>
            <template #item.created_at="{ item }">
              {{ item.created_at ? new Date(item.created_at).toLocaleString('ko-KR') : '-' }}
            </template>
            <template #item.imported_at="{ item }">
              {{ item.imported_at ? new Date(item.imported_at).toLocaleString('ko-KR') : '-' }}
            </template>
            <template #item.import_result="{ item }">
              {{ importStatusText(item) }}
            </template>
            <template #item.actions="{ item }">
              <VBtn
                size="small"
                color="success"
                class="mr-2"
                @click="triggerImport(item)"
              >
                임포트
              </VBtn>
              <VBtn
                size="small"
                color="error"
                @click="deleteFile(item)"
              >
                삭제
              </VBtn>
            </template>
          </VDataTable>
        </VCardText>
      </VCard>
    </VCol>
  </VRow>

  <!-- 확인 다이얼로그 -->
  <VDialog v-model="confirmDialog" max-width="400">
    <VCard>
      <VCardTitle>확인</VCardTitle>
      <VCardText>{{ confirmMessage }}</VCardText>
      <VCardActions>
        <VSpacer />
        <VBtn @click="confirmDialog = false">취소</VBtn>
        <VBtn color="primary" @click="executeConfirm">확인</VBtn>
      </VCardActions>
    </VCard>
  </VDialog>
</template>
```

**Step 3: 빌드 확인**

```bash
cd SeoulVenturesGroupware/frontend && bun run typecheck 2>&1 | tail -20
```
Expected: 타입 오류 없음 (또는 기존 오류만 있음)

**Step 4: 커밋**

```bash
cd SeoulVenturesGroupware && git add frontend/resources/ts/api/entities/review/naverXls.ts frontend/resources/ts/pages/review/naver-xls/index.vue
git commit -m "feat(naver-xls): 프론트엔드 API 엔티티 및 페이지 추가"
```

---

## Task 5: sv-nova-master NaverXlsFileResource 스케줄 제거

**Files:**
- Modify: `sv-nova-master/app/Nova/NovaServiceProvider.php` 또는 `app/Providers/NovaServiceProvider.php` — NaverXlsFileResource 등록 제거
- Modify: `sv-nova-master/app/Providers/NovaServiceProvider.php`

**컨텍스트:**
- Nova Resource 등록을 제거하면 Nova UI에서 메뉴가 사라짐
- 모델·마이그레이션·데이터는 그대로 유지 (sv_nova DB 공유)
- `NovaServiceProvider.php`의 `resources()` 메서드에서 `NaverXlsFileResource::class` 제거

**Step 1: Nova Service Provider에서 NaverXlsFileResource 제거**

`sv-nova-master/app/Providers/NovaServiceProvider.php` 파일을 읽어 `NaverXlsFileResource::class`가 있는 줄을 찾아 제거.

**Step 2: 테스트**

```bash
cd sv-nova-master && php artisan nova:check 2>/dev/null || php artisan route:list | grep naver
```
Expected: naver-xls 관련 Nova 라우트 없음

**Step 3: 커밋 (sv-nova-master)**

```bash
cd sv-nova-master && git add app/Providers/NovaServiceProvider.php
git commit -m "feat(naver-xls): Nova에서 NaverXlsFileResource 제거 - SVGW로 이관"
```

**Step 4: 서브모듈 업데이트 커밋 (regle-mono)**

```bash
cd /opt/SeoulVentures/regle && git add sv-nova-master
git commit -m "chore: sv-nova-master 서브모듈 업데이트 - NaverXlsFileResource Nova 제거"
```

---

## Task 6: PR 생성

**Step 1: 전체 테스트 실행**

```bash
cd SeoulVenturesGroupware && vendor/bin/phpunit --no-coverage 2>&1 | tail -10
```
Expected: 전체 PASS

**Step 2: SVGW 브랜치 푸시**

```bash
cd SeoulVenturesGroupware && git push -u origin feat/naver-xls-migration
```

**Step 3: PR 생성**

```bash
gh pr create \
  --title "feat(naver-xls): Phase 3 - NaverXls 임포트 이관 (sv-nova-master → SVGW)" \
  --body "$(cat <<'EOF'
## Summary
- `NaverXlsFile` 모델 추가 (sv_nova DB 연결)
- `RegleEcsService::importNaverFileS3()` 추가 (ECS 커맨드: import-naver-file-s3-with-driver-config)
- `NaverXlsController` 추가: 목록 조회 / S3 업로드 / ECS 임포트 트리거 / 삭제
- `/review/naver-xls` 프론트엔드 페이지 추가
- sv-nova-master Nova에서 NaverXlsFileResource 제거

## Test Plan
- [ ] `/api/review/naver-xls` 인증 없이 401 반환 확인
- [ ] XLS 파일 업로드 후 S3 저장 및 DB 레코드 생성 확인
- [ ] 임포트 버튼 클릭 시 ECS 태스크 트리거 및 import_result 기록 확인
- [ ] 파일 삭제 시 S3 + DB 동시 삭제 확인
- [ ] `/review/naver-xls` 페이지 UI 정상 렌더링 확인

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## 변경 파일 목록

| 파일 | 작업 | 위치 |
|------|------|------|
| `app/Models/NaverXlsFile.php` | 신규 | SVGW |
| `app/Services/RegleEcsService.php` | `importNaverFileS3()` 추가 | SVGW |
| `app/Http/Controllers/Review/NaverXlsController.php` | 신규 | SVGW |
| `routes/api.php` | 라우트 4개 추가 | SVGW |
| `frontend/resources/ts/api/entities/review/naverXls.ts` | 신규 | SVGW |
| `frontend/resources/ts/pages/review/naver-xls/index.vue` | 신규 | SVGW |
| `tests/Unit/Models/NaverXlsFileTest.php` | 신규 | SVGW |
| `tests/Unit/Services/RegleEcsServiceNaverXlsTest.php` | 신규 | SVGW |
| `tests/Feature/NaverXlsControllerTest.php` | 신규 | SVGW |
| `app/Providers/NovaServiceProvider.php` | NaverXlsFileResource 제거 | sv-nova-master |

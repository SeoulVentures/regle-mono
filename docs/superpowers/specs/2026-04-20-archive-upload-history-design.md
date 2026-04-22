# 매핑 이관 이력 아카이브 (Danger Zone)

작성일: 2026-04-20
대상: SVGW `/review/data` 매핑 관리 페이지 + MongoDB `review_upload_target_list`

## 배경

특정 매핑의 이관 이력을 운영자가 수동으로 초기화해야 하는 요구가 반복적으로 들어온다 (예: Mall ID 160 `curlyshyll`, 매핑 ID 303315 — 브랜드스토어 채널 상품 `4995740052` / 자사몰 `189`). 현재는 운영자가 DB 에 직접 접근해 MongoDB `review_upload_target_list` 레코드를 삭제해야 하며, 실수·사고 위험이 크다.

시스템이 자동으로 삭제하는 것은 부적절하다 — 이관 완료 상태를 되돌리면 자사몰에 동일 리뷰가 중복 등록될 수 있어, 반드시 명시적인 운영자 확인이 필요하다.

본 스펙은 이 작업을 **그룹웨어 어드민에서 Danger Zone 으로 노출** 하여 안전하게 수행할 수 있도록 한다.

## 범위

- 대상 페이지: SVGW `/review/data` (매핑 관리)
- 동작: MongoDB `{target_database_hive}.review_upload_target_list` 의 해당 매핑 레코드를 `review_upload_target_list_archive` 로 **이동** (insert → delete)
- 건드리지 않는 것:
  - `standard_review_target` (형상 관리 DB)
  - `TargetItemMap` 의 `ready_cnt/failed_cnt/finished_cnt` 카운터
  - 자사몰에 이미 업로드된 실제 리뷰 (외부 시스템, 접근 불가)
- 한 번에 최대 **10 매핑** 선택 가능
- 매핑당 chunk 500 건 단위 순차 처리 (재시작 안전)

## 설계 원칙

- **매핑 ID 비의존**: 엔드포인트는 `(client_id, config_id, target_item_code, client_item_code)` 튜플 기반. 매핑이 이미 삭제된 상태에서도 운영자가 동일 도구로 이관 이력을 정리할 수 있다.
- **동기 처리**: 위험 동작이므로 백그라운드 큐 금지. 프론트가 사용자 대기 화면에서 순차 호출·진행률 표시.
- **Chunked·멱등**: 매 호출은 독립적으로 500 건을 archive+delete. 세션 단절·사용자 취소·네트워크 실패 후 재실행해도 남은 레코드만 이어서 처리. 멱등성은 **archive 측 유니크 인덱스 `{original_id: 1}`** + `ordered:false insertMany` 의 duplicate-key 허용으로 보장한다 (단순히 "유니크 인덱스 없음" 으로 넘기지 않는다).
- **동시 실행 방지**: 같은 튜플에 대해 Laravel `Cache::lock()` (Redis 기반) 30초 TTL 분산 락을 획득한 후에만 처리. 획득 실패 시 423 Locked.
- **Archive 는 이동이지 이력 테이블 아님**: 복원이 필요하면 운영자가 `review_upload_target_list_archive` 에서 `review_upload_target_list` 로 수동 이전. 자동 복원 UI 는 본 스펙 밖.

## 전제 조건

- **MongoDB 토폴로지**: 단일 노드 / replica set 모두 대응. 트랜잭션 (multi-document) 을 의존하지 않는다 (C-1 해결로 불필요).
- **`target_database_hive` 는 client 격리 DB**: 한 hive 내 `review_upload_target_list` 의 `{driver_code, target_item_code, client_item_code}` 조합은 해당 client 의 레코드로 고유하게 특정된다. 기존 `BaseUploadDriver.clean_failed_and_ready_by_review_target_item_map_id` (`review-moai-refactoring/app/drivers/BaseUploadDriver.py:745`) 가 동일 전제로 검증되어 운영 중. 본 스펙도 동일 전제 — `client_id` 필드 필터는 사용하지 않는다.
- **Redis 캐시**: Laravel 의 기본 cache driver 가 Redis (또는 최소한 원자적 락을 지원하는 드라이버) 이어야 한다.
- **인덱스**: `review_upload_target_list_archive.{original_id: 1}` 유니크 인덱스를 생성한다. `review_upload_target_list` 의 필터 인덱스 `{driver_code, target_item_code, client_item_code}` 존재 여부는 운영 시점에 확인 (인덱스 부재 시 collection scan 이지만 hive 당 레코드 수가 제한적이라 일단 허용. 느릴 경우 추가).

## API

### 엔드포인트

```
POST /api/review/clients/{client}/upload-history/archive
```

- 매핑 독립 (클라이언트 단위 라우트)
- 기존 `Route::middleware('auth:sanctum')->group(...)` 내부의 `Route::prefix('review')->group(...)` 하위에 추가 (`routes/api.php:86` 구조)
- 추가 미들웨어: `throttle:60,1` (사용자 스코프 — Laravel 기본 key 는 로그인 시 user-id, 미로그인 시 IP). 분당 60 호출 제한. 평균 10 매핑 × 20 chunk ≈ 200 회 요청을 3.3 분에 수용. 멀티 운영자는 각자 60/분 여유 (상호 간섭 없음).

### Request

```json
{
  "config_id": 42,
  "target_item_code": "4995740052",
  "client_item_code": "189",
  "confirm_text": "위험성을 알고 동의합니다"
}
```

- **`mapping_batch_id` 는 request 에 포함하지 않는다 (서버 주도)**.
  - 서버가 첫 chunk 진입 시 UUID v4 를 생성하여 Redis `Cache::put("upload-history-batch:{client_id}:{config_id}:{target_item_code}:{client_item_code}", $uuid, 600)` 에 10분 TTL 로 저장
  - 후속 chunk 호출은 cache 에서 재조회 (없으면 신규 UUID — 새 "세션" 으로 간주)
  - 클라이언트 통제 값이 아니므로 감사 추적 신뢰성 보장 (임의 UUID 주입 불가)
  - Response 에서 echo 해 프론트 정합성 확인 가능

**`config_id` 를 URL 이 아닌 body 에 두는 이유** (S-7):
- URL 에 올리면 삭제된 config 접근이 route model binding 에 의해 404 → 운영자가 "원인 불명 실패" 로 혼란
- 매핑 ID 비의존 설계 원칙과도 부합 (URL 은 `/clients/{client}/...` 까지만)

### 검증

- `config_id`: `integer|min:1`, `DriverConfig::find($config_id)->client_id === client->id` (cross-client 공격 방어)
- `target_item_code`: `string|min:1`
- `client_item_code`: `string|min:1`
- `confirm_text`: trim + NFC 정규화 후 `위험성을 알고 동의합니다` 정확 일치 — `ClientNameComparator::equals()` **재사용** (신규 클래스 X). 호출부는 `UploadHistoryController::confirmTokenMatches(string $input): bool` 래퍼 private 메서드로 의도 명시 (S-1)
- `driver_code`: 서버가 `DriverConfig` 에서 도출 (클라이언트 입력 불허)
- `target_database_hive`: 서버가 `Client` 에서 도출 (클라이언트 입력 불허)

**컨트롤러가 chunk 당 수행하는 MySQL 쿼리** (I-4 경계 명시):
- (a) `Client` 조회 — route model binding (`{client}`)
- (b) `DriverConfig::find($configId)` — cross-client 검증용 1회
- (c) `TargetItemMap::where(...)->value('id')` — `archived_mapping_id` 1회

(a)~(c) 모두 chunk 당 1회이며 서비스 내부로 들어가지 않는다. 서비스는 MongoDB 연산만 수행.

### Response

```json
{
  "success": true,
  "archived_count": 500,
  "duplicate_count": 0,
  "remaining_count": 2067,
  "has_more": true,
  "mapping_batch_id": "550e8400-e29b-41d4-a716-446655440000"
}
```

- `archived_count`: **이번 호출** 에서 archive 에 실제 insert 된 건수 (duplicate key 로 차단된 건 제외)
- `duplicate_count`: archive 유니크 인덱스로 중복 차단된 건수 (C-1 방어 발동 여부 관측, S-2). 정상 운영에서는 0. 재시도 경로에서만 증가.
- `remaining_count`: 이번 호출 후 조건에 매칭되는 잔여 건수. **모든 호출마다 `countDocuments` 수행** (I-2 단정 — 구현자 재량 없음). 프론트 진행률 계산 기반.
- `has_more`: `remaining_count > 0`
- `mapping_batch_id`: request 에서 전달받은 값을 그대로 echo — 프론트 정합성 확인용

### 예외

- 토큰 불일치: 422 `{"message": "확인 문구가 일치하지 않습니다."}`
- `config_id` 가 client 소속이 아님: 422 `{"message": "드라이버 설정이 해당 클라이언트에 속하지 않습니다."}`
- `target_database_hive` / `driver_code` 결손: 422 `{"message": "클라이언트 또는 드라이버 설정이 불완전합니다."}`
- 분산 락 획득 실패 (같은 튜플 동시 실행): 423 `{"message": "같은 매핑에 대한 아카이브 작업이 이미 진행 중입니다. 잠시 후 재시도하세요."}`
- Rate limit 초과: 429 (Laravel throttle 기본 응답)
- MongoDB 연결 실패: 500 (Handler 가 Sentry 전파)
- insert 성공 후 delete 실패: 500 + `Log::error`. 재호출 시 archive 유니크 인덱스가 이미 완료된 문서를 duplicate-key 로 차단 → 원본 `deleteMany` 가 재시도되어 안전하게 수렴.

## MongoDB 처리

### 필터

```php
$filter = [
    'driver_code' => $driverCode,
    'target_item_code' => $targetItemCode,
    'client_item_code' => $clientItemCode,
];
```

state 무관 (ready / failed / finished 모두).

### 아카이브 흐름

분산 락 → find → insertMany (duplicate key 허용) → deleteMany 순. 각 단계의 실패가 재호출 시 안전하게 수렴하도록 설계.

```php
// === Controller: UploadHistoryController::archive() ===
public function archive(Client $client, Request $request): JsonResponse
{
    $validated = $request->validate([...]);
    // ... (a) Client 이미 바인딩, (b) DriverConfig 조회, (c) TargetItemMap 조회
    $driverConfig = DriverConfig::findOrFail($validated['config_id']);
    abort_if($driverConfig->client_id !== $client->id, 422, '드라이버 설정이 ...');
    $archivedMappingId = TargetItemMap::query()
        ->where('client_id', $client->id)
        ->where('config_id', $validated['config_id'])
        ->where('target_item_code', $validated['target_item_code'])
        ->where('client_item_code', $validated['client_item_code'])
        ->value('id');

    try {
        $result = $this->service->archiveChunk(
            $client,
            $validated['config_id'],
            $driverConfig->driver_code,
            $validated['target_item_code'],
            $validated['client_item_code'],
            Auth::user()->email ?? 'unknown',
            $archivedMappingId,
        );
    } catch (UploadHistoryLockedException $e) {
        return response()->json(['message' => '같은 매핑에 대한 아카이브 작업이 이미 진행 중입니다. 잠시 후 재시도하세요.'], 423);
    }

    return response()->json($result);
}

// === Service: UploadHistoryArchiveService::archiveChunk() ===
const CHUNK_SIZE = 500;

// 1. 분산 락 획득 (C-2 방어)
//    - TTL 30초는 chunk 처리 (수백 ms) 대비 충분
//    - 서버 crash 등으로 finally 가 실행되지 못해도 30초 내 auto-release
//    - 락이 auto-release 된 후 동시 실행이 발생해도 archive 측 {original_id:1}
//      유니크 인덱스가 원본 중복을 구조적으로 차단한다 (중첩 방어).
//    - 프론트 HTTP 타임아웃이 발생해도 서버는 finally 까지 실행하여 락 해제.
$lockKey = sprintf(
    'archive-upload-history:%d:%d:%s:%s',
    $client->id, $configId, $targetItemCode, $clientItemCode
);
$lock = Cache::lock($lockKey, 30);
if (! $lock->get()) {
    Log::warning('[upload-history] lock contention', [
        'client_id' => $client->id, 'config_id' => $configId,
        'target_item_code' => $targetItemCode, 'client_item_code' => $clientItemCode,
        'archived_by' => $archivedBy,
    ]);
    throw new UploadHistoryLockedException; // 컨트롤러가 423 으로 변환
}

try {
    // 2. mapping_batch_id — Redis 에서 재사용 또는 신규 발급 (I-5, 서버 주도)
    $batchCacheKey = sprintf('upload-history-batch:%d:%d:%s:%s',
        $client->id, $configId, $targetItemCode, $clientItemCode);
    $mappingBatchId = Cache::remember(
        $batchCacheKey,
        600, // 10분 TTL — 한 매핑 처리가 끝날 시간 여유
        fn() => (string) Str::uuid()
    );

    // 3. MongoDB 연결 — CLAUDE.md: getClient() / table() 사용
    $conn = DB::connection('mongodb');
    $db = $conn->getClient()->selectDatabase($client->target_database_hive);
    $coll = $db->selectCollection('review_upload_target_list');
    $archiveColl = $db->selectCollection('review_upload_target_list_archive');

    // 4. 런타임 인덱스 보장 (I-4/S-4) — 신규 hive 에서도 유니크 인덱스 보장
    //    같은 이름/스펙 재생성은 MongoDB 가 no-op 처리 (비용 미미)
    $archiveColl->createIndex(
        ['original_id' => 1],
        ['unique' => true, 'name' => 'uniq_original_id']
    );

    // 5. 청크 조회
    $docs = iterator_to_array($coll->find($filter, ['limit' => self::CHUNK_SIZE]), false);
    if (empty($docs)) {
        Cache::forget($batchCacheKey); // 배치 종료 — 다음 실행은 신규 UUID
        return [
            'archived_count' => 0, 'duplicate_count' => 0,
            'remaining_count' => 0, 'has_more' => false,
            'mapping_batch_id' => $mappingBatchId,
        ];
    }

    // 6. 메타 추가
    $archivedAt = new UTCDateTime();
    $originalIds = [];
    foreach ($docs as &$doc) {
        $originalIds[] = $doc['_id'];
        $doc['original_id']         = $doc['_id'];
        $doc['_id']                 = new ObjectId;
        $doc['archived_at']         = $archivedAt;
        $doc['archived_by']         = $archivedBy;
        $doc['archived_mapping_id'] = $archivedMappingId; // param
        $doc['archive_batch_id']    = $mappingBatchId;    // 매핑 단위 UUID (S-4)
    }
    unset($doc);

    // 7. archive insertMany — ordered:false + code 11000 허용 (C-1 해결)
    $duplicateCount = 0;
    $insertedCount = count($docs);
    try {
        $archiveColl->insertMany($docs, ['ordered' => false]);
    } catch (BulkWriteException $e) {
        // getWriteResult() 가 null 반환 가능성 방어 (S-9)
        $writeResult = $e->getWriteResult();
        $writeErrors = $writeResult !== null ? $writeResult->getWriteErrors() : [];

        foreach ($writeErrors as $err) {
            if ($err->getCode() !== 11000) {
                throw $e; // non-duplicate 에러는 전파
            }
            $duplicateCount++;
        }
        $insertedCount = $writeResult !== null
            ? $writeResult->getInsertedCount()
            : count($docs) - $duplicateCount;
    }

    // 8. 원본 deleteMany — archive 완료(신규 or duplicate 둘 다) 보장된 _id 들 제거
    $coll->deleteMany(['_id' => ['$in' => $originalIds]]);

    // 9. remaining_count — 매 호출 집계 (I-2 단정)
    $remainingCount = $coll->countDocuments($filter);

    // 10. 완료 시 batch cache 정리 (다음 실행은 신규 UUID)
    if ($remainingCount === 0) {
        Cache::forget($batchCacheKey);
    }

    return [
        'archived_count' => $insertedCount,
        'duplicate_count' => $duplicateCount,
        'remaining_count' => $remainingCount,
        'has_more' => $remainingCount > 0,
        'mapping_batch_id' => $mappingBatchId,
    ];
} finally {
    optional($lock)->release();
}
```

**불변식**: `archived_count + duplicate_count === 이번 chunk 에서 MongoDB 가 반환한 문서 수 (최대 CHUNK_SIZE)`. 테스트 assertion 으로 활용 (S-3).

**`insertMany` vs `upsert` 선택 이유**: upsert 는 기존 archive 문서를 업데이트해 **최초 archive 시점 메타 (archived_at, archived_by) 손실** 위험. `insertMany(ordered:false)` + code 11000 허용은 "최초 기록만 유지, 중복 차단" 을 자연히 달성 (S-2 정당화).

**컨트롤러 진입 시 1회 조회 (I-4 해결)**:

```php
$archivedMappingId = TargetItemMap::query()
    ->where('client_id', $client->id)
    ->where('config_id', $configId)
    ->where('target_item_code', $targetItemCode)
    ->where('client_item_code', $clientItemCode)
    ->value('id'); // nullable — 삭제된 매핑이면 null
// Service 호출에 $archivedMappingId 를 파라미터로 전달. 매 chunk MySQL 재조회 금지.
```

**최초 배포 시 인덱스 생성 — Laravel migration 필수** (S-8):

```php
// database/migrations/2026_04_20_000001_create_upload_target_list_archive_index.php
use Illuminate\Database\Migrations\Migration;
use MongoDB\Laravel\Facades\DB as MongoDB;

return new class extends Migration
{
    public function up(): void
    {
        // MongoDB 는 전 hive 공통이 아니라 hive 당 컬렉션이 존재한다.
        // 배포 스크립트가 운영 hive 목록을 순회하여 각각에 인덱스 생성.
        foreach (\App\Models\Review\Client::pluck('target_database_hive')->filter()->unique() as $hive) {
            $collection = DB::connection('mongodb')->getClient()
                ->selectDatabase($hive)
                ->selectCollection('review_upload_target_list_archive');
            $collection->createIndex(
                ['original_id' => 1],
                ['unique' => true, 'name' => 'uniq_original_id']
            );
        }
    }

    public function down(): void { /* 운영 데이터 보호 — drop 하지 않음 */ }
};
```

- 수동 mongosh 실행은 hotfix 용. 기본 경로는 migration.
- 컬렉션이 없는 hive 에서도 `createIndex` 는 컬렉션 자동 생성과 함께 동작 (MongoDB 기본 동작).

### 아카이브 도큐먼트 스키마

원본 필드 전부 + 다음 메타:

| 필드 | 타입 | 설명 |
|------|------|------|
| `_id` | ObjectId | 신규 발급 (원본 `_id` 와 별개) |
| `original_id` | ObjectId | 원본 `review_upload_target_list._id` |
| `archived_at` | UTCDateTime | 이동 시점 |
| `archived_by` | string | 실행자 email |
| `archived_mapping_id` | int \| null | 실행 시점의 `TargetItemMap.id` (삭제된 매핑이면 null) |
| `archive_batch_id` | string (UUID v4) | 매핑 단위 배치 ID (API 에서는 `mapping_batch_id` 로 echo — 두 이름은 같은 값, 관점 구분: API 는 "매핑 처리 배치", 저장소는 "아카이브 배치") |

**인덱스**:
- `{original_id: 1}` **유니크 인덱스** 필수 (C-1 멱등성 방어). 한 번 archive 된 원본은 동일 `original_id` 로 다시 들어오지 않으며, 재호출 시 duplicate key (code 11000) 로 차단됨.
- 같은 매핑을 여러 번 실행해도 "한 원본 → archive 1건" 보장. 여러 번 실행한 추적은 `archive_batch_id` 와 `archived_at` 로 수행.
- 보조 인덱스 (예: `{archived_at: 1}`, `{archive_batch_id: 1}`) 는 조회 빈도에 따라 운영 중 추가. 본 스펙에선 유니크 인덱스만 의무화.

## UI

### 위치

`frontend/resources/ts/pages/review/data/index.vue` — 매핑 관리 페이지의 테이블 toolbar.

### 버튼

- 라벨: **이관 이력 삭제**
- 색상: 빨강 (`color="error"` outlined 또는 tonal, 다른 파괴적 액션과 톤 일치)
- 활성 조건:
  - `selectedMappings.length` 가 1 이상 10 이하일 때만 enabled
  - 0 또는 >10 면 disabled + 툴팁 (`선택된 매핑이 없습니다` / `최대 10개까지 선택 가능합니다`)

### 확인 다이얼로그 (1단계)

제목: **이관 이력 삭제 (Danger Zone)**

본문:
```
[경고] 중복 이관 위험

- review_upload_target_list 의 해당 매핑 레코드를
  review_upload_target_list_archive 로 이동합니다.
- 자사몰에 이미 업로드된 리뷰는 외부 시스템에 그대로 남아있으며,
  다음 업로드 사이클에서 동일 리뷰가 중복 등록될 수 있습니다.
- 실행 중 취소해도 이미 이동된 기록은 자동으로 되돌릴 수 없습니다.
  복원이 필요하면 운영자 (데이터팀) 에게 문의해 주세요.
```

대상 매핑 테이블 (selectedMappings 렌더):

| 매핑 ID | 채널명 | 채널 상품코드 | 자사몰 상품코드 | 상품명 (채널 / 자사몰) |
|--------|-------|------------|--------------|-------------------|
| 303315 | 브랜드스토어 | 4995740052 | 189 | "상품 A" / "자사몰 B" |

컬럼 매핑 (테이블 행 객체에서):
- 매핑 ID: `mapping.id`
- 채널명: `mapping.driver_config?.name` 또는 `mapping.driver_name`
- 채널 상품코드: `mapping.target_item_code`
- 자사몰 상품코드: `mapping.client_item_code`
- 상품명: `mapping.target_item_name` / `mapping.client_item_name` (긴 이름은 truncate + 툴팁)

확인 입력:
```
확인 문구를 정확히 입력하세요: 위험성을 알고 동의합니다
[_______________________________________________]
```

버튼:
- `[취소]` — 다이얼로그 닫기
- `[삭제 시작]` — 확인 문구 정확 일치 시에만 enabled

### 진행 다이얼로그 (2단계)

제목: **이관 이력 삭제 진행 중**

```
매핑 {N}/{TOTAL}: #{mapping.id} ({mapping.driver_name})
[████████░░░░░░░░]  {processed} / {total_for_this_mapping}  ({percent}%)

전체 진행  [████░░░░░░░░░░]  {completed_mappings} / {total_mappings} 매핑 완료

[취소]
```

- `total_for_this_mapping`: 현재 매핑의 첫 호출 응답에서 `archived_count + remaining_count` 로 고정
- `processed`: 누적 `archived_count` (현재 매핑 범위 내)
- `percent`: `processed / total_for_this_mapping`
- 전체 진행: `완료 매핑 수 / 전체 선택 수`

취소 동작:
- `cancelled.value = true` 플래그
- 현재 진행 중인 API 호출이 응답하면 루프 종료 (서버 도중 취소 불가, 이미 이동된 기록은 남음)
- 완료 후 스낵바: `취소됨. N개 매핑 중 M개 처리 완료.`

### 프론트 실행 루프

**불변성**: 각 매핑은 `results` 에 정확히 1건 push 된다 (완료 / 에러 / 취소 / 미처리 중 하나). `finally` 로 보장.

```ts
type ArchiveResult =
  | { mapping: TargetItemMap; status: 'completed'; archived: number }
  | { mapping: TargetItemMap; status: 'error'; archived: number; message: string }
  | { mapping: TargetItemMap; status: 'cancelled'; archived: number }
  | { mapping: TargetItemMap; status: 'skipped' }  // 루프 시작 전 이미 취소됨

const cancelled = ref(false)

async function executeArchive(selected: TargetItemMap[]) {
  const results: ArchiveResult[] = []

  for (const [idx, m] of selected.entries()) {
    // 루프 시작 전 취소된 경우: skipped 로 기록
    if (cancelled.value) {
      results.push({ mapping: m, status: 'skipped' })
      continue
    }

    updateProgress({ currentMappingIndex: idx, mapping: m })

    let processed = 0
    let total: number | null = null
    let finalStatus: ArchiveResult['status'] = 'cancelled'
    let errorMessage: string | undefined
    // mapping_batch_id 는 서버가 발급 (I-5). 프론트는 응답의 mapping_batch_id 로 추적만.

    try {
      while (true) {
        let res
        try {
          res = await archiveUploadHistory(m.client_id, {
            config_id: m.config_id,
            target_item_code: m.target_item_code,
            client_item_code: m.client_item_code,
            confirm_text: '위험성을 알고 동의합니다',
          })
        } catch (e) {
          // C-2 해결: 네트워크/HTTP 에러는 error 로 기록 (silent cancelled 금지)
          finalStatus = 'error'
          errorMessage = (e as Error).message ?? 'network error'
          break
        }

        if (!res.success) {
          finalStatus = 'error'
          errorMessage = res.message
          break
        }

        if (total === null) total = res.archived_count + res.remaining_count
        processed += res.archived_count
        // total 을 초과하지 않도록 processed 를 clamp (E3: 중간 insert 시 안전)
        updateProgress({ processed: Math.min(processed, total), total })

        if (!res.has_more) {
          finalStatus = 'completed'
          break
        }

        // 응답 반영 후 취소 확인 — 이 시점에 취소되면 현재 매핑은 부분 완료로 종료
        if (cancelled.value) {
          finalStatus = 'cancelled'
          break
        }

        await sleep(300)

        // sleep 이후에도 재확인 (sleep 중 취소된 경우)
        if (cancelled.value) {
          finalStatus = 'cancelled'
          break
        }
      }
    } finally {
      // 어떤 경로로 루프를 빠져나오든 results 에 정확히 1건 push
      if (finalStatus === 'error') {
        results.push({ mapping: m, status: 'error', archived: processed, message: errorMessage! })
      } else {
        results.push({ mapping: m, status: finalStatus, archived: processed })
      }
    }

    // 외부 루프는 break 하지 않는다 — 다음 iteration 에서 앞부분의 `cancelled.value` 가드가 남은 매핑을 skipped 기록
  }

  showSummary(results, cancelled.value)
}
```

취소 경로별 기록:
- 루프 시작 전 취소 → `skipped`, archived=0
- chunk 응답 후 취소 → `cancelled`, archived=현재까지 처리량
- sleep 중 취소 → `cancelled`, archived=현재까지 처리량
- API 에러 → `error`, archived=현재까지 처리량 + 에러 메시지
- 정상 완료 → `completed`, archived=총합

요약 화면은 `N개 매핑 중 M개 완료, K개 취소 (부분 처리 포함), E개 에러` 처럼 상태별 집계 노출.

## 감사 로그

매 API 호출마다:

```php
Log::info('[upload-history] archive chunk', [
    'client_id' => $client->id,
    'config_id' => $configId,
    'driver_code' => $driverCode,
    'target_item_code' => $targetItemCode,
    'client_item_code' => $clientItemCode,
    'target_database_hive' => $client->target_database_hive,
    'archived_count' => $insertedCount,
    'duplicate_count' => $duplicateCount, // C-1 방어 발동 관측용 (S-2)
    'remaining_count' => $remainingCount,
    'archived_mapping_id' => $archivedMappingId,
    'mapping_batch_id' => $mappingBatchId,
    'archived_by' => $archivedBy,
]);

// 락 획득 실패는 별도 Log::warning 으로 위에서 기록
// Rate limit 초과 (429) 는 Laravel throttle 미들웨어가 자체 로깅
// 0건 chunk (has_more=false, archived_count=0) 도 위 Log::info 로 기록 — 컨트롤러가 서비스 반환 직후 호출 (S-6)
```

MongoDB archive 레코드 자체가 1차 감사 소스 (원본 + 메타 보존). 애플리케이션 로그는 보조.

## 구현 파일

### SVGW (`SeoulVenturesGroupware`)

- `app/Http/Controllers/Review/UploadHistoryController.php` (**신규, 단독 파일 필수**)
  - `archive(Client $client, Request $request)` 메서드
  - 기존 `TargetItemMapActionController` 에 합치지 않는다 — 매핑 ID 비의존 설계의 의미 반영 + 후속 upload-history 액션 (잔여 집계, 수동 재시도 등) 이 들어올 여지 확보
- `app/Services/Review/UploadHistoryArchiveService.php` (신규, 테스트 용이성)
  - `archiveChunk(Client $client, int $configId, string $driverCode, string $targetItemCode, string $clientItemCode, string $archivedBy, ?int $archivedMappingId, string $mappingBatchId, int $chunkSize = 500): ArchiveResult`
  - **I-4 불변**: 서비스는 MySQL 재조회하지 않는다. `driverCode` / `archivedMappingId` 모두 컨트롤러가 1회 조회해 파라미터로 주입.
- 토큰 비교: 기존 `App\Support\Review\ClientNameComparator::equals()` 재활용 (이미 NFC + `\p{Z}` trim 지원). 신규 클래스 만들지 않는다 (S-2).
- `routes/api.php` — 라우트 1개 추가
- `frontend/resources/ts/api/entities/review/uploadHistory.ts` (신규)
  - `archiveUploadHistory(clientId, payload)` 함수
- `frontend/resources/ts/pages/review/data/index.vue` — toolbar 버튼 + 2단계 다이얼로그 + 실행 루프 추가
- `frontend/resources/ts/components/review/ArchiveUploadHistoryDialog.vue` (신규, 관심사 분리)
  - 확인 다이얼로그 (대상 테이블 + 토큰 입력)
  - 진행 다이얼로그 (프로그레스 + 취소)

### 테스트

- `tests/Feature/Review/ArchiveUploadHistoryTest.php`
  - 정상 흐름 (단일 chunk, 멀티 chunk) — 응답에 `mapping_batch_id` (서버 생성 UUID) 포함 검증
  - 토큰 불일치 → 422
  - cross-client config_id → 422
  - 매핑이 삭제된 상태 (mapping_id null) 에서도 archive 동작
  - 0건 요청 (has_more=false, archived_count=0, duplicate_count=0) 멱등
  - **재호출 멱등성**: 같은 원본을 두 번째 호출 시 **응답의 `duplicate_count === 500` 이고 `archived_count === 0`** 검증 (C-1 방어 발동 관측, I-3)
  - **`mapping_batch_id` 재사용**: 같은 튜플의 연속 chunk 호출에서 응답 `mapping_batch_id` 동일값 유지. `Cache::flush` 후 재호출 시 신규 UUID
  - **분산 락**: 같은 튜플에 락이 이미 걸려있으면 423 Locked (Cache::lock 을 mock 또는 실제 Redis 사용)
  - **Rate limit**: 분당 60+1 호출 시 429 반환
- `tests/Unit/Services/Review/UploadHistoryArchiveServiceTest.php`
  - chunk size 경계 (정확히 500, 501, 1000)
  - 아카이브 도큐먼트 메타 필드 검증 (`original_id`, `archived_at`, `archived_by`, `archived_mapping_id`, `archive_batch_id`)
  - `archived_mapping_id` / `driver_code` 가 서비스 호출 1회당 MySQL 재조회 없이 파라미터로 전달되는지 검증
  - `BulkWriteException` 중 code 11000 만 허용, 다른 에러는 전파됨을 검증
  - 불변식 `archived_count + duplicate_count === 조회 건수 (최대 CHUNK_SIZE)` 검증 (S-3)
  - 런타임 `createIndex` idempotent 호출 검증 (I-4)

## 엣지 케이스

### E1. 동일 매핑을 두 운영자가 동시에 실행
- **Cache::lock(튜플키, 30s)** 로 차단됨. 후발 호출은 423 Locked 응답.
- 프론트는 423 수신 시 "다른 운영자가 처리 중" 토스트 노출 후 해당 매핑만 건너뛰고 다음 매핑으로 진행.

### E2. Insert 성공 후 Delete 실패 → 재호출
- archive 의 `{original_id: 1}` 유니크 인덱스가 같은 원본 재 insert 를 차단 (code 11000)
- `ordered:false insertMany` 로 부분 성공 + 부분 duplicate key 모두 허용
- duplicate key 만 있는 WriteError 는 정상 계속, `deleteMany($originalIds)` 로 원본 제거 재시도 → 수렴
- archive 측 중복 누적 없음 (원본 1건당 archive 1건 보장)

### E3. 중간에 새 이관 레코드가 insert 됨
- 업로드 워커가 계속 돌면서 `review_upload_target_list` 에 새 레코드를 만듦
- 프론트가 첫 호출 응답의 `total` 을 기반으로 진행률을 계산했으므로, 실제 처리량이 total 을 초과할 수 있음
- 수용: progress clamp (`Math.max(total, processed)`) 적용. 사용자 혼란 최소화를 위해 안내 문구 추가 여부는 구현 단계 판단.

### E4. target_database_hive 가 `null` 또는 공백
- 검증에서 422 로 반환 (`클라이언트 설정이 불완전합니다`)
- MongoDB 선택 직전 double-check

### E5. 클라이언트는 있지만 MongoDB DB 자체가 존재하지 않음
- MongoDB 는 존재하지 않는 DB/컬렉션을 쿼리해도 에러가 아닌 빈 결과 반환
- `archived_count=0, has_more=false` 응답. 멱등 성공 처리.

### E6. 매우 큰 이관 이력 (예: 10만건)
- 10만 / 500 = 200 회 호출 × 300ms delay = 약 1분 + API 처리 시간
- Rate limit (`throttle:60,1`) 에 의해 분당 60 호출 상한 → 200 회는 최소 3.3 분 분산
- 사용자 UI 대기 시간 수 분 단위 가능. 다이얼로그에 경고 문구 (예: "양이 많으면 수 분 걸릴 수 있습니다") 표시.
- 도중 취소 가능. 이어서 재실행 가능.

### E7. HTTP 타임아웃
- chunk 500 + countDocuments 1회 = 수백 ms 예상 (필터 인덱스 존재 시). 일반 타임아웃 내.
- **대형 hive 주의**: 필터 인덱스 부재 + 누적 100만 건+ 의 hive 에서는 collection scan 으로 chunk 당 수 초 가능. Nginx/PHP-FPM 기본 60초는 넘지 않으나 운영자 대기 누적. 대형 hive 운영자 배포 전 `{driver_code, target_item_code, client_item_code}` 인덱스 생성 권고.
- 프론트 HTTP 타임아웃이 발생해도 서버는 `finally` 까지 실행해 락을 정상 해제 → 다음 호출 정상 수용.
- 느려지면 chunk size 를 200 등으로 조정 (상수 하나).

### E8. 매핑이 이미 삭제된 후 운영자가 동일 튜플로 정리
- 엔드포인트는 매핑 존재 여부 검증하지 않음
- `TargetItemMap` 레코드가 없으면 `archived_mapping_id = null` 로 기록
- UI 에선 기본 노출 안 됨 (선택지 목록에 없으니), 운영자가 API 직접 호출 시나리오.

### E9. Archive 컬렉션 디스크 풀
- `review_upload_target_list_archive` 가 원본만큼 커질 수 있음
- 기존 운영 hive 는 이미 리뷰 원본 데이터가 크기 때문에 누적 증가에 유의
- 대응: 운영 차원에서 주기적 export + 오래된 archive TTL 정리 (본 스펙 밖, O-2 로 이관)
- 첫 호출이 `write error code 12` (exceeded quota) 등으로 실패하면 500 + Sentry. 운영자에게 DBA 확인 요청.

### E10. Redis 락 캐시 미구성
- `Cache::lock()` 이 array driver 에서는 프로세스별 분리라 실제 락 안 됨
- 운영은 Redis 전제 (`config/cache.php` default=`redis`). 배포 전 확인.
- 개발/테스트 환경에서는 락 획득 항상 성공 (실 운영 동시성과 다름) — 테스트 명시.

## 오픈 이슈

### O-1. 복원 UI 제공 여부
- 현재 설계: 복원은 수동 (운영자가 DB 에서 `archived_mapping_id` / `archive_batch_id` 로 조회 후 원본 컬렉션으로 이전)
- 후속 요구가 들어오면 별도 스펙으로 추가
- 본 스펙 밖

### O-2. Archive 컬렉션의 TTL 또는 주기적 정리
- 무기한 보존. 크기 문제 발생 시 별도 운영 규칙 결정.
- 본 스펙 밖

### O-3. 수동 입력 모드 (삭제된 매핑 정리)
- API 자체는 지원하지만 UI 는 미제공
- 당장은 운영자가 API 직접 호출로 처리
- 반복 수요가 생기면 UI 추가

### O-4. 10개 제한의 서버 검증
- 현재 엔드포인트는 per-mapping (1건씩). 10 제한은 UX 가드.
- 서버 보호는 `throttle:60,1` 미들웨어로 충당 (본 스펙에 포함, 1차 I-2 해결).
- **악용 시나리오 수용 계산**: 사용자 1명당 분당 60 chunk = 분당 최대 30,000 문서 archive. MongoDB delete_many + insert_many 의 chunk 500 처리 비용을 고려할 때 운영상 허용 범위.
- 같은 튜플 동시 호출은 분산 락으로, 서로 다른 튜플의 대량 병렬은 throttle 로 차단 — 두 층이 각자 목적.
- 실측 악용 시 client/user scope 로 별도 `RateLimiter::for(...)` 정의 고려.

## 배포 및 릴리즈

- SVGW 단독 변경 (Python 워커 영향 없음)
- MongoDB 컬렉션 `review_upload_target_list_archive` 는 첫 호출 시 암묵적으로 생성됨 — 사전 마이그레이션 불필요
- PR 1개 (백엔드 + 프론트엔드 + 테스트 묶음)
- 릴리즈 방식: 기존 SVGW 패턴 — PR 머지 → 자동 GitHub Actions 배포

## 완료 기준

- [ ] MongoDB `review_upload_target_list_archive` 에 `{original_id: 1}` 유니크 인덱스 생성 (mongosh 또는 migration)
- [ ] 엔드포인트 구현 (분산 락 + ordered:false insertMany + throttle 미들웨어)
- [ ] 서비스 계층 단위 테스트 (chunk 경계, 메타 필드, BulkWriteException 11000 허용)
- [ ] Feature 테스트 9 케이스 (정상/토큰/cross-client/삭제된 매핑/0건/재호출 멱등/락/throttle/delete 실패 복구)
- [ ] 프론트 확인 다이얼로그 + 진행 다이얼로그 (results 1-건 불변성 검증)
- [ ] 취소 동작 검증 (4가지 경로: 시작 전/응답 후/sleep 중/에러 후 — 수동 QA)
- [ ] 실제 curlyshyll 매핑 303315 로 스테이징 동작 확인 후 운영 배포
- [ ] 배포 후 운영자가 대기 중인 요청 처리

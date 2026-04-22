# 매핑 이관 이력 아카이브 (Danger Zone) 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 매핑 관리 페이지에 "이관 이력 삭제" Danger Zone 버튼을 추가, 선택된 매핑(최대 10)의 MongoDB `review_upload_target_list` 레코드를 `review_upload_target_list_archive` 로 안전하게 이동한다.

**Architecture:** 서버가 분산 락 (Redis `Cache::lock`) 과 archive 측 `{original_id:1}` 유니크 인덱스로 멱등성을 보장한다. 프론트는 매핑 단위로 순차 순회, chunk 500 건 단위로 API 를 재호출하며 진행률을 표시하고 중간 취소를 지원한다. `mapping_batch_id` 는 서버 주도 (Redis `Cache::remember` 10분 TTL) 로 클라이언트 통제 없이 한 매핑 처리의 모든 chunk 를 같은 UUID 로 묶는다.

**Tech Stack:**
- Backend: Laravel 11 (PHP 8.3), MongoDB via `mongodb/laravel-mongodb` 5.x, Redis cache, PHPUnit
- Frontend: Vue 3 + Vuetify 3 + TypeScript, Pinia, ofetch (`@/api`)
- 스펙 문서: `docs/superpowers/specs/2026-04-20-archive-upload-history-design.md`

---

## File Structure

**Backend (SeoulVenturesGroupware/):**
- Create: `app/Exceptions/Review/UploadHistoryLockedException.php` — 도메인 예외 (서비스→컨트롤러 경계)
- Create: `app/Services/Review/UploadHistoryArchiveService.php` — MongoDB 처리 + 락 + batch cache
- Create: `app/Http/Controllers/Review/UploadHistoryController.php` — 단독 컨트롤러 (매핑 독립 의미)
- Create: `database/migrations/2026_04_20_000001_create_upload_target_list_archive_index.php` — 유니크 인덱스
- Modify: `routes/api.php` — 라우트 1줄 추가 (auth:sanctum 그룹 내부)
- Create: `tests/Feature/Review/ArchiveUploadHistoryTest.php`
- Create: `tests/Unit/Services/Review/UploadHistoryArchiveServiceTest.php`

**Frontend (SeoulVenturesGroupware/frontend/):**
- Create: `resources/ts/api/entities/review/uploadHistory.ts` — API entity
- Modify: `resources/ts/api/entities/index.ts` — 엔트리 재수출
- Create: `resources/ts/components/review/ArchiveUploadHistoryDialog.vue` — 2단계 다이얼로그
- Modify: `resources/ts/pages/review/data/index.vue` — toolbar 버튼 + 실행 루프

---

## Task 1: 브랜치 & Draft PR 셋업

**Files:**
- Modify: SVGW 저장소 새 브랜치

- [ ] **Step 1: 브랜치 생성**

```bash
cd /opt/SeoulVentures/regle/SeoulVenturesGroupware
git fetch origin
git checkout -b feat/archive-upload-history origin/master
```

- [ ] **Step 2: 스펙·플랜 링크를 readme 성격으로 작업 공간에 확인만**

플랜·스펙은 regle 루트에 이미 커밋됨 (`ed6a78b` 기준). 별도 복사 불필요.

- [ ] **Step 3: Draft PR 생성 (본문은 스펙 요약 + 이 플랜 링크)**

```bash
git push -u origin feat/archive-upload-history
gh pr create --draft --title "feat: 매핑 이관 이력 아카이브 Danger Zone" --body "$(cat <<'EOF'
## Summary
- 매핑 관리 페이지에서 선택 매핑(최대 10개)의 MongoDB 이관 이력을 archive 컬렉션으로 이동
- 서버 주도 mapping_batch_id + 분산 락 + 유니크 인덱스 3층 방어
- 프론트 진행률 · 중간 취소 · 재시작 안전

스펙: `docs/superpowers/specs/2026-04-20-archive-upload-history-design.md`
플랜: `docs/superpowers/plans/2026-04-20-archive-upload-history.md`

## Test plan
- [ ] Feature 테스트 9 케이스 통과
- [ ] Unit 테스트 통과
- [ ] staging 에서 curlyshyll 매핑 303315 동작 확인
- [ ] CACHE_DRIVER=redis 확인

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Task 2: 도메인 예외 클래스

**Files:**
- Create: `app/Exceptions/Review/UploadHistoryLockedException.php`

- [ ] **Step 1: 예외 클래스 작성**

```php
<?php

namespace App\Exceptions\Review;

use RuntimeException;

/**
 * 같은 (client_id, config_id, target_item_code, client_item_code) 튜플에 대한
 * archive 작업이 이미 진행 중일 때 서비스가 throw. 컨트롤러가 catch 하여 423 Locked 응답.
 */
class UploadHistoryLockedException extends RuntimeException
{
}
```

- [ ] **Step 2: 커밋**

```bash
git add app/Exceptions/Review/UploadHistoryLockedException.php
git commit -m "feat: UploadHistoryLockedException 도메인 예외 추가"
```

---

## Task 3: Migration — archive 유니크 인덱스

**Files:**
- Create: `database/migrations/2026_04_20_000001_create_upload_target_list_archive_index.php`

- [ ] **Step 1: 마이그레이션 파일 작성**

```php
<?php

use App\Models\Review\Client;
use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

/**
 * review_upload_target_list_archive 에 {original_id:1} 유니크 인덱스 생성.
 * 운영 hive 목록을 순회 (Client.target_database_hive 기준).
 * 
 * 서비스 런타임에도 멱등 createIndex 를 호출하므로 이 마이그레이션은 성능 최적화.
 */
return new class extends Migration
{
    public function up(): void
    {
        if (config('database.connections.mongodb') === null) {
            return;
        }

        $hives = Client::query()
            ->whereNotNull('target_database_hive')
            ->pluck('target_database_hive')
            ->unique()
            ->values();

        foreach ($hives as $hive) {
            try {
                DB::connection('mongodb')->getClient()
                    ->selectDatabase($hive)
                    ->selectCollection('review_upload_target_list_archive')
                    ->createIndex(
                        ['original_id' => 1],
                        ['unique' => true, 'name' => 'uniq_original_id']
                    );
            } catch (\Throwable $e) {
                // hive 접근 불가 시 skip — 런타임 createIndex 로 보호됨
                logger()->warning('[upload-history-archive] hive index skip', [
                    'hive' => $hive,
                    'error' => $e->getMessage(),
                ]);
            }
        }
    }

    public function down(): void
    {
        // 운영 데이터 보호 — drop 하지 않음
    }
};
```

- [ ] **Step 2: 로컬 마이그레이션 드라이런 (환경 허용 시)**

```bash
php artisan migrate --pretend
```

예상: 에러 없이 출력, 실제 변경은 없음.

- [ ] **Step 3: 커밋**

```bash
git add database/migrations/2026_04_20_000001_create_upload_target_list_archive_index.php
git commit -m "feat: archive 유니크 인덱스 마이그레이션"
```

---

## Task 4: Service 스켈레톤 + 0건 분기 테스트

**Files:**
- Create: `app/Services/Review/UploadHistoryArchiveService.php`
- Create: `tests/Unit/Services/Review/UploadHistoryArchiveServiceTest.php`

- [ ] **Step 1: 0건 분기 실패 테스트 작성**

```php
<?php

namespace Tests\Unit\Services\Review;

use App\Models\Review\Client;
use App\Services\Review\UploadHistoryArchiveService;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class UploadHistoryArchiveServiceTest extends TestCase
{
    public function test_returns_zero_counts_when_no_matching_docs(): void
    {
        $this->skipIfMongoDbUnavailable();

        $client = Client::factory()->create(['target_database_hive' => 'test_empty_hive']);
        $service = app(UploadHistoryArchiveService::class);

        $result = $service->archiveChunk(
            $client,
            configId: 999,
            driverCode: 'nonexistent',
            targetItemCode: 'nonexistent',
            clientItemCode: 'nonexistent',
            archivedBy: 'tester@example.com',
            archivedMappingId: null,
        );

        $this->assertSame(0, $result['archived_count']);
        $this->assertSame(0, $result['duplicate_count']);
        $this->assertSame(0, $result['remaining_count']);
        $this->assertFalse($result['has_more']);
        $this->assertNotEmpty($result['mapping_batch_id']);
    }

    private function skipIfMongoDbUnavailable(): void
    {
        try {
            DB::connection('mongodb')->getClient()->listDatabases();
        } catch (\Throwable) {
            $this->markTestSkipped('MongoDB unavailable');
        }
    }
}
```

- [ ] **Step 2: 실행하여 실패 확인**

```bash
vendor/bin/phpunit --filter=test_returns_zero_counts_when_no_matching_docs
```

예상: FAIL — 클래스 없음 에러.

- [ ] **Step 3: Service 스켈레톤 작성 (0건 분기까지)**

```php
<?php

namespace App\Services\Review;

use App\Exceptions\Review\UploadHistoryLockedException;
use App\Models\Review\Client;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;
use MongoDB\BSON\ObjectId;
use MongoDB\BSON\UTCDateTime;
use MongoDB\Driver\Exception\BulkWriteException;

class UploadHistoryArchiveService
{
    public const CHUNK_SIZE = 500;

    public function archiveChunk(
        Client $client,
        int $configId,
        string $driverCode,
        string $targetItemCode,
        string $clientItemCode,
        string $archivedBy,
        ?int $archivedMappingId,
    ): array {
        $lockKey = sprintf(
            'archive-upload-history:%d:%d:%s:%s',
            $client->id, $configId, $targetItemCode, $clientItemCode
        );
        $lock = Cache::lock($lockKey, 30);
        if (! $lock->get()) {
            Log::warning('[upload-history] lock contention', [
                'client_id' => $client->id, 'config_id' => $configId,
                'target_item_code' => $targetItemCode,
                'client_item_code' => $clientItemCode,
                'archived_by' => $archivedBy,
            ]);
            throw new UploadHistoryLockedException;
        }

        try {
            $batchCacheKey = sprintf(
                'upload-history-batch:%d:%d:%s:%s',
                $client->id, $configId, $targetItemCode, $clientItemCode
            );
            $mappingBatchId = Cache::remember(
                $batchCacheKey,
                600,
                fn() => (string) Str::uuid()
            );

            $db = DB::connection('mongodb')->getClient()
                ->selectDatabase($client->target_database_hive);
            $coll = $db->selectCollection('review_upload_target_list');
            $archiveColl = $db->selectCollection('review_upload_target_list_archive');

            $archiveColl->createIndex(
                ['original_id' => 1],
                ['unique' => true, 'name' => 'uniq_original_id']
            );

            $filter = [
                'driver_code' => $driverCode,
                'target_item_code' => $targetItemCode,
                'client_item_code' => $clientItemCode,
            ];

            $docs = iterator_to_array(
                $coll->find($filter, ['limit' => self::CHUNK_SIZE]),
                false
            );

            if (empty($docs)) {
                Cache::forget($batchCacheKey);
                return [
                    'archived_count' => 0,
                    'duplicate_count' => 0,
                    'remaining_count' => 0,
                    'has_more' => false,
                    'mapping_batch_id' => $mappingBatchId,
                ];
            }

            // 다음 Task 에서 완성
            throw new \LogicException('Not implemented yet');
        } finally {
            optional($lock)->release();
        }
    }
}
```

- [ ] **Step 4: 실행하여 통과 확인**

```bash
vendor/bin/phpunit --filter=test_returns_zero_counts_when_no_matching_docs
```

예상: PASS.

- [ ] **Step 5: 커밋**

```bash
git add app/Services/Review/UploadHistoryArchiveService.php tests/Unit/Services/Review/UploadHistoryArchiveServiceTest.php
git commit -m "feat: UploadHistoryArchiveService 스켈레톤 + 0건 분기"
```

---

## Task 5: Service 정상 흐름 (insert + delete + 카운트)

**Files:**
- Modify: `app/Services/Review/UploadHistoryArchiveService.php`
- Modify: `tests/Unit/Services/Review/UploadHistoryArchiveServiceTest.php`

- [ ] **Step 1: 정상 흐름 실패 테스트 추가**

```php
public function test_archives_and_deletes_matching_docs(): void
{
    $this->skipIfMongoDbUnavailable();

    $hive = 'test_archive_happy_' . uniqid();
    $client = Client::factory()->create(['target_database_hive' => $hive]);

    $db = DB::connection('mongodb')->getClient()->selectDatabase($hive);
    $coll = $db->selectCollection('review_upload_target_list');
    $archiveColl = $db->selectCollection('review_upload_target_list_archive');

    try {
        $coll->insertMany([
            ['driver_code' => 'naver', 'target_item_code' => 'T1', 'client_item_code' => 'C1', 'state' => 'ready', 'upload_key' => 'k1'],
            ['driver_code' => 'naver', 'target_item_code' => 'T1', 'client_item_code' => 'C1', 'state' => 'finished', 'upload_key' => 'k2'],
            ['driver_code' => 'naver', 'target_item_code' => 'OTHER', 'client_item_code' => 'C1', 'state' => 'ready', 'upload_key' => 'k3'],
        ]);

        $result = app(UploadHistoryArchiveService::class)->archiveChunk(
            $client,
            configId: 1,
            driverCode: 'naver',
            targetItemCode: 'T1',
            clientItemCode: 'C1',
            archivedBy: 'tester@example.com',
            archivedMappingId: 42,
        );

        $this->assertSame(2, $result['archived_count']);
        $this->assertSame(0, $result['duplicate_count']);
        $this->assertSame(0, $result['remaining_count']);
        $this->assertFalse($result['has_more']);

        $this->assertSame(1, $coll->countDocuments([])); // OTHER 만 남음
        $this->assertSame(2, $archiveColl->countDocuments([]));

        $archived = iterator_to_array($archiveColl->find([]));
        $this->assertSame(42, $archived[0]['archived_mapping_id']);
        $this->assertSame('tester@example.com', $archived[0]['archived_by']);
        $this->assertNotNull($archived[0]['original_id']);
        $this->assertNotNull($archived[0]['archive_batch_id']);
    } finally {
        $db->drop();
    }
}
```

- [ ] **Step 2: 실행하여 실패 확인**

```bash
vendor/bin/phpunit --filter=test_archives_and_deletes_matching_docs
```

예상: FAIL — `LogicException: Not implemented yet`.

- [ ] **Step 3: Service 본체 완성 (empty check 아래 블록 교체)**

```php
$archivedAt = new UTCDateTime();
$originalIds = [];
foreach ($docs as &$doc) {
    $originalIds[] = $doc['_id'];
    $doc['original_id']         = $doc['_id'];
    $doc['_id']                 = new ObjectId;
    $doc['archived_at']         = $archivedAt;
    $doc['archived_by']         = $archivedBy;
    $doc['archived_mapping_id'] = $archivedMappingId;
    $doc['archive_batch_id']    = $mappingBatchId;
}
unset($doc);

$duplicateCount = 0;
$insertedCount = count($docs);
try {
    $archiveColl->insertMany($docs, ['ordered' => false]);
} catch (BulkWriteException $e) {
    $writeResult = $e->getWriteResult();
    $writeErrors = $writeResult !== null ? $writeResult->getWriteErrors() : [];
    foreach ($writeErrors as $err) {
        if ($err->getCode() !== 11000) {
            throw $e;
        }
        $duplicateCount++;
    }
    $insertedCount = $writeResult !== null
        ? $writeResult->getInsertedCount()
        : count($docs) - $duplicateCount;
}

$coll->deleteMany(['_id' => ['$in' => $originalIds]]);

$remainingCount = $coll->countDocuments($filter);

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
```

(위 블록이 `throw new \LogicException('Not implemented yet');` 을 대체)

- [ ] **Step 4: 실행하여 통과 확인**

```bash
vendor/bin/phpunit --filter=UploadHistoryArchiveServiceTest
```

예상: 두 테스트 PASS.

- [ ] **Step 5: 커밋**

```bash
git add app/Services/Review/UploadHistoryArchiveService.php tests/Unit/Services/Review/UploadHistoryArchiveServiceTest.php
git commit -m "feat: Service 정상 흐름 완성 (insert + delete + 카운트)"
```

---

## Task 6: Service 재호출 멱등성 (duplicate_count) 테스트

**Files:**
- Modify: `tests/Unit/Services/Review/UploadHistoryArchiveServiceTest.php`

- [ ] **Step 1: 재호출 멱등 테스트 추가**

```php
public function test_duplicate_original_ids_are_counted_and_deleted(): void
{
    $this->skipIfMongoDbUnavailable();

    $hive = 'test_archive_duplicate_' . uniqid();
    $client = Client::factory()->create(['target_database_hive' => $hive]);

    $db = DB::connection('mongodb')->getClient()->selectDatabase($hive);
    $coll = $db->selectCollection('review_upload_target_list');
    $archiveColl = $db->selectCollection('review_upload_target_list_archive');

    try {
        // 미리 archive 에 original_id 가 존재하는 상태로 둠 (재호출 시뮬레이션)
        $originalId = new ObjectId;
        $archiveColl->insertOne([
            '_id' => new ObjectId,
            'original_id' => $originalId,
            'driver_code' => 'naver',
            'target_item_code' => 'T1',
            'client_item_code' => 'C1',
            'state' => 'finished',
            'archived_at' => new UTCDateTime(),
            'archived_by' => 'previous@example.com',
            'archived_mapping_id' => 42,
            'archive_batch_id' => 'old-batch',
        ]);
        $archiveColl->createIndex(['original_id' => 1], ['unique' => true]);

        // 원본에 동일 _id 로 남아있는 상태
        $coll->insertOne([
            '_id' => $originalId,
            'driver_code' => 'naver',
            'target_item_code' => 'T1',
            'client_item_code' => 'C1',
            'state' => 'finished',
        ]);

        $result = app(UploadHistoryArchiveService::class)->archiveChunk(
            $client, 1, 'naver', 'T1', 'C1', 'retry@example.com', 42
        );

        $this->assertSame(0, $result['archived_count']);   // 신규 insert 없음
        $this->assertSame(1, $result['duplicate_count']);  // duplicate 로 차단
        $this->assertSame(0, $result['remaining_count']);  // 원본은 삭제됨
        $this->assertSame(0, $coll->countDocuments([]));
        $this->assertSame(1, $archiveColl->countDocuments([])); // 여전히 1건 (기존)
    } finally {
        $db->drop();
    }
}
```

- [ ] **Step 2: 실행하여 통과 확인**

```bash
vendor/bin/phpunit --filter=test_duplicate_original_ids_are_counted_and_deleted
```

예상: PASS (Task 5 에서 duplicate 처리 로직 완성됨).

- [ ] **Step 3: 불변식 테스트 추가 (archived + duplicate === 조회건수)**

```php
public function test_archived_plus_duplicate_equals_chunk_size(): void
{
    $this->skipIfMongoDbUnavailable();

    $hive = 'test_archive_invariant_' . uniqid();
    $client = Client::factory()->create(['target_database_hive' => $hive]);

    $db = DB::connection('mongodb')->getClient()->selectDatabase($hive);
    $coll = $db->selectCollection('review_upload_target_list');
    $archiveColl = $db->selectCollection('review_upload_target_list_archive');

    try {
        $archiveColl->createIndex(['original_id' => 1], ['unique' => true]);

        // 5건 중 2건은 이미 archive 에 들어가 있는 상태 (재호출 시뮬레이션)
        $preArchivedIds = [];
        for ($i = 0; $i < 5; $i++) {
            $id = new ObjectId;
            $coll->insertOne(['_id' => $id, 'driver_code' => 'naver', 'target_item_code' => 'T', 'client_item_code' => 'C', 'state' => 'ready']);
            if ($i < 2) {
                $archiveColl->insertOne([
                    '_id' => new ObjectId, 'original_id' => $id,
                    'archived_at' => new UTCDateTime(), 'archived_by' => 'prev',
                    'archived_mapping_id' => null, 'archive_batch_id' => 'prev',
                ]);
                $preArchivedIds[] = $id;
            }
        }

        $result = app(UploadHistoryArchiveService::class)->archiveChunk(
            $client, 1, 'naver', 'T', 'C', 'tester@example.com', null
        );

        $this->assertSame(5, $result['archived_count'] + $result['duplicate_count']);
        $this->assertSame(3, $result['archived_count']);
        $this->assertSame(2, $result['duplicate_count']);
    } finally {
        $db->drop();
    }
}
```

- [ ] **Step 4: 실행하여 통과 확인**

```bash
vendor/bin/phpunit --filter=UploadHistoryArchiveServiceTest
```

예상: 4 테스트 PASS.

- [ ] **Step 5: 커밋**

```bash
git add tests/Unit/Services/Review/UploadHistoryArchiveServiceTest.php
git commit -m "test: Service 재호출 멱등성 + 불변식 검증"
```

---

## Task 7: Service 분산 락 + mapping_batch_id 재사용 테스트

**Files:**
- Modify: `tests/Unit/Services/Review/UploadHistoryArchiveServiceTest.php`

- [ ] **Step 1: 분산 락 테스트 추가**

```php
public function test_throws_when_lock_contended(): void
{
    $this->skipIfMongoDbUnavailable();

    $client = Client::factory()->create(['target_database_hive' => 'test_lock_' . uniqid()]);

    // 수동으로 같은 락을 선점
    $lockKey = sprintf('archive-upload-history:%d:%d:%s:%s',
        $client->id, 1, 'T', 'C');
    $held = Cache::lock($lockKey, 10);
    $this->assertTrue($held->get());

    try {
        $this->expectException(\App\Exceptions\Review\UploadHistoryLockedException::class);
        app(UploadHistoryArchiveService::class)->archiveChunk(
            $client, 1, 'naver', 'T', 'C', 'tester@example.com', null
        );
    } finally {
        $held->release();
    }
}

public function test_reuses_mapping_batch_id_across_consecutive_chunks(): void
{
    $this->skipIfMongoDbUnavailable();

    $hive = 'test_archive_batchid_' . uniqid();
    $client = Client::factory()->create(['target_database_hive' => $hive]);

    $db = DB::connection('mongodb')->getClient()->selectDatabase($hive);
    $coll = $db->selectCollection('review_upload_target_list');

    try {
        // CHUNK_SIZE + 1 개 삽입 → 2회 호출 필요
        $size = UploadHistoryArchiveService::CHUNK_SIZE + 1;
        $bulk = [];
        for ($i = 0; $i < $size; $i++) {
            $bulk[] = ['driver_code' => 'naver', 'target_item_code' => 'T',
                       'client_item_code' => 'C', 'state' => 'ready', 'upload_key' => "k{$i}"];
        }
        $coll->insertMany($bulk);

        $service = app(UploadHistoryArchiveService::class);
        $res1 = $service->archiveChunk($client, 1, 'naver', 'T', 'C', 'tester@example.com', null);
        $res2 = $service->archiveChunk($client, 1, 'naver', 'T', 'C', 'tester@example.com', null);

        $this->assertSame($res1['mapping_batch_id'], $res2['mapping_batch_id']);
        $this->assertTrue($res1['has_more']);
        $this->assertFalse($res2['has_more']);
    } finally {
        $db->drop();
    }
}
```

- [ ] **Step 2: 필요한 use 구문 테스트 파일 상단에 추가 (누락된 것만)**

```php
use App\Exceptions\Review\UploadHistoryLockedException; // 이미 있으면 skip
use App\Services\Review\UploadHistoryArchiveService;
use Illuminate\Support\Facades\Cache;
use MongoDB\BSON\ObjectId;
use MongoDB\BSON\UTCDateTime;
```

- [ ] **Step 3: 실행하여 통과 확인**

```bash
vendor/bin/phpunit --filter=UploadHistoryArchiveServiceTest
```

예상: 6 테스트 PASS.

- [ ] **Step 4: 커밋**

```bash
git add tests/Unit/Services/Review/UploadHistoryArchiveServiceTest.php
git commit -m "test: Service 분산 락 + mapping_batch_id 재사용"
```

---

## Task 8: Controller + 라우트 + 검증 (happy path 통합)

**Files:**
- Create: `app/Http/Controllers/Review/UploadHistoryController.php`
- Modify: `routes/api.php`

- [ ] **Step 1: Controller 작성**

```php
<?php

namespace App\Http\Controllers\Review;

use App\Exceptions\Review\UploadHistoryLockedException;
use App\Http\Controllers\Controller;
use App\Models\Review\Client;
use App\Models\Review\DriverConfig;
use App\Models\Review\TargetItemMap;
use App\Services\Review\UploadHistoryArchiveService;
use App\Support\Review\ClientNameComparator;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Log;

class UploadHistoryController extends Controller
{
    private const CONFIRM_TOKEN = '위험성을 알고 동의합니다';

    public function __construct(private UploadHistoryArchiveService $service) {}

    public function archive(Client $client, Request $request): JsonResponse
    {
        $validated = $request->validate([
            'config_id'        => 'required|integer|min:1',
            'target_item_code' => 'required|string|min:1',
            'client_item_code' => 'required|string|min:1',
            'confirm_text'     => 'required|string',
        ]);

        if (! $this->confirmTokenMatches($validated['confirm_text'])) {
            return response()->json(['message' => '확인 문구가 일치하지 않습니다.'], 422);
        }

        $driverConfig = DriverConfig::find($validated['config_id']);
        if (! $driverConfig || $driverConfig->client_id !== $client->id) {
            return response()->json(
                ['message' => '드라이버 설정이 해당 클라이언트에 속하지 않습니다.'],
                422
            );
        }

        if (empty($client->target_database_hive) || empty($driverConfig->driver_code)) {
            return response()->json(
                ['message' => '클라이언트 또는 드라이버 설정이 불완전합니다.'],
                422
            );
        }

        $archivedMappingId = TargetItemMap::query()
            ->where('client_id', $client->id)
            ->where('config_id', $validated['config_id'])
            ->where('target_item_code', $validated['target_item_code'])
            ->where('client_item_code', $validated['client_item_code'])
            ->value('id');

        $archivedBy = Auth::user()->email ?? Auth::user()->name ?? 'unknown';

        try {
            $result = $this->service->archiveChunk(
                $client,
                $validated['config_id'],
                $driverConfig->driver_code,
                $validated['target_item_code'],
                $validated['client_item_code'],
                $archivedBy,
                $archivedMappingId,
            );
        } catch (UploadHistoryLockedException) {
            return response()->json(
                ['message' => '같은 매핑에 대한 아카이브 작업이 이미 진행 중입니다. 잠시 후 재시도하세요.'],
                423
            );
        }

        Log::info('[upload-history] archive chunk', [
            'client_id' => $client->id,
            'config_id' => $validated['config_id'],
            'driver_code' => $driverConfig->driver_code,
            'target_item_code' => $validated['target_item_code'],
            'client_item_code' => $validated['client_item_code'],
            'target_database_hive' => $client->target_database_hive,
            'archived_count' => $result['archived_count'],
            'duplicate_count' => $result['duplicate_count'],
            'remaining_count' => $result['remaining_count'],
            'archived_mapping_id' => $archivedMappingId,
            'mapping_batch_id' => $result['mapping_batch_id'],
            'archived_by' => $archivedBy,
        ]);

        return response()->json([
            'success' => true,
            ...$result,
        ]);
    }

    private function confirmTokenMatches(string $input): bool
    {
        return ClientNameComparator::equals($input, self::CONFIRM_TOKEN);
    }
}
```

- [ ] **Step 2: 라우트 추가**

`routes/api.php` 에서 `Route::middleware('auth:sanctum')->group(function() {` 블록 내부의 `Route::prefix('review')->group(function () {` 하위에, TargetItemMapActionController 부근에 1줄 추가:

```php
Route::post('clients/{client}/upload-history/archive',
    [\App\Http\Controllers\Review\UploadHistoryController::class, 'archive']
)->middleware('throttle:60,1');
```

- [ ] **Step 3: 로컬 라우트 확인**

```bash
php artisan route:list --path=review/clients | grep upload-history
```

예상: `POST api/review/clients/{client}/upload-history/archive ... throttle:60,1`

- [ ] **Step 4: 커밋**

```bash
git add app/Http/Controllers/Review/UploadHistoryController.php routes/api.php
git commit -m "feat: UploadHistoryController + 라우트 + throttle"
```

---

## Task 9: Feature 테스트 — 인증·정상 흐름

**Files:**
- Create: `tests/Feature/Review/ArchiveUploadHistoryTest.php`

- [ ] **Step 1: 인증·정상 테스트 작성**

```php
<?php

namespace Tests\Feature\Review;

use App\Models\Review\Client;
use App\Models\Review\DriverConfig;
use App\Models\User;
use Illuminate\Support\Facades\DB;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class ArchiveUploadHistoryTest extends TestCase
{
    public function test_requires_auth(): void
    {
        $response = $this->postJson('/api/review/clients/1/upload-history/archive', [
            'config_id' => 1,
            'target_item_code' => 'T',
            'client_item_code' => 'C',
            'confirm_text' => '위험성을 알고 동의합니다',
        ]);

        $response->assertStatus(401);
    }

    public function test_archives_happy_path(): void
    {
        $this->skipIfMongoDbUnavailable();

        /** @var User $user */
        $user = User::factory()->create();
        Sanctum::actingAs($user);

        $hive = 'test_archive_feature_' . uniqid();
        $client = Client::factory()->create(['target_database_hive' => $hive]);
        $driverConfig = DriverConfig::factory()->create([
            'client_id' => $client->id,
            'driver_code' => 'naver',
        ]);

        $db = DB::connection('mongodb')->getClient()->selectDatabase($hive);
        $coll = $db->selectCollection('review_upload_target_list');

        try {
            $coll->insertMany([
                ['driver_code' => 'naver', 'target_item_code' => 'T', 'client_item_code' => 'C', 'state' => 'ready', 'upload_key' => 'k1'],
                ['driver_code' => 'naver', 'target_item_code' => 'T', 'client_item_code' => 'C', 'state' => 'finished', 'upload_key' => 'k2'],
            ]);

            $response = $this->postJson("/api/review/clients/{$client->id}/upload-history/archive", [
                'config_id' => $driverConfig->id,
                'target_item_code' => 'T',
                'client_item_code' => 'C',
                'confirm_text' => '위험성을 알고 동의합니다',
            ]);

            $response->assertOk();
            $response->assertJson([
                'success' => true,
                'archived_count' => 2,
                'duplicate_count' => 0,
                'remaining_count' => 0,
                'has_more' => false,
            ]);
            $this->assertNotEmpty($response->json('mapping_batch_id'));
        } finally {
            $db->drop();
        }
    }

    private function skipIfMongoDbUnavailable(): void
    {
        try {
            DB::connection('mongodb')->getClient()->listDatabases();
        } catch (\Throwable) {
            $this->markTestSkipped('MongoDB unavailable');
        }
    }
}
```

- [ ] **Step 2: 실행하여 통과 확인**

```bash
vendor/bin/phpunit --filter=ArchiveUploadHistoryTest
```

예상: 2 PASS (또는 MongoDB 미연결 환경이면 1 PASS + 1 skipped).

- [ ] **Step 3: 커밋**

```bash
git add tests/Feature/Review/ArchiveUploadHistoryTest.php
git commit -m "test: Feature 인증 + 정상 흐름"
```

---

## Task 10: Feature 테스트 — validation 실패 케이스

**Files:**
- Modify: `tests/Feature/Review/ArchiveUploadHistoryTest.php`

- [ ] **Step 1: 4건 validation 테스트 추가**

```php
public function test_rejects_wrong_confirm_text(): void
{
    Sanctum::actingAs(User::factory()->create());
    $client = Client::factory()->create();

    $response = $this->postJson("/api/review/clients/{$client->id}/upload-history/archive", [
        'config_id' => 1,
        'target_item_code' => 'T',
        'client_item_code' => 'C',
        'confirm_text' => '잘못된 문구',
    ]);

    $response->assertStatus(422);
    $response->assertJson(['message' => '확인 문구가 일치하지 않습니다.']);
}

public function test_rejects_cross_client_config_id(): void
{
    Sanctum::actingAs(User::factory()->create());

    $clientA = Client::factory()->create();
    $clientB = Client::factory()->create();
    $configOfB = DriverConfig::factory()->create(['client_id' => $clientB->id]);

    $response = $this->postJson("/api/review/clients/{$clientA->id}/upload-history/archive", [
        'config_id' => $configOfB->id,
        'target_item_code' => 'T',
        'client_item_code' => 'C',
        'confirm_text' => '위험성을 알고 동의합니다',
    ]);

    $response->assertStatus(422);
}

public function test_rejects_nonexistent_config_id_as_422(): void
{
    Sanctum::actingAs(User::factory()->create());
    $client = Client::factory()->create();

    $response = $this->postJson("/api/review/clients/{$client->id}/upload-history/archive", [
        'config_id' => 999999,
        'target_item_code' => 'T',
        'client_item_code' => 'C',
        'confirm_text' => '위험성을 알고 동의합니다',
    ]);

    $response->assertStatus(422); // NOT 404
}

public function test_validates_required_fields(): void
{
    Sanctum::actingAs(User::factory()->create());
    $client = Client::factory()->create();

    $response = $this->postJson("/api/review/clients/{$client->id}/upload-history/archive", []);

    $response->assertStatus(422);
    $response->assertJsonValidationErrors(['config_id', 'target_item_code', 'client_item_code', 'confirm_text']);
}
```

- [ ] **Step 2: 실행하여 통과 확인**

```bash
vendor/bin/phpunit --filter=ArchiveUploadHistoryTest
```

예상: 6 PASS.

- [ ] **Step 3: 커밋**

```bash
git add tests/Feature/Review/ArchiveUploadHistoryTest.php
git commit -m "test: validation 실패 케이스 4건"
```

---

## Task 11: Feature 테스트 — 0건 · 재호출 멱등 · 삭제된 매핑

**Files:**
- Modify: `tests/Feature/Review/ArchiveUploadHistoryTest.php`

- [ ] **Step 1: 3건 멱등 케이스 추가**

```php
public function test_returns_zero_counts_when_empty(): void
{
    $this->skipIfMongoDbUnavailable();

    Sanctum::actingAs(User::factory()->create());
    $hive = 'test_archive_empty_' . uniqid();
    $client = Client::factory()->create(['target_database_hive' => $hive]);
    $driverConfig = DriverConfig::factory()->create(['client_id' => $client->id, 'driver_code' => 'naver']);

    $response = $this->postJson("/api/review/clients/{$client->id}/upload-history/archive", [
        'config_id' => $driverConfig->id,
        'target_item_code' => 'T', 'client_item_code' => 'C',
        'confirm_text' => '위험성을 알고 동의합니다',
    ]);

    $response->assertOk();
    $response->assertJson(['archived_count' => 0, 'duplicate_count' => 0, 'has_more' => false]);
}

public function test_handles_missing_mapping_row(): void
{
    $this->skipIfMongoDbUnavailable();

    Sanctum::actingAs(User::factory()->create());
    $hive = 'test_archive_noMap_' . uniqid();
    $client = Client::factory()->create(['target_database_hive' => $hive]);
    $driverConfig = DriverConfig::factory()->create(['client_id' => $client->id, 'driver_code' => 'naver']);

    $db = DB::connection('mongodb')->getClient()->selectDatabase($hive);
    $coll = $db->selectCollection('review_upload_target_list');
    $archiveColl = $db->selectCollection('review_upload_target_list_archive');

    try {
        $coll->insertOne(['driver_code' => 'naver', 'target_item_code' => 'T',
                          'client_item_code' => 'C', 'state' => 'finished']);

        $response = $this->postJson("/api/review/clients/{$client->id}/upload-history/archive", [
            'config_id' => $driverConfig->id,
            'target_item_code' => 'T', 'client_item_code' => 'C',
            'confirm_text' => '위험성을 알고 동의합니다',
        ]);

        $response->assertOk();
        $response->assertJson(['archived_count' => 1]);

        // archived_mapping_id 는 null 로 저장되어야 함
        $archived = iterator_to_array($archiveColl->find([]));
        $this->assertNull($archived[0]['archived_mapping_id']);
    } finally {
        $db->drop();
    }
}

public function test_second_call_returns_duplicate_count(): void
{
    $this->skipIfMongoDbUnavailable();

    Sanctum::actingAs(User::factory()->create());
    $hive = 'test_archive_idempotent_' . uniqid();
    $client = Client::factory()->create(['target_database_hive' => $hive]);
    $driverConfig = DriverConfig::factory()->create(['client_id' => $client->id, 'driver_code' => 'naver']);

    $db = DB::connection('mongodb')->getClient()->selectDatabase($hive);
    $coll = $db->selectCollection('review_upload_target_list');

    try {
        $coll->insertOne(['driver_code' => 'naver', 'target_item_code' => 'T',
                          'client_item_code' => 'C', 'state' => 'finished', 'upload_key' => 'k1']);

        $payload = [
            'config_id' => $driverConfig->id,
            'target_item_code' => 'T', 'client_item_code' => 'C',
            'confirm_text' => '위험성을 알고 동의합니다',
        ];

        // 첫 호출: archive
        $res1 = $this->postJson("/api/review/clients/{$client->id}/upload-history/archive", $payload);
        $res1->assertOk()->assertJson(['archived_count' => 1, 'duplicate_count' => 0]);

        // 원본을 수동으로 복원 (재호출 시뮬레이션 — insert 만 성공하고 delete 실패한 상황)
        $originalId = iterator_to_array(
            $db->selectCollection('review_upload_target_list_archive')->find([])
        )[0]['original_id'];
        $coll->insertOne([
            '_id' => $originalId,
            'driver_code' => 'naver', 'target_item_code' => 'T',
            'client_item_code' => 'C', 'state' => 'finished', 'upload_key' => 'k1',
        ]);

        // 두 번째 호출: archive 는 duplicate, 원본은 재삭제
        $res2 = $this->postJson("/api/review/clients/{$client->id}/upload-history/archive", $payload);
        $res2->assertOk()->assertJson(['archived_count' => 0, 'duplicate_count' => 1]);
    } finally {
        $db->drop();
    }
}
```

- [ ] **Step 2: 실행하여 통과 확인**

```bash
vendor/bin/phpunit --filter=ArchiveUploadHistoryTest
```

예상: 9 PASS.

- [ ] **Step 3: 커밋**

```bash
git add tests/Feature/Review/ArchiveUploadHistoryTest.php
git commit -m "test: 0건·삭제된 매핑·재호출 멱등성"
```

---

## Task 12: Frontend — API entity

**Files:**
- Create: `frontend/resources/ts/api/entities/review/uploadHistory.ts`
- Modify: `frontend/resources/ts/api/entities/index.ts`

- [ ] **Step 1: API entity 작성**

```ts
import { type ApiResponse, post } from '@/api'

export interface ArchiveUploadHistoryPayload {
  config_id: number
  target_item_code: string
  client_item_code: string
  confirm_text: string
}

export interface ArchiveUploadHistoryResponse extends ApiResponse {
  archived_count: number
  duplicate_count: number
  remaining_count: number
  has_more: boolean
  mapping_batch_id: string
}

export const uploadHistoryApi = {
  archive: (
    clientId: number,
    payload: ArchiveUploadHistoryPayload,
  ): Promise<ArchiveUploadHistoryResponse> =>
    post(`/review/clients/${clientId}/upload-history/archive`, payload),
}

export default uploadHistoryApi
```

- [ ] **Step 2: index.ts 에 재수출 추가 (배럴 파일이 존재할 때만)**

`frontend/resources/ts/api/entities/index.ts` 를 열어 기존 형식을 확인. 다른 review entity 재수출 근처에 1줄 추가:

```ts
export { default as uploadHistoryApi } from './review/uploadHistory'
```

(auto-import 경로가 개별 파일 기준이라면 이 단계는 스킵 — 확인 후 판단)

- [ ] **Step 3: 타입 체크**

```bash
cd frontend && bun run typecheck
```

예상: 에러 없음.

- [ ] **Step 4: 커밋**

```bash
git add frontend/resources/ts/api/entities/review/uploadHistory.ts frontend/resources/ts/api/entities/index.ts
git commit -m "feat(frontend): uploadHistory API entity"
```

---

## Task 13: Frontend — ArchiveUploadHistoryDialog 컴포넌트

**Files:**
- Create: `frontend/resources/ts/components/review/ArchiveUploadHistoryDialog.vue`

- [ ] **Step 1: 컴포넌트 작성**

```vue
<script setup lang="ts">
import { computed, ref, watch } from 'vue'

const CONFIRM_TOKEN = '위험성을 알고 동의합니다'

interface MappingRow {
  id: number
  config_id: number
  client_id: number
  driver_name: string
  target_item_code: string
  target_item_name: string | null
  client_item_code: string
  client_item_name: string | null
}

const props = defineProps<{
  modelValue: boolean
  selectedMappings: MappingRow[]
}>()

const emit = defineEmits<{
  'update:modelValue': [v: boolean]
  'confirm': []
}>()

// 확인 단계 상태
const confirmInput = ref('')
const canStart = computed(() => confirmInput.value.trim() === CONFIRM_TOKEN)

// 진행 단계 상태 — 부모가 setProgress 로 갱신
const phase = ref<'confirm' | 'progress'>('confirm')
const currentMappingIndex = ref(0)
const currentMapping = ref<MappingRow | null>(null)
const processed = ref(0)
const total = ref(0)
const completedMappings = ref(0)

watch(() => props.modelValue, (v) => {
  if (v) {
    phase.value = 'confirm'
    confirmInput.value = ''
  }
})

function close() {
  emit('update:modelValue', false)
}

function startConfirm() {
  if (!canStart.value) return
  phase.value = 'progress'
  emit('confirm')
}

defineExpose({
  setProgress(payload: {
    currentMappingIndex: number
    mapping: MappingRow
    processed: number
    total: number
    completedMappings: number
  }) {
    currentMappingIndex.value = payload.currentMappingIndex
    currentMapping.value = payload.mapping
    processed.value = payload.processed
    total.value = payload.total
    completedMappings.value = payload.completedMappings
  },
  requestCancel(cb: () => void) {
    cb()
  },
})

const cancelRequested = ref(false)
function onCancel() {
  cancelRequested.value = true
  emit('update:modelValue', false)
}
</script>

<template>
  <VDialog :model-value="modelValue" max-width="720" persistent @update:model-value="close">
    <VCard v-if="phase === 'confirm'">
      <VCardTitle class="text-error">이관 이력 삭제 (Danger Zone)</VCardTitle>
      <VCardText>
        <VAlert type="warning" variant="tonal" class="mb-4">
          <div class="font-weight-bold mb-2">중복 이관 위험</div>
          <ul class="mb-0">
            <li>review_upload_target_list 의 해당 매핑 레코드를 archive 컬렉션으로 이동합니다.</li>
            <li>자사몰에 이미 업로드된 리뷰는 외부 시스템에 그대로 남아있으며, 다음 업로드 사이클에서 동일 리뷰가 중복 등록될 수 있습니다.</li>
            <li>실행 중 취소해도 이미 이동된 기록은 자동으로 되돌릴 수 없습니다. 복원이 필요하면 데이터팀에 문의해 주세요.</li>
          </ul>
        </VAlert>

        <div class="mb-4">
          <div class="text-subtitle-2 mb-2">대상 매핑 ({{ selectedMappings.length }}개)</div>
          <VDataTable
            :headers="[
              { title: '매핑 ID', key: 'id', width: 90 },
              { title: '채널명', key: 'driver_name' },
              { title: '채널 상품코드', key: 'target_item_code' },
              { title: '자사몰 코드', key: 'client_item_code' },
              { title: '상품명 (채널 / 자사몰)', key: 'names' },
            ]"
            :items="selectedMappings"
            hide-default-footer
            items-per-page="-1"
            density="compact"
          >
            <template #item.names="{ item }">
              {{ item.target_item_name || '-' }} / {{ item.client_item_name || '-' }}
            </template>
          </VDataTable>
        </div>

        <VTextField
          v-model="confirmInput"
          label="확인 문구 입력"
          :placeholder="CONFIRM_TOKEN"
          :hint="`정확히 입력: ${CONFIRM_TOKEN}`"
          persistent-hint
          density="comfortable"
        />
      </VCardText>
      <VCardActions>
        <VSpacer />
        <VBtn @click="close">취소</VBtn>
        <VBtn color="error" :disabled="!canStart" @click="startConfirm">삭제 시작</VBtn>
      </VCardActions>
    </VCard>

    <VCard v-else>
      <VCardTitle>이관 이력 삭제 진행 중</VCardTitle>
      <VCardText>
        <div v-if="currentMapping" class="mb-2">
          매핑 {{ currentMappingIndex + 1 }}/{{ selectedMappings.length }}:
          #{{ currentMapping.id }} ({{ currentMapping.driver_name }})
        </div>
        <VProgressLinear
          :model-value="total > 0 ? (processed / total) * 100 : 0"
          height="16"
          color="primary"
          class="mb-2"
        >
          <template #default>{{ processed }} / {{ total }}</template>
        </VProgressLinear>

        <div class="text-caption mt-4">전체 진행: {{ completedMappings }} / {{ selectedMappings.length }} 매핑 완료</div>
        <VProgressLinear
          :model-value="(completedMappings / selectedMappings.length) * 100"
          height="8"
          color="primary"
          class="mt-1"
        />
      </VCardText>
      <VCardActions>
        <VSpacer />
        <VBtn @click="onCancel" :disabled="cancelRequested">{{ cancelRequested ? '취소 처리 중...' : '취소' }}</VBtn>
      </VCardActions>
    </VCard>
  </VDialog>
</template>
```

- [ ] **Step 2: 타입 체크**

```bash
cd frontend && bun run typecheck
```

예상: 에러 없음.

- [ ] **Step 3: 커밋**

```bash
git add frontend/resources/ts/components/review/ArchiveUploadHistoryDialog.vue
git commit -m "feat(frontend): ArchiveUploadHistoryDialog 컴포넌트"
```

---

## Task 14: Frontend — 매핑 관리 페이지 버튼 + 실행 루프

**Files:**
- Modify: `frontend/resources/ts/pages/review/data/index.vue`

- [ ] **Step 1: 기존 파일 구조 파악**

```bash
grep -n "selectedMappings\|toolbar\|useConfirmDialog\|sleep" frontend/resources/ts/pages/review/data/index.vue | head -20
```

(파일 구조 확인 후 아래 스니펫을 적절한 위치에 삽입)

- [ ] **Step 2: import 추가**

파일 상단 script 블록의 기존 import 블록에 추가:

```ts
import ArchiveUploadHistoryDialog from '@/components/review/ArchiveUploadHistoryDialog.vue'
import { uploadHistoryApi } from '@/api/entities/review/uploadHistory'
```

(import 대신 auto-import 가 동작하면 `uploadHistoryApi` 만 직접 `api/entities` 에서 들어올 수 있음 — 타입 체크로 확인)

- [ ] **Step 3: state / 타입 / 실행 함수 추가 (script 내 selectedMappings 근처)**

```ts
const archiveDialog = ref(false)
const archiveDialogRef = ref<InstanceType<typeof ArchiveUploadHistoryDialog> | null>(null)
const archiveRunning = ref(false)
const cancelled = ref(false)

type ArchiveStatus = 'completed' | 'error' | 'cancelled' | 'skipped'
interface ArchiveResult {
  mapping: typeof selectedMappings.value[number]
  status: ArchiveStatus
  archived: number
  message?: string
}

const canArchive = computed(() =>
  selectedMappings.value.length >= 1 && selectedMappings.value.length <= 10
)
const archiveDisabledReason = computed(() => {
  if (selectedMappings.value.length === 0) return '선택된 매핑이 없습니다'
  if (selectedMappings.value.length > 10) return '최대 10개까지 선택 가능합니다'
  return ''
})

function sleep(ms: number) {
  return new Promise<void>(resolve => setTimeout(resolve, ms))
}

async function runArchive() {
  const selected = [...selectedMappings.value]
  const results: ArchiveResult[] = []
  archiveRunning.value = true
  cancelled.value = false

  try {
    for (const [idx, m] of selected.entries()) {
      if (cancelled.value) {
        results.push({ mapping: m, status: 'skipped', archived: 0 })
        continue
      }

      archiveDialogRef.value?.setProgress({
        currentMappingIndex: idx,
        mapping: m,
        processed: 0,
        total: 0,
        completedMappings: results.filter(r => r.status === 'completed').length,
      })

      let processed = 0
      let total: number | null = null
      let finalStatus: ArchiveStatus = 'cancelled'
      let errorMessage: string | undefined

      try {
        while (true) {
          let res
          try {
            res = await uploadHistoryApi.archive(m.client_id, {
              config_id: m.config_id,
              target_item_code: m.target_item_code,
              client_item_code: m.client_item_code,
              confirm_text: '위험성을 알고 동의합니다',
            })
          } catch (e) {
            finalStatus = 'error'
            errorMessage = (e as Error).message || 'network error'
            break
          }

          if (!res.success) {
            finalStatus = 'error'
            errorMessage = (res as { message?: string }).message || 'unknown error'
            break
          }

          if (total === null) total = res.archived_count + res.remaining_count
          processed += res.archived_count
          archiveDialogRef.value?.setProgress({
            currentMappingIndex: idx,
            mapping: m,
            processed: Math.min(processed, total),
            total,
            completedMappings: results.filter(r => r.status === 'completed').length,
          })

          if (!res.has_more) {
            finalStatus = 'completed'
            break
          }

          if (cancelled.value) {
            finalStatus = 'cancelled'
            break
          }

          await sleep(300)

          if (cancelled.value) {
            finalStatus = 'cancelled'
            break
          }
        }
      } finally {
        results.push(
          finalStatus === 'error'
            ? { mapping: m, status: 'error', archived: processed, message: errorMessage! }
            : { mapping: m, status: finalStatus, archived: processed }
        )
      }
    }

    showArchiveSummary(results, cancelled.value)
  } finally {
    archiveRunning.value = false
    archiveDialog.value = false
  }
}

function showArchiveSummary(results: ArchiveResult[], wasCancelled: boolean) {
  const completed = results.filter(r => r.status === 'completed').length
  const errors = results.filter(r => r.status === 'error').length
  const partialCancelled = results.filter(r => r.status === 'cancelled').length
  const skipped = results.filter(r => r.status === 'skipped').length

  if (wasCancelled) {
    snackbar.info(
      `취소됨. 완료 ${completed}개 / 취소 ${partialCancelled}개 / 건너뜀 ${skipped}개 / 에러 ${errors}개`
    )
  } else if (errors > 0) {
    snackbar.error(`완료 ${completed}개 / 에러 ${errors}개`)
  } else {
    snackbar.success(`이관 이력 삭제 완료 (${completed}개 매핑)`)
  }
}
```

(정확한 삽입 위치: 기존 `const MSG_XXX` 상수 블록 및 snackbar 등이 선언된 script 뒷부분)

- [ ] **Step 4: template 에 toolbar 버튼 추가**

테이블 toolbar 영역 (다른 selection-based 액션 버튼 근처) 에:

```vue
<VBtn
  color="error"
  variant="tonal"
  :disabled="!canArchive || archiveRunning"
  @click="archiveDialog = true"
>
  <template #prepend><VIcon icon="tabler-archive" /></template>
  이관 이력 삭제
  <VTooltip v-if="!canArchive" activator="parent" location="bottom">
    {{ archiveDisabledReason }}
  </VTooltip>
</VBtn>

<ArchiveUploadHistoryDialog
  ref="archiveDialogRef"
  v-model="archiveDialog"
  :selected-mappings="selectedMappings"
  @confirm="runArchive"
/>
```

- [ ] **Step 5: 로컬 dev 서버로 UI 확인**

```bash
cd frontend && bun run dev
```

브라우저에서 매핑 관리 페이지 접속 → 매핑 선택 → "이관 이력 삭제" 버튼 노출 확인. 클릭 시 다이얼로그 열림, 확인 문구 오입력 시 "삭제 시작" disabled.

- [ ] **Step 6: 타입 체크 + 린트**

```bash
cd frontend && bun run typecheck && bun run lint
```

예상: 에러 없음.

- [ ] **Step 7: 커밋**

```bash
git add frontend/resources/ts/pages/review/data/index.vue
git commit -m "feat(frontend): 매핑 관리 페이지에 이관 이력 삭제 버튼 + 실행 루프"
```

---

## Task 15: 수동 QA 체크리스트 (staging)

**Files:** 없음 — QA 세션

- [ ] **Step 1: staging 환경에 배포**

```bash
git push origin feat/archive-upload-history
gh pr ready  # draft 해제
# 머지 전 staging 수동 배포 방식이면 팀 컨벤션 따르기
```

- [ ] **Step 2: 환경 전제 확인**

```bash
# SSH staging
ssh -i ~/.ssh/SeoulVentures.pem ubuntu@3.34.97.42
cat /var/www/groupware/.env | grep -E "CACHE_DRIVER|REDIS_HOST"
```

예상: `CACHE_DRIVER=redis` (값이 file 이면 배포 중단 후 인프라팀 확인).

- [ ] **Step 3: curlyshyll 매핑 303315 로 실 동작 확인**

- 매핑 관리 페이지에서 "자사몰 189 / 채널 4995740052" 매핑 검색
- 단독 선택 → "이관 이력 삭제" 버튼
- 확인 다이얼로그에 매핑 정보 노출 확인
- 확인 문구 `위험성을 알고 동의합니다` 입력 → 삭제 시작
- 진행 다이얼로그 프로그레스 확인 (N건 / N건)
- 완료 스낵바 확인

- [ ] **Step 4: MongoDB 상태 확인**

```bash
# curlyshyll 의 target_database_hive 에 접속
mongosh "mongodb://<prod>/<hive>"
> db.review_upload_target_list.countDocuments({driver_code:'<code>', target_item_code:'4995740052', client_item_code:'189'})
> db.review_upload_target_list_archive.countDocuments({archived_mapping_id: 303315})
```

전자 0, 후자 >0 이어야 함.

- [ ] **Step 5: 취소 시나리오 확인**

- 이관 이력이 큰 매핑 선택 (필요시 테스트용으로 다른 매핑)
- 삭제 시작 → 진행 중 "취소" 클릭
- 스낵바에 "취소됨. 완료 N개 / 취소 M개 ..." 확인
- 다시 같은 매핑 선택 → 삭제 시작 → 남은 건수부터 이어서 처리되는지 확인

- [ ] **Step 6: PR 본문에 QA 결과 기록 + Ready for review 전환**

```bash
gh pr comment --body "스테이징 QA 완료: curlyshyll 매핑 303315 이관 이력 N건 archive. archive_batch_id: <uuid>"
```

---

## Task 16: 세션 메모리 업데이트

**Files:**
- Create: `/opt/SeoulVentures/.claude/projects/-opt-SeoulVentures-regle/memory/archive-upload-history-2026-04-20.md`
- Modify: `/opt/SeoulVentures/.claude/projects/-opt-SeoulVentures-regle/memory/MEMORY.md`

- [ ] **Step 1: 작업 메모리 파일 작성**

```markdown
---
name: 이관 이력 아카이브 (Danger Zone)
description: 2026-04-20 SVGW 매핑 관리 페이지에 이관 이력 삭제 버튼 추가. MongoDB review_upload_target_list → archive 이동. 서버 주도 mapping_batch_id + 분산 락 + 유니크 인덱스 3층 방어.
type: project
---

## 배경
Mall 160 curlyshyll 매핑 303315 운영자 요청 기반. 이관 이력을 매핑 단위로 안전하게 초기화하는 어드민 툴.

## 핵심 설계 결정
- 엔드포인트: POST /api/review/clients/{client}/upload-history/archive (튜플 기반, 매핑 ID 비의존)
- 프론트가 매핑당 순차 호출, chunk 500 단위 재호출
- 서버 mapping_batch_id: Cache::remember 10분 TTL, 클라이언트 통제 X
- 락: Cache::lock 30초 TTL 튜플 키
- archive 컬렉션: {original_id:1} 유니크 인덱스 (migration + 런타임 이중 보장)
- 토큰: "위험성을 알고 동의합니다" (ClientNameComparator::equals 재사용)
- 한계: 선택 최대 10 매핑 (UX 가드), throttle:60,1 (사용자별 분당 60 호출)

## Why 이관 이력만 archive, TargetItemMap 카운터는 손 안 댐
사용자 요구사항. MongoDB 처리만.

## How to apply
후속 유사 Danger Zone 기능 설계 시 참고. 특히 "서버 주도 batch_id", "분산 락 + 유니크 인덱스 2층 방어", "매핑 단위 순차 + chunk 재시작" 패턴.

스펙: docs/superpowers/specs/2026-04-20-archive-upload-history-design.md
플랜: docs/superpowers/plans/2026-04-20-archive-upload-history.md
PR: SeoulVenturesGroupware#<번호>
```

- [ ] **Step 2: MEMORY.md 에 한 줄 추가**

`## 최근 주요 작업` 섹션 상단에:

```markdown
- **이관 이력 아카이브 Danger Zone** (2026-04-20) — [상세](./archive-upload-history-2026-04-20.md). SVGW 매핑 관리 페이지 + MongoDB archive 이동. 분산 락 + 유니크 인덱스 + 서버 주도 mapping_batch_id
```

- [ ] **Step 3: regle 루트에서 커밋 (서브모듈 포인터 동시 이동)**

```bash
cd /opt/SeoulVentures/regle
git add SeoulVenturesGroupware
git commit -m "chore: SVGW 서브모듈 업데이트 — 이관 이력 아카이브 기능 (#<번호>)"
```

(메모리 파일은 `.claude/projects` 밖 경로라 별도 관리 — 커밋 대상 아님)

---

## Task 17: 머지 (사용자 승인 후)

**조건:** CLAUDE.md 18항 "사용자 승인 후 머지" — 사용자가 "머지" 를 명시 지시할 때까지 대기.

- [ ] **Step 1: 사용자에게 머지 가능 상태 보고**

"모든 테스트 통과, staging QA 완료, 리뷰 반영 완료. 머지해도 될까요?" — 대답 후 진행.

- [ ] **Step 2: 머지**

```bash
gh pr merge --squash --delete-branch
```

- [ ] **Step 3: 머지 후 정리**

```bash
git checkout master && git pull
git branch -d feat/archive-upload-history
git remote prune origin
```

---

## 리스크 & 대응

- **Redis 미구성** (E10): 배포 전 `.env` 확인. CACHE_DRIVER 가 file 이면 batch_id 재사용·락 둘 다 기능 저하. 배포 중단.
- **대형 hive 인덱스 부재**: chunk countDocuments 가 느릴 수 있음. 필요 시 `review_upload_target_list` 에 `{driver_code, target_item_code, client_item_code}` 인덱스 추가.
- **동시 운영자**: 분산 락이 차단하고 프론트가 423 을 다음 매핑으로 skip 처리. 부작용 없음.
- **매핑 이미 삭제**: `archived_mapping_id = null` 로 기록, 동작 정상.

## 완료 정의

- [ ] Unit 테스트 6 케이스 통과
- [ ] Feature 테스트 9 케이스 통과
- [ ] 프론트 typecheck + lint 통과
- [ ] staging QA: curlyshyll 매핑 303315 이관 이력 archive 성공 확인
- [ ] archive 컬렉션에 원본 + 메타 (`original_id`, `archived_at`, `archived_by`, `archived_mapping_id`, `archive_batch_id`) 저장 확인
- [ ] 취소·재시작 수동 QA 확인
- [ ] PR 리뷰 승인
- [ ] 사용자 명시 머지 승인
- [ ] 메모리 업데이트 + MEMORY.md 인덱스 반영

# 매핑 일괄 삭제 감사 테이블 + UI 안전 장치 설계

**작성일**: 2026-04-08 (1차)
**최종 갱신**: 2026-04-08 (PR#541 리뷰 반영, 선택 삭제/UX 분리/안전성 보강)
**대상 저장소**: `SeoulVenturesGroupware`
**대상 DB**: `retaku_admin` (운영 Aurora MySQL 8.0)
**관련 사고**: 2026-04-07 00:56 발생, 2026-04-08 백업 Aurora 스냅샷에서 원본 id 복원 완료. Client 1538(바닐라코) 매핑 93건 실수 삭제.

---

## 개요

`review_target_item_map` 테이블의 **일괄 삭제 실수**로 매핑 전량이 사라지는 사고를 방지하고, 사고 발생 시 **즉시 복원 가능한 감사 기반**을 만든다. 핵심 운영 테이블은 스키마/쿼리 변경 없이 그대로 두고, **신규 감사 테이블**에 삭제 이벤트를 원본 그대로 기록하는 방식을 택한다.

## 목표

1. **사고 복구 능력**: 매핑 삭제가 발생하면 즉시 `원본 id + 모든 컬럼`을 복원할 수 있어야 한다 (백업 스냅샷 복원 없이)
2. **운영 쿼리 무영향**: 드라이버, 크롤러, 리뷰 업로드 핫 패스(Python SQLModel, Presto, Laravel Eloquent/Query Builder)의 쿼리 경로에 **전혀 손대지 않는다**
3. **UI 실수 방지**: 전체 매핑 삭제 버튼은 **업체명 타이핑 확인**이 있어야만 실행 가능하도록 변경
4. **감사 메타 확보**: 누가, 언제, 어떤 경로로, 왜 삭제했는지 기록

## 비목표

- Eloquent `SoftDeletes` trait 도입 (raw/Presto 경로 호환성 리스크, 의존 파일 10~15개로 범위 과다)
- Python `SQLModel` 글로벌 필터 도입
- UNIQUE 인덱스 변경 (`deleted_at` 포함)
- 권한 시스템 전면 개편 (별도 이슈에서)
- `review_client_items`, `review_targets` 등 형제 테이블의 감사 (필요 시 후속 스펙에서 동일 패턴 확장)
- 단일 행 삭제 경로(`TargetItemMapController::destroy`) 감사 — 이번 사고 원인은 일괄 삭제이며, 단일 삭제 감사는 범위 확장 후 별도 결정

---

## 배경 / 현상

- `review_target_item_map` 는 운영 DB에서 37만+ 행을 가진 핫 테이블로, Python 드라이버 50+, Laravel Eloquent, Laravel Query Builder, Presto/Athena raw SQL 등 **광범위한 읽기 경로**를 가진다.
- 삭제 경로는 한 곳: `SeoulVenturesGroupware/app/Services/Review/TargetItemMapService::deleteBulk` → `$client->targetItemMaps()->delete()`
- 호출은 프런트 `/review/data` 페이지의 **업체 매핑 정보 삭제** 버튼(`index.vue:1420`) → `DELETE /review/clients/{client}/target-item-map`
- 2026-04-07 00:56 경 직원이 이 버튼을 실수로 눌러 Client 1538의 93건 전량 삭제. 백업 Aurora 스냅샷 복원 후 원본 id 유지 INSERT 로 복구 완료 (별도 메모리 `banila-mapping-restore-2026-04-08.md` 참고).

---

## 아키텍처

```
[프런트 /review/data]
    │  "업체 매핑 정보 삭제" 버튼
    │
    ▼
[DeleteAllMappingsDialog] ─ 업체명 직접 타이핑 확인 + reason(선택)
    │
    │  DELETE /review/clients/{client}/target-item-map
    │  body: { driver_config_id?, reason? }
    │
    ▼
[TargetItemMapController::destroyBulk]
    │
    ▼
[TargetItemMapService::deleteBulk]  (단일 DB 트랜잭션)
    │
    ├─ 1. 감사 메타 준비 (user, via='bulk_button', reason)
    ├─ 2. INSERT INTO retaku_admin.review_target_item_map_audit
    │       SELECT ... FROM retaku_admin.review_target_item_map WHERE ...
    ├─ 3. DELETE FROM retaku_admin.review_target_item_map WHERE ...
    ├─ 4. 건수 검증 (감사 INSERT count == DELETE count)
    └─ 5. 불일치 시 throw → 트랜잭션 rollback

[복원 필요 시]
    │
    ▼
[Artisan: target-item-map:restore-from-audit]
    │  --client=1538 [--driver-config=3834] [--deleted-at-from=...]
    │
    ├─ 1. 감사 행 조회 (원본 컬럼 그대로)
    ├─ 2. 운영에 id 충돌 여부 확인 (있으면 ABORT)
    ├─ 3. 트랜잭션으로 원본 id + 모든 컬럼 그대로 INSERT
    └─ 4. pre/in-tx/post 카운트 검증 후 COMMIT
```

---

## 변경 범위

### A. DB 마이그레이션 — 감사 테이블 신설

#### A-1. 파일: `database/migrations/2026_04_08_000001_create_review_target_item_map_audit_table.php`

```php
public function up(): void
{
    Schema::connection('retaku_admin')->create('review_target_item_map_audit', function (Blueprint $table) {
        $table->bigIncrements('audit_id');

        // 감사 메타
        $table->timestamp('deleted_at')->useCurrent()->index('idx_audit_deleted_at');
        $table->string('deleted_by', 255)->nullable()->comment('actor email or CLI name');
        $table->string('deleted_via', 64)->nullable()
            ->comment('bulk_button | bulk_button_selected | api | cli | system');
        $table->string('reason', 500)->nullable();
        $table->string('request_id', 64)->nullable()->index('idx_audit_request_id');

        // 원본 복제 — review_target_item_map 의 SHOW CREATE TABLE 결과(bigint
        // unsigned, varchar(255) COLLATE utf8mb4_unicode_ci, ready/failed/
        // finished_cnt 는 NOT NULL DEFAULT 0)와 정확히 동일한 타입을 사용한다.
        $table->unsignedBigInteger('orig_id')->index('idx_audit_orig_id');
        $table->unsignedBigInteger('client_id');
        $table->unsignedBigInteger('config_id');
        $table->string('target_database_hive', 255);
        $table->string('driver_code', 255);
        $table->string('review_service', 255);
        $table->string('target_item_code', 255);
        $table->string('client_item_code', 255);
        $table->bigInteger('similarity')->nullable();
        $table->text('intersection')->nullable();
        $table->bigInteger('collected_review_count')->nullable();
        $table->bigInteger('filtered_review_count')->nullable();
        $table->bigInteger('ready_cnt')->default(0);
        $table->bigInteger('failed_cnt')->default(0);
        $table->bigInteger('finished_cnt')->default(0);
        $table->timestamp('orig_created_at')->nullable();
        $table->timestamp('orig_updated_at')->nullable();

        $table->index(['client_id', 'config_id'], 'idx_audit_client_config');
    });
}
```

**주의사항**:
- **FK 제약 없음**: 감사 테이블은 원본이 삭제되어도 남아야 하므로 `client_id`/`config_id`에 FK를 걸지 않는다.
- **UNIQUE 없음**: 같은 원본 id가 삭제→복원→재삭제를 반복할 수 있으므로 `orig_id` UNIQUE 금지. 단순 인덱스.
- **원본 컬럼 타입 일치**: 위 코드는 실제 `SHOW CREATE TABLE retaku_admin.review_target_item_map` 결과(`bigint unsigned`, `varchar(255) COLLATE utf8mb4_unicode_ci`, `ready/failed/finished_cnt NOT NULL DEFAULT 0`)와 동일한 타입으로 작성된다. 타입이 달라지면 복원 시 컬럼 의미 비교/검증이 어려워지므로 피한다.
- `deleted_at`은 `DEFAULT CURRENT_TIMESTAMP`, NOT NULL.
- 원본 `id` 컬럼은 `orig_id`로 이름 변경 — 감사 테이블 자체 PK(`audit_id`)와 혼동 방지.
- **마이그레이션 파일명**: `2026_04_08_000001_create_review_target_item_map_audit_table.php` (000001).

#### A-2. 컬럼 타입 재확인 쿼리 (마이그레이션 작성자 전용)

```sql
SELECT COLUMN_NAME, COLUMN_TYPE, IS_NULLABLE, COLUMN_DEFAULT
FROM information_schema.COLUMNS
WHERE TABLE_SCHEMA='retaku_admin' AND TABLE_NAME='review_target_item_map'
ORDER BY ORDINAL_POSITION;
```

---

### B. 백엔드 변경 — SeoulVenturesGroupware

#### B-1. 신규 모델: `app/Models/Review/TargetItemMapAudit.php`

감사 레코드는 **append-only / immutable** 이다. 모델 수준에서 mass assignment 와
update/delete 자체를 차단해 누군가 실수로 감사 로그를 오염시키는 것을 막는다.

```php
class TargetItemMapAudit extends Model
{
    public const TABLE = 'review_target_item_map_audit';

    protected $connection = 'retaku_admin';
    protected $table = self::TABLE;
    protected $primaryKey = 'audit_id';
    public $timestamps = false;

    // append-only: mass assignment 전면 차단. 신규 행은 raw INSERT 로만.
    protected $guarded = ['*'];

    // PDO 드라이버 설정에 따른 string 반환 방지를 위해 정수 컬럼도 명시 cast.
    protected $casts = [
        'deleted_at'             => 'datetime',
        'orig_created_at'        => 'datetime',
        'orig_updated_at'        => 'datetime',
        'audit_id'               => 'integer',
        'orig_id'                => 'integer',
        'client_id'              => 'integer',
        'config_id'              => 'integer',
        'similarity'             => 'integer',
        'collected_review_count' => 'integer',
        'filtered_review_count'  => 'integer',
        'ready_cnt'              => 'integer',
        'failed_cnt'             => 'integer',
        'finished_cnt'           => 'integer',
    ];

    protected static function boot(): void
    {
        parent::boot();
        static::updating(static fn () => throw new \LogicException(
            'TargetItemMapAudit 레코드는 변경할 수 없습니다 (append-only).'
        ));
        static::deleting(static fn () => throw new \LogicException(
            'TargetItemMapAudit 레코드는 삭제할 수 없습니다 (append-only).'
        ));
    }
}
```

**같이 추가되는 enum**: `app/Enums/Review/TargetItemMapDeleteVia.php`

```php
enum TargetItemMapDeleteVia: string
{
    case BulkButton         = 'bulk_button';
    case BulkButtonSelected = 'bulk_button_selected';
    case Api                = 'api';
    case Cli                = 'cli';
    case System             = 'system';
}
```
Service / Controller 의 `$deletedVia` 파라미터 타입은 이 enum 으로 강제된다 —
오타 ('bulk_buton' 등) 가 정적 분석에서 잡힌다.

#### B-2. 서비스 수정: `app/Services/Review/TargetItemMapService.php`

```php
public function deleteBulk(
    Client $client,
    ?int $driverConfigId = null,
    ?array $ids = null,                                              // 선택 삭제 모드
    ?string $reason = null,
    ?string $deletedBy = null,
    TargetItemMapDeleteVia $deletedVia = TargetItemMapDeleteVia::BulkButton,
    ?string $requestId = null
): array {
    $requestId = $requestId ?: (string) Str::uuid();

    // 트랜잭션 안에서 감사 INSERT → 운영 DELETE → 건수 검증 까지만 묶고,
    // ReviewCountManager 캐시 리셋은 트랜잭션 밖에서 실행한다 (실패가 감사/
    // 삭제 rollback 으로 전염되는 것을 막기 위함).
    $result = DB::connection('retaku_admin')->transaction(function () use (
        $client, $driverConfigId, $ids, $reason, $deletedBy, $deletedVia, $requestId
    ) {
        $mapTable   = TargetItemMap::TABLE;
        $auditTable = TargetItemMapAudit::TABLE;
        $hasIds     = !empty($ids);
        $idPlaceholders = $hasIds ? implode(',', array_fill(0, count($ids), '?')) : '';

        // 1) 감사 INSERT ... SELECT FOR UPDATE — 동시 삭제/수정 팬텀 방지
        $sql = "INSERT INTO {$auditTable} (...)
                SELECT NOW(), ?, ?, ?, ?, id, client_id, config_id, ...
                FROM {$mapTable}
                WHERE client_id = ?"
            . ($driverConfigId ? ' AND config_id = ?' : '')
            . ($hasIds ? " AND id IN ({$idPlaceholders})" : '')
            . ' FOR UPDATE';
        DB::connection('retaku_admin')->insert($sql, [...]);

        $auditCount = DB::connection('retaku_admin')
            ->table($auditTable)->where('request_id', $requestId)->count();

        // 2) 운영 DELETE
        $deletedCount = $client->targetItemMaps()
            ->when($driverConfigId, fn ($q) => $q->where('config_id', $driverConfigId))
            ->when($hasIds, fn ($q) => $q->whereIn('id', $ids))
            ->delete();

        // 3) 건수 검증 — 불일치 시 RuntimeException 으로 rollback
        if ($auditCount !== $deletedCount) {
            throw new \RuntimeException("Audit count mismatch: audit={$auditCount}, delete={$deletedCount}");
        }

        return ['deletedCount' => $deletedCount, 'auditCount' => $auditCount,
                'requestId' => $requestId, 'driverConfigId' => $driverConfigId];
    });

    // 4) 카운트 리셋 — 트랜잭션 밖, 실패는 swallow + log
    try {
        if ($result['driverConfigId']) {
            $this->reviewCountManager->resetClientReviewCount($client->id);
            $this->reviewCountManager->resetDriverConfigReviewCount($result['driverConfigId']);
        } else {
            // 선택 삭제 시에도 영향 드라이버 집합을 정밀 계산할 수 없으므로
            // 클라이언트 전체 리셋으로 폴백한다.
            $this->reviewCountManager->resetClientReviewCount($client->id, true);
        }
    } catch (\Throwable $e) {
        Log::warning('[deleteBulk] resetReviewCount 실패 — 삭제는 이미 커밋됨', [...]);
    }

    // 0건 결과는 success 로 반환하되 감사 가능하게 흔적을 남긴다.
    if ($result['deletedCount'] === 0) {
        Log::warning('[deleteBulk] 0건 삭제 — 빈 범위 가능성', [...]);
    }

    unset($result['driverConfigId']);
    return $result;
}
```

**구현 노트**:
- 두 모드(전체 / 선택)를 단일 메서드로 처리. 선택 모드는 `$ids` 비-비어 있음으로 식별.
- `request_id` 는 외부 X-Request-Id 헤더 또는 신규 UUID v4. audit 테이블에서 이번 배치만 골라내는 식별자로 쓰인다. 외부 헤더 신뢰성에 따라 이론적 충돌 가능성 존재.
- `FOR UPDATE` — 동시 삭제/삽입 팬텀 방지. REPEATABLE-READ 환경에서 안전.
- 건수 검증 실패는 트랜잭션 rollback → 감사/운영 모두 원상 복구.
- ReviewCountManager 리셋은 의도적으로 트랜잭션 밖. 카운트 캐시 실패가 사고 복구용 감사 행을 같이 날리는 걸 막는다. 실패는 `QueryException | RedisException` 만 swallow + `Log::warning` + `report($e)` (Sentry) 로 전파. `TypeError` 같은 프로그래밍 에러는 그대로 bubble up.
- 0건 결과는 422 가 아닌 200 + `Log::warning` + 프런트 `snackbar.warning` 으로 분기. 호출자(컨트롤러/UI) 가 별도로 사용자에게 알릴 수 있다.
- **응답 payload 는 `deletedCount` / `auditCount` / `requestId` 3 필드만 노출**. Service 는 내부적으로 `driverConfigId` 를 담아 반환하지만 `unset` 으로 제거한 뒤 컨트롤러로 넘긴다. 프런트 `BulkDeleteResult` 타입과 1:1 대응.

#### B-3. 컨트롤러 수정: `app/Http/Controllers/Review/TargetItemMapController.php`

```php
public function destroyBulk(Client $client, Request $request)
{
    $request->validate([
        'driver_config_id' => 'nullable|integer',
        'ids'              => 'nullable|array|min:1|max:2000',  // 선택 모드, 상한 보호
        'ids.*'            => 'integer|min:1|distinct',
        'reason'           => 'nullable|string|max:500',
        'confirm_name'     => 'required_without:ids|string',     // ids 있으면 면제
    ]);

    $ids = $request->input('ids');
    $driverConfigId = $request->input('driver_config_id');
    $isSelectedMode = !empty($ids);

    if (!$isSelectedMode) {
        // 전체 모드: ClientNameComparator (양 끝 유니코드 공백 trim + NFC) 로
        // 업체명 타이핑 일치를 재검증. 내부 공백은 보존되어 "A 사" / "A사" 가
        // 별개 업체로 취급된다.
        if (!ClientNameComparator::equals($request->input('confirm_name'), $client->name)) {
            return response()->json(['message' => '업체명 확인이 일치하지 않습니다.'], 422);
        }
    } else {
        // 선택 모드: 모든 ids 가 해당 client(+ optional driver_config_id) 소속인지
        // 사전 검증. driver_config_id 가 동시 전달되면 그 조건까지 AND 로 강화해
        // silent 0건(서버는 매칭 없는데 ownership 만 통과) 결과를 차단한다.
        $ownedCount = TargetItemMap::query()
            ->whereIn('id', $ids)
            ->where('client_id', $client->id)
            ->when($driverConfigId, fn ($q) => $q->where('config_id', $driverConfigId))
            ->count();

        if ($ownedCount !== count($ids)) {
            return response()->json(
                ['message' => '일부 매핑이 해당 업체/드라이버 범위에 속하지 않습니다.'],
                422
            );
        }
    }

    $user = Auth::user();
    // request_id 는 외부 X-Request-Id 헤더를 받지 않는다 — 재사용된 헤더가
    // Service 의 audit_count 계산을 과거 행까지 부풀려 rollback 을 유발.
    // Service 가 항상 신규 UUID v4 를 생성하도록 null 을 전달한다.
    return $this->targetItemMapService->deleteBulk(
        client: $client,
        driverConfigId: $driverConfigId,
        ids: $ids,
        reason: $request->input('reason'),
        deletedBy: $user?->email ?? $user?->name ?? 'unknown',
        deletedVia: $isSelectedMode
            ? TargetItemMapDeleteVia::BulkButtonSelected
            : TargetItemMapDeleteVia::BulkButton,
        requestId: null,
    );
}

```

**업체명 비교 유틸** — `App\Support\Review\ClientNameComparator::equals(string, string)`:

- 양 끝 유니코드 공백(`\p{Z}` — NBSP, em space, 전각 공백 포함)만 제거하고, 내부 공백은 유지한다.
- NFC 정규화로 결합 자모 ↔ 완성형 한글을 통일한다.
- `preg_replace` 나 `\Normalizer::normalize` 가 실패하면 `Log::warning` 으로 흔적을 남기고 가장 보수적인 결과(양끝 공백만 trim 된 원본)를 반환한다.
- 프런트 `frontend/resources/ts/utils/review/clientNameComparator.ts` 에 동일 규칙을 구현해 **버튼 활성 조건과 서버 검증이 동일** 하게 동작하도록 대칭성을 보장한다.

**구현 노트**:
- `confirm_name` validation 은 서버에서 재검증 (cURL 등 우회 차단). 정규화로 전각 공백/결합 자모 우회까지 막는다.
- 선택 모드 ownership 검증은 `driver_config_id` 까지 AND 로 결합 — 두 파라미터 동시 전달 시 silent 0건을 미연에 차단.
- `ids` 는 `min:1|max:2000|distinct` 로 빈 배열, 과대 배치, 중복을 모두 거른다. 2000 초과는 프런트가 chunked 호출로 분할.
- `Auth::user()` null safe 접근 (`?->`). 인증 미들웨어가 먼저 401 을 반환하므로 정상 경로에선 발생하지 않지만 안전 측.

#### B-4. 복원용 Artisan Command: `app/Console/Commands/RestoreTargetItemMapFromAudit.php`

```bash
php artisan target-item-map:restore-from-audit \
    --client=1538 \
    [--driver-config=3834] \
    [--deleted-at-from="2026-04-07 00:00:00"] \
    [--deleted-at-to="2026-04-07 23:59:59"] \
    [--request-id=<uuid>] \
    [--dry-run] \
    [--force]
```

- `--dry-run`: 대상 상위 10건만 출력하고 종료.
- `--force`: 대화형 confirm 프롬프트를 건너뛰고 즉시 복원. CI/자동화 경로 전용. 미지정 시 엔터만 치면 취소되어 exit code `2` (= `EXIT_CANCELED`, SUCCESS 와 구분) 로 종료된다.
- 복원 실패는 `Log::error` + `report($e)` 로 Sentry 에 전파된다.

**동작**:
1. `--client` 또는 `--request-id` 중 최소 하나 필수 (둘 다 없으면 FAILURE 종료).
2. 감사 테이블에서 조건에 맞는 행 조회 — 동일 `orig_id` 에 대해 **가장 큰 `audit_id`** 행 1건만 선택. 동일 `deleted_at`(초 단위 충돌) 케이스에서도 deterministic 단일 행 보장.
3. 각 `orig_id` 가 운영 `review_target_item_map` 에 이미 존재하는지 확인 — 있으면 PK 충돌로 ABORT.
4. UNIQUE `review_map_code_unique(client_id, config_id, target_item_code, client_item_code)` 충돌 검사 — `client_id` 별로 그룹 쿼리 1회로 batch 비교 (N+1 회피). 충돌 시 ABORT.
5. `--dry-run` 이면 상위 10건 미리보기만 출력 후 종료. 아니면 사용자 `confirm()` 후 단일 트랜잭션 INSERT → postCount 검증 → COMMIT.
6. 실패 시 `Log::error('[target-item-map:restore] failed', [exception, ...])` + 콘솔에 스택 트레이스 출력.
7. 감사 행에 `restored_at` 같은 플래그는 **남기지 않는다** (감사 = 이벤트 로그, immutable).

**비제공 옵션** — 강제 덮어쓰기(`REPLACE`) 모드는 복원 의도에 반하므로 제공하지 않는다.

---

### C. 프런트 변경 — SeoulVenturesGroupware/frontend

#### C-1. `resources/ts/pages/review/data/index.vue`

##### C-1a. 툴바 두 행 분리 + 매핑 삭제 드롭다운

기존 단일 줄에 모여 있던 8 개 버튼을 **데이터 작업 그룹** 과 **Target 작업 그룹** 두 행으로 분리한다. 매핑 삭제는 단일 버튼이 아니라 드롭다운으로 한 단계 안으로 들이고, 데이터 작업 그룹의 끝에 둔다 — 자주 쓰는 다른 버튼과 인접해 실수 클릭이 발생하던 문제(2026-04-07 사고)를 직접 차단.

```
[데이터 작업 그룹]
상품명 수집 ▼ │ 유사도 생성 ▼ │ 리뷰 수집 ▼ │ 매핑 데이터 추가 │ 엑셀 다운로드 │ 리뷰 수 계산 │ 매핑 정보 삭제 ▼
                                                                                                  ├ 선택된 매핑(N) 삭제
                                                                                                  └ 업체 매핑 전체 삭제

[Target 작업 그룹]
Target 액션 ▼
```

```vue
<div class="d-flex flex-column gap-2">
  <!-- 데이터 작업 그룹 (안전한 액션). 매핑 삭제는 이 그룹의 끝에 드롭다운으로
       만 노출하며, Target 작업 그룹과는 별도 줄에 분리한다. WARNING: 매핑 정보
       삭제를 단일 버튼으로 다시 노출하지 말 것 (2026-04-07 사고 참조). -->
  <div class="d-flex flex-wrap gap-2">
    <!-- 상품명 수집 / 유사도 생성 / 리뷰 수집 / 매핑 데이터 추가 / 엑셀 / 리뷰 수 계산 ... -->

    <VMenu>
      <template #activator="{ props }">
        <VBtn v-bind="props" variant="outlined" color="error" :disabled="!selectedClient">
          매핑 정보 삭제
          <VIcon end icon="tabler-chevron-down" />
        </VBtn>
      </template>
      <VList>
        <VListItem :disabled="selectedMappings.length === 0" @click="openDeleteSelectedDialog">
          선택된 매핑({{ selectedMappings.length }}) 삭제
        </VListItem>
        <VDivider />
        <VListItem class="text-error" @click="openDeleteAllDialog">
          업체 매핑 전체 삭제
        </VListItem>
      </VList>
    </VMenu>
  </div>

  <!-- Target 작업 그룹 (특수/위험 액션) -->
  <div class="d-flex flex-wrap gap-2">
    <!-- Target 액션 ▼ -->
  </div>
</div>
```

##### C-1b. 두 다이얼로그 — 전체 / 선택

**전체 삭제 다이얼로그** (`deleteAllDialog`): 업체명 직접 타이핑 + 사유(선택) 입력. `canConfirmDeleteAll` computed 가 입력 일치 + `!isDeletingAll` 양쪽을 모두 만족해야 활성. 서버 422 응답은 `getErrorMessage(response.error)` 로 추출해 사용자에게 그대로 노출.

**선택 삭제 다이얼로그** (`deleteSelectedDialog`): 사용자가 이미 명시적으로 선택한 항목이라 업체명 타이핑까지는 과한 UX로 판단, 사유(선택) + 단순 confirm. `targetItemMapApi.deleteSelectedTargetItemMaps(clientId, ids, reason)` 로 호출.

**0건 결과**: 두 다이얼로그 모두 `data.deletedCount === 0` 일 때는 `snackbar.success` 가 아니라 `snackbar.warning` 으로 분리 표시 ("삭제 대상 매핑이 없었습니다") — 의도하지 않은 빈 범위 삭제를 사용자가 즉시 인지할 수 있도록.

```ts
const confirmDeleteAllMappings = async () => {
  if (!canConfirmDeleteAll.value || !selectedClient.value) return
  isDeletingAll.value = true
  try {
    const response = await targetItemMapApi.deleteTargetItemMapsForClient(
      selectedClient.value.id,
      deleteAllConfirmName.value.trim(),
      deleteAllReason.value || undefined,
    )

    if (response.success && response.data) {
      const { deletedCount, requestId } = response.data
      if (deletedCount === 0)
        snackbar.warning('삭제 대상 매핑이 없었습니다.')
      else
        snackbar.success(`${deletedCount}건의 매핑을 삭제했습니다. (감사 ID: ${requestId})`)
      deleteAllDialog.value = false
      await Promise.all([loadMappings(), loadClientStats(), loadDriverConfigs()])
    }
    else {
      // del() 은 4xx/5xx 도 throw 하지 않고 success:false 로 swallow 한다.
      // 서버의 422 message ("업체명 확인이 일치하지 않습니다." 등) 를 그대로
      // 노출해 silent failure 를 막는다.
      snackbar.error(getErrorMessage(response.error, '매핑 삭제에 실패했습니다.'))
    }
  }
  catch (error) {
    handleError(error, { notificationMessage: '매핑 삭제에 실패했습니다.' })
  }
  finally {
    isDeletingAll.value = false
  }
}
```

**중요 포인트** (PR#519 교훈 반영):
- `:disabled="!selectedClient"` / `selectedMappings.length === 0` 가드 둘 다 적용
- `isDeletingAll` / `isDeletingSelected` 가드로 중복 요청 방지
- `success && data` 분기에 더해 `deletedCount === 0` 도 명시적으로 분리
- `else` 분기에서 `getErrorMessage(response.error)` 로 서버 본문 노출 (silent failure 방지)
- `:loading` 바인딩

#### C-2. API 엔티티 수정: `resources/ts/api/entities/review/targetItemMap.ts`

3 개 함수 시그니처:

```ts
deleteTargetItemMapsForDriverConfig(clientId, driverConfigId, confirmName, reason?)
deleteTargetItemMapsForClient(clientId, confirmName, reason?)
deleteSelectedTargetItemMaps(clientId, ids: number[], reason?)        // 신규
```

세 함수 모두 `Promise<ApiResponse<BulkDeleteResult>>` 를 반환:

```ts
interface BulkDeleteResult {
  deletedCount: number
  auditCount: number
  requestId: string
}
```

#### C-3. `del()` body 지원

`api/index.ts::del` 에 optional `body?: unknown` 파라미터 추가 — DELETE 메서드 본문으로 `confirm_name` / `reason` / `ids` 등을 전달하기 위함. 기존 호출과 backward compatible.

---

## 데이터 모델 요약

### 신규: `retaku_admin.review_target_item_map_audit`

| 카테고리 | 컬럼 | 비고 |
|---|---|---|
| 감사 PK | `audit_id BIGINT AUTO_INCREMENT` | 감사 테이블 자체 PK |
| 감사 메타 | `deleted_at`, `deleted_by`, `deleted_via`, `reason`, `request_id` | `deleted_at`은 NOT NULL DEFAULT CURRENT_TIMESTAMP |
| 원본 식별 | `orig_id` | 원본 `review_target_item_map.id`, 인덱스만, UNIQUE 아님 |
| 원본 복제 | 나머지 17개 컬럼 | `review_target_item_map`의 모든 컬럼을 그대로 (타입/길이/nullable 일치) |
| 인덱스 | `deleted_at`, `orig_id`, `(client_id, config_id)` | 복원 조회 성능 |

---

## 삭제 시퀀스 다이어그램

```
프런트                  컨트롤러              서비스                DB (retaku_admin)
  │                        │                    │                          │
  │ 타이핑 확인 OK          │                    │                          │
  │────────────────────────▶                    │                          │
  │ DELETE .../target-item-map                  │                          │
  │     { confirm_name, reason }                │                          │
  │                        │ validate()          │                          │
  │                        │ confirm_name 일치   │                          │
  │                        │────────────────────▶                          │
  │                        │ deleteBulk()        │                          │
  │                        │                    │ BEGIN                     │
  │                        │                    │──────────────────────────▶│
  │                        │                    │ INSERT INTO audit          │
  │                        │                    │    SELECT ... FOR UPDATE  │
  │                        │                    │──────────────────────────▶│
  │                        │                    │                 N rows    │
  │                        │                    │ ◀──────────────────────── │
  │                        │                    │ DELETE FROM map           │
  │                        │                    │──────────────────────────▶│
  │                        │                    │                 N rows    │
  │                        │                    │ ◀──────────────────────── │
  │                        │                    │ 건수 검증 (a == d)         │
  │                        │                    │ COMMIT                    │
  │                        │                    │──────────────────────────▶│
  │                        │ ◀── { deletedCount, auditCount, requestId }    │
  │ ◀── success, N         │                    │                          │
```

---

## 복원 SOP (표준 절차)

### 시나리오 1 — 실수 직후 즉시 복원

1. 담당자가 Claude/운영자에게 복원 요청 (Client ID + 대략적 시점)
2. 운영자가 `target-item-map:restore-from-audit --client=<id> --dry-run` 실행
3. 출력된 예상 복원 건수/샘플 확인
4. `--dry-run` 제외하고 재실행
5. Slack `#ops` 채널에 결과 보고

### 시나리오 2 — 2026-04-08 복원 작업 같은 사후 복원

감사 테이블에 **기록이 없을 때** 는 기존 방식(백업 Aurora 스냅샷에서 SELECT → 운영 INSERT) 사용. 이번 사고가 마지막이 되도록 본 스펙을 배포.

### 시나리오 3 — 일부 행만 선택적 복원

`--deleted-at-from/--deleted-at-to` / `--request-id` 옵션으로 시간 범위/배치 제한. `--orig-id=1443078,...` 옵션은 **현재 미구현** (필요 시 후속 이슈에서 추가 검토).

---

## 엣지 케이스

### EC-1. 감사 INSERT는 성공, DELETE 실패
- 트랜잭션 rollback → 감사 행도 사라짐. **운영 상태 그대로**.

### EC-2. DELETE 중 일부 행만 삭제
- InnoDB 단일 DELETE 문은 원자적. 건수 검증 실패 시 rollback으로 일관성 확보.

### EC-3. 동시 삭제 2건 (같은 client, 서로 다른 config_id)
- `FOR UPDATE` 로 행 단위 락. 다른 config_id는 lock 경합 없음. 같은 config_id 중복 삭제는 한쪽이 대기 후 0 rows DELETE로 끝남 (이미 삭제됨).

### EC-4. `deleted_at` 동일 시각 중복
- `audit_id` PK가 있어 문제 없음. `request_id` 필터로 이번 배치 구분.
- 복원 커맨드도 `MAX(audit_id)` 서브쿼리로 단일 행을 보장 (EC-5 참고).

### EC-5. 동일 `orig_id`가 여러 번 삭제-복원-재삭제
- `orig_id` UNIQUE 아님 → 감사 행이 여러 개 쌓임. 복원 시 `MAX(audit_id)` 로 가장 최근 감사 행 1건만 선택한다 (`audit_id` 는 auto_increment 라 동일 `deleted_at` 충돌에서도 deterministic).

### EC-6. 감사 테이블 복원 중, 같은 키가 이미 존재
- `review_map_code_unique` 충돌 → Artisan command가 충돌 키를 보고하고 ABORT. 수동 해결 가이드: 기존 활성 행이 의도적인지 확인 후 삭제 또는 복원 skip.

### EC-7. 감사 테이블 자체가 사고로 비워짐
- 복원 불가. 방지책: 감사 테이블 DROP/TRUNCATE 권한을 DB 레벨에서 제한 (별도 이슈)
- 장기적: S3로 일별 dump

### EC-8. 사용자 없이 시스템이 호출 (cron/artisan)
- `deleted_by`에 CLI 이름 기록 (`artisan:some-command`), `deleted_via='cli'`

### EC-9. `reason`에 엄청 긴 텍스트가 들어올 경우
- 컨트롤러 validation `max:500` + DB `VARCHAR(500)` → 초과 시 422

### EC-10. `FOR UPDATE` + REPEATABLE-READ + 다른 트랜잭션의 INSERT (phantom)
- 이론상 팬텀 가능. 단 다른 트랜잭션이 같은 (client_id, config_id) 에 새 row INSERT 중이면 두 트랜잭션 중 하나가 block. 실무상 드뭄. 필요 시 `SELECT ... LOCK IN SHARE MODE` 대신 `FOR UPDATE` 유지.

### EC-11. `request_id` 충돌 — **외부 헤더 입력 차단으로 원천 제거**
- 초기 설계에서는 컨트롤러가 `X-Request-Id` 헤더를 받아 Service 에 전달했으나, Sentry bot 2차 리뷰에서 이 경로가 치명적 버그를 일으킨다고 지적:
  - 외부 호출자가 동일 헤더를 재사용하면 `->where('request_id', $requestId)->count()` 가 과거 감사 행까지 함께 세어 `audit_count !== deletedCount` 불일치로 RuntimeException rollback → 삭제가 전혀 되지 않음.
- **수정**: 컨트롤러에서 `requestId: null` 만 전달. Service 가 항상 신규 `Str::uuid()` (UUID v4) 를 생성한다. 외부 헤더가 필요한 경우 감사 컬럼이 아닌 Laravel `request_id` 미들웨어 / Sentry trace_id 에 맡긴다.

### EC-12. 감사 테이블 크기 증가
- 1년 운영 기준 예상 몇 만 ~ 수십만 건. 인덱스 포함 수백 MB 수준. 당장 파티셔닝 불필요.
- 보관 정책: 1년 경과분은 S3로 dump 후 `DELETE FROM audit WHERE deleted_at < ?` — 별도 정리 스펙

### EC-13. 크로스 스키마 쿼리 권한
- Laravel `connection('retaku_admin')` 사용 시 운영 DB 계정이 해당 스키마에 `INSERT`/`SELECT` 권한 있는지 확인
- 감사 테이블 생성 마이그레이션 시점에 자동으로 같은 권한 승계됨 (동일 스키마 내)

### EC-14. 마이그레이션 silent skip 의 위험
- 과거 시안은 `try { Schema::hasTable() } catch (\Throwable) { return; }` 패턴이었으나, 이렇게 하면 권한/일시 장애/타입 비호환 같은 진짜 root cause 를 모두 warning 한 줄로 가리고 migrations 테이블에는 "수행됨" 으로 기록되어 다음 배포 때까지 감사 테이블이 없는 상태가 지속될 수 있다.
- 현재 구현은 `config('database.connections.retaku_admin')` 가 null 인 경우(=CI 처럼 연결 자체가 미설정)에만 안전하게 skip 하고, 그 외 실제 스키마 호출은 throw 를 허용한다.

### EC-15. ReviewCountManager 리셋 실패의 rollback 전염
- 캐시 리셋이 트랜잭션 안에서 실행되면 리셋 실패 시 감사/삭제까지 함께 rollback 된다 — 사고 복구용 감사 행마저 사라지는 문제. 현재는 의도적으로 트랜잭션 **밖** 에서 실행하고, 실패는 `Log::warning` 으로 swallow 한다.

### EC-16. 0건 결과 silent 통과
- `auditCount === deletedCount === 0` 이면 일치 검증 자체는 통과해 `success` 응답으로 보일 수 있다. 현재는 Service 가 `Log::warning` 으로 흔적을 남기고, 프런트가 별도 분기로 `snackbar.warning` 을 표시해 사용자에게 명시적으로 알린다.

### EC-17. 선택 모드 + driver_config_id 동시 전달
- ids 배열이 driver_config_id 가 가리키는 config 의 행이 아닐 경우, ownership 만 통과해도 Service 의 WHERE 에서 제외되어 0건 결과가 나오는 silent 실패가 가능하다. 컨트롤러는 ownership 검증에 `config_id` 까지 AND 로 결합해 미연에 422 로 차단한다.

### EC-18. 복원 `--request-id` 필터 + audit_id tiebreaker 스코프
- 동일 `orig_id` 에 다른 `request_id` 로 감사 행이 2건 쌓인 상황(삭제→복원→재삭제)에서, 사용자가 첫 번째 배치를 `--request-id` 로 복원하려 할 때 서브쿼리 `SELECT MAX(audit_id) WHERE orig_id = a.orig_id` 가 필터를 무시하면 두 번째(더 큰) 행이 선택되고 외부 where `a.request_id = 'A'` 와 충돌해 0건이 되어 **첫 배치가 전혀 복원되지 않는다**.
- **수정**: `RestoreTargetItemMapFromAudit` 의 서브쿼리(`a2`)에도 외부 where 와 동일한 필터(`client_id`, `config_id`, `deleted_at`, `request_id`)를 주입해 tiebreaker 가 필터 범위 안에서만 작동하도록 한다. 회귀 테스트: `test_restore_request_id_filter_respects_tiebreaker_scope`.

---

## 테스트 계획

### T-1. Feature test: `tests/Feature/Review/TargetItemMapDeleteBulkAuditTest.php`

전체 모드 / 선택 모드 / validation / 인증 / 정규화 / 감사 메타까지 13 케이스:

1. `test_destroy_bulk_requires_auth` — 미인증 401
2. `test_destroy_bulk_rejects_when_confirm_name_mismatch` — 422 + 변동 없음
3. `test_destroy_bulk_copies_to_audit_then_deletes` — 정상 5건 감사+삭제+메타 검증
4. `test_destroy_bulk_filters_by_driver_config` — config 필터 동작
5. `test_destroy_bulk_validates_payload` — confirm_name 누락 / reason 501자 / ids 빈 배열 / ids.* 음수 / ids 중복 (distinct) / ids 2001건 (max:2000)
6. `test_destroy_bulk_selected_deletes_only_specified_ids` — 5 중 2 선택 삭제 + 감사 `bulk_button_selected`
7. `test_destroy_bulk_selected_rejects_ids_from_other_client` — 다른 client ids 끼워넣기 422
8. `test_destroy_bulk_full_mode_zero_rows_succeeds_with_warning` — 빈 업체 0건 정상 통과 계약 고정
9. `test_destroy_bulk_normalizes_confirm_name` — trim / 전각 공백 정규화 검증
10. `test_destroy_bulk_selected_with_driver_config_filter` — ids+driver_config_id AND 결합 + 일관 불가 시 422
11. `test_destroy_bulk_selected_audit_meta_fields` — 선택 모드 감사 메타 (deleted_by, deleted_via, reason, request_id, client_id, config_id, deleted_at) 검증
12. `test_destroy_bulk_selected_requires_auth` — 선택 모드 401 경로 별도 고정
13. `test_destroy_bulk_selected_rejects_nonexistent_ids` — 존재하지 않는 id 가 섞이면 ownership 가드가 422 차단

### T-2. Feature test: `tests/Feature/Review/RestoreTargetItemMapFromAuditTest.php` (신규)

7 케이스로 복원 커맨드의 핵심 계약 고정:

1. `test_restore_inserts_with_original_id` — 원본 id 그대로 INSERT (3건 배치)
2. `test_restore_dry_run_inserts_nothing` — `--dry-run` 시 운영 변동 없음
3. `test_restore_aborts_when_primary_key_already_exists` — PK 충돌 ABORT, 운영 유지
4. `test_restore_aborts_on_unique_key_conflict` — UNIQUE `(client_id, config_id, target_item_code, client_item_code)` 충돌 ABORT
5. `test_restore_picks_largest_audit_id_per_orig_id` — 동일 deleted_at 충돌 시에도 audit_id tiebreaker 로 단일 행 (가장 최근) 선택
6. `test_restore_filters_by_request_id` — `--request-id` 필터 동작
7. `test_restore_requires_client_or_request_id` — 가드 절 동작

### T-3. Unit 테스트 (신규)

**`tests/Unit/Support/Review/ClientNameComparatorTest.php`** — 정규화 회귀 방지:
- 반각/NBSP/em space/전각 공백이 **양 끝** 에 있을 때 모두 동일 업체로 판정
- 내부 공백 차이 (`"A 사"` vs `"A사"`) 는 **서로 다른** 업체로 보존
- NFD ↔ NFC 일치 (intl 확장 없으면 skip)
- `null` 비교는 항상 `false` (우회 차단)

**`tests/Unit/Enums/Review/TargetItemMapDeleteViaTest.php`** — enum value freeze:
- 각 case 의 string value 가 운영 DB 에 기록된 값(`bulk_button`, `bulk_button_selected` 등) 과 일치
- 이 테스트가 실패하면 "변경 가능" 이 아니라 "DB 마이그레이션 필요" 신호

**`tests/Unit/Models/Review/TargetItemMapAuditGuardTest.php`** — append-only 가드:
- 모델 `save()` / `update()` / `delete()` 호출 시 `LogicException('append-only')` throw
- `$guarded=['*']` 로 mass assignment 자체가 차단되는지
- raw `DB::table()->insert()` 는 가드와 무관하게 정상 동작 (쓰기 경로 계약 고정)

### T-4. 프런트 단위 테스트 (후속 별도 작업)
- `confirmName` 빈 문자열/다른 문자열/공백 포함일 때 버튼 disabled (프런트 `clientNameEquals` 활용)
- `isDeletingAll=true`일 때 버튼 loading + 재클릭 차단
- 0건 응답 시 `snackbar.warning` 분기 호출
- 422 응답 시 서버 message 가 사용자 노출되는지 검증

---

## 마이그레이션/배포 순서

1. **[DB] 감사 테이블 생성 마이그레이션 실행** (`php artisan migrate`)
   - 기존 데이터 영향 없음
2. **[백엔드] 모델 + 서비스 + 컨트롤러 변경 배포**
   - 이 시점부터 모든 일괄 삭제가 감사 테이블에 기록됨
   - 이전 프런트는 `confirm_name` 을 전달하지 않음 → 422 반환, 삭제 불가
   - **필연적 다운타임 없음**. 기존 프런트는 삭제 버튼이 막히고 나머지는 정상 동작.
3. **[프런트] 다이얼로그 + API 호출 수정 배포** (GitHub Actions)
   - 배포 직후 새 UI로 작동
4. **[운영] 복원 Artisan 커맨드 배포 확인** — `php artisan list | grep target-item-map`
5. **[문서] 복원 SOP 를 팀 Wiki/이 docs/runbook에 추가** — 운영자가 이번 사고 스크립트 대신 이 커맨드를 쓰도록 유도
6. **[모니터링] 감사 테이블 건수 알림** — `deleted_at > 1시간 전` 인 감사 행이 100건 초과 시 Slack #ops 알림 (별도 cron or CloudWatch)

---

## 오픈 이슈

| # | 이슈 | 상태 |
|---|---|---|
| ~~O-1~~ | ~~복원 완료 플래그(`restored_at`)를 감사 테이블에 남길지~~ | **결정**: 남기지 않음. 감사 = 이벤트 로그(immutable) 원칙 우선. 복원 이력은 로그/요청 ID 로 추적. |
| O-2 | 감사 테이블 장기 보존/S3 dump 정책 | 별도 스펙 (현재 범위 외) |
| ~~O-3~~ | ~~단일 삭제 경로(`destroy`)도 감사할지~~ | **결정**: 이번 범위에서 제외. 사후 추적 가능성을 위해 `Log::info` 한 줄만 추가 (`TargetItemMapController::destroy`). |
| O-4 | `review_client_items`, `review_targets` 형제 테이블도 동일 패턴으로 확장할지 | 본 스펙 배포 후 재검토 |
| O-5 | 권한 분리 (매핑 삭제 버튼 롤 제한) | 별도 이슈 (RBAC 개편과 연계) |
| O-6 | 프런트 다이얼로그 단위 테스트 (T-3) | 후속 PR — 본 스펙은 백엔드/통합 테스트로 우선 보호 |

---

## 참고 링크

- 2026-04-08 바닐라코 매핑 복원 작업 메모리: `banila-mapping-restore-2026-04-08.md`
- 매핑 삭제 드롭다운: `SeoulVenturesGroupware/frontend/resources/ts/pages/review/data/index.vue` 의 "매핑 정보 삭제" VMenu (데이터 작업 그룹의 끝)
- 서비스: `SeoulVenturesGroupware/app/Services/Review/TargetItemMapService.php::deleteBulk`
- 복원 커맨드: `SeoulVenturesGroupware/app/Console/Commands/RestoreTargetItemMapFromAudit.php`
- 유사 bulk 액션 경험칙: PR#519 (sv-nova-master)

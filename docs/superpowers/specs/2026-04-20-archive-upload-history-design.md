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
- **Chunked·멱등**: 매 호출은 독립적으로 500 건을 archive+delete. 세션 단절·사용자 취소·네트워크 실패 후 재실행해도 남은 레코드만 이어서 처리.
- **Archive 는 이동이지 이력 테이블 아님**: 복원이 필요하면 운영자가 `review_upload_target_list_archive` 에서 `review_upload_target_list` 로 수동 이전. 자동 복원 UI 는 본 스펙 밖.

## API

### 엔드포인트

```
POST /api/review/clients/{client}/upload-history/archive
```

- 매핑 독립 (클라이언트 단위 라우트)
- 기존 `Route::prefix('review')->middleware('auth')->group(...)` 내부

### Request

```json
{
  "config_id": 42,
  "target_item_code": "4995740052",
  "client_item_code": "189",
  "confirm_text": "위험성을 알고 동의합니다"
}
```

### 검증

- `config_id`: `integer|min:1`, `DriverConfig::find($config_id)->client_id === client->id` (cross-client 공격 방어)
- `target_item_code`: `string|min:1`
- `client_item_code`: `string|min:1`
- `confirm_text`: trim + NFC 정규화 후 `위험성을 알고 동의합니다` 정확 일치 (`ClientNameComparator` 스타일)
- `driver_code`: 서버가 `DriverConfig` 에서 도출 (클라이언트 입력 불허)
- `target_database_hive`: 서버가 `Client` 에서 도출 (클라이언트 입력 불허)

### Response

```json
{
  "success": true,
  "archived_count": 500,
  "remaining_count": 2067,
  "has_more": true,
  "batch_id": "550e8400-e29b-41d4-a716-446655440000"
}
```

- `archived_count`: **이번 호출** 에서 이동한 건수
- `remaining_count`: 이번 호출 후 조건에 매칭되는 잔여 건수 (`countDocuments` 로 경량 확인)
- `has_more`: `remaining_count > 0`
- `batch_id`: 이번 호출 단위 UUID v4 (archive 도큐먼트에 기록되어 "몇 번의 세션에 걸쳐 이동되었는지" 추적 가능)

### 예외

- 토큰 불일치: 422 `{"message": "확인 문구가 일치하지 않습니다."}`
- `config_id` 가 client 소속이 아님: 422 `{"message": "드라이버 설정이 해당 클라이언트에 속하지 않습니다."}`
- `target_database_hive` / `driver_code` 결손: 422 `{"message": "클라이언트 또는 드라이버 설정이 불완전합니다."}`
- MongoDB 연결 실패: 500 (Handler 가 Sentry 전파)
- insert 성공 후 delete 실패: 500 + `Log::error`. archive 에 중복 레코드 허용 (유니크 인덱스 없음). 재호출 시 안전하게 이어짐.

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

```php
const CHUNK_SIZE = 500;

// MongoDBConnection 서비스 재사용 (app/Services/MongoDB/MongoDBConnection.php)
// CLAUDE.md: getClient() 사용 (deprecated getMongoClient() 대신), table() 사용 (deprecated collection() 대신)
$conn = DB::connection('mongodb');
$db = $conn->getClient()->selectDatabase($client->target_database_hive);
$coll = $db->selectCollection('review_upload_target_list');
$archiveColl = $db->selectCollection('review_upload_target_list_archive');

$docs = $coll->find($filter, ['limit' => self::CHUNK_SIZE])->toArray();
if (empty($docs)) {
    return [
        'archived_count' => 0,
        'remaining_count' => 0,
        'has_more' => false,
        'batch_id' => $batchId,
    ];
}

$archivedAt = new UTCDateTime();
$archivedBy = Auth::user()->email ?? 'unknown';
$mappingId = TargetItemMap::query()
    ->where('client_id', $client->id)
    ->where('config_id', $configId)
    ->where('target_item_code', $targetItemCode)
    ->where('client_item_code', $clientItemCode)
    ->value('id'); // nullable — 삭제된 매핑이면 null

$originalIds = [];
foreach ($docs as &$doc) {
    $originalIds[] = $doc['_id'];
    $doc['original_id']         = $doc['_id'];
    $doc['_id']                 = new ObjectId;
    $doc['archived_at']         = $archivedAt;
    $doc['archived_by']         = $archivedBy;
    $doc['archived_mapping_id'] = $mappingId;
    $doc['archive_batch_id']    = $batchId;
}
unset($doc);

$archiveColl->insertMany($docs);
$coll->deleteMany(['_id' => ['$in' => $originalIds]]);

$remainingCount = $coll->countDocuments($filter);

return [
    'archived_count' => count($docs),
    'remaining_count' => $remainingCount,
    'has_more' => $remainingCount > 0,
    'batch_id' => $batchId,
];
```

### 아카이브 도큐먼트 스키마

원본 필드 전부 + 다음 메타:

| 필드 | 타입 | 설명 |
|------|------|------|
| `_id` | ObjectId | 신규 발급 (원본 `_id` 와 별개) |
| `original_id` | ObjectId | 원본 `review_upload_target_list._id` |
| `archived_at` | UTCDateTime | 이동 시점 |
| `archived_by` | string | 실행자 email |
| `archived_mapping_id` | int \| null | 실행 시점의 `TargetItemMap.id` (삭제된 매핑이면 null) |
| `archive_batch_id` | string (UUID v4) | 이번 호출 배치 ID |

유니크 인덱스 없음 — 같은 매핑의 이관 이력을 여러 번 삭제할 수 있으며, 각 배치가 독립적인 레코드로 남는다. Mongo 인덱스는 운영 중 필요 시 추가 가능 (예: `archived_at`, `archive_batch_id`) — 본 스펙에선 생성하지 않음.

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

```ts
const cancelled = ref(false)

async function executeArchive(selected: TargetItemMap[]) {
  const results: ArchiveResult[] = []

  for (const [idx, m] of selected.entries()) {
    if (cancelled.value) break

    updateProgress({ currentMappingIndex: idx, mapping: m })

    let processed = 0
    let total: number | null = null

    while (!cancelled.value) {
      const res = await archiveUploadHistory(m.client_id, {
        config_id: m.config_id,
        target_item_code: m.target_item_code,
        client_item_code: m.client_item_code,
        confirm_text: '위험성을 알고 동의합니다',
      })

      if (!res.success) {
        results.push({ mapping: m, error: res.message })
        break
      }

      if (total === null) total = res.archived_count + res.remaining_count
      processed += res.archived_count
      updateProgress({ processed, total })

      if (!res.has_more) {
        results.push({ mapping: m, archived: processed })
        break
      }

      await sleep(300)
    }
  }

  showSummary(results, cancelled.value)
}
```

## 감사 로그

매 API 호출마다:

```php
Log::info('[target-item-map] archive upload history', [
    'client_id' => $client->id,
    'config_id' => $configId,
    'driver_code' => $driverCode,
    'target_item_code' => $targetItemCode,
    'client_item_code' => $clientItemCode,
    'target_database_hive' => $client->target_database_hive,
    'archived_count' => count($docs),
    'remaining_count' => $remainingCount,
    'archived_mapping_id' => $mappingId,
    'archive_batch_id' => $batchId,
    'archived_by' => $archivedBy,
]);
```

MongoDB archive 레코드 자체가 1차 감사 소스 (원본 + 메타 보존). 애플리케이션 로그는 보조.

## 구현 파일

### SVGW (`SeoulVenturesGroupware`)

- `app/Http/Controllers/Review/UploadHistoryController.php` (신규)
  - `archive(Client $client, Request $request)` 메서드
  - 또는 기존 `TargetItemMapActionController` 에 추가 — 전자 추천 (매핑 독립 의미 반영)
- `app/Services/Review/UploadHistoryArchiveService.php` (신규, 테스트 용이성)
  - `archiveChunk(Client $client, int $configId, string $targetItemCode, string $clientItemCode, string $archivedBy, int $chunkSize = 500): ArchiveResult`
- `app/Support/Review/ConfirmTextComparator.php` (신규, 재사용 가능한 토큰 비교기) 또는 기존 `ClientNameComparator` 재활용
- `routes/api.php` — 라우트 1개 추가
- `frontend/resources/ts/api/entities/review/uploadHistory.ts` (신규)
  - `archiveUploadHistory(clientId, payload)` 함수
- `frontend/resources/ts/pages/review/data/index.vue` — toolbar 버튼 + 2단계 다이얼로그 + 실행 루프 추가
- `frontend/resources/ts/components/review/ArchiveUploadHistoryDialog.vue` (신규, 관심사 분리)
  - 확인 다이얼로그 (대상 테이블 + 토큰 입력)
  - 진행 다이얼로그 (프로그레스 + 취소)

### 테스트

- `tests/Feature/Review/ArchiveUploadHistoryTest.php`
  - 정상 흐름 (단일 chunk, 멀티 chunk)
  - 토큰 불일치 → 422
  - cross-client config_id → 422
  - 매핑이 삭제된 상태 (mapping_id null) 에서도 archive 동작
  - 0건 요청 (has_more=false, archived_count=0) 멱등
  - insert 성공 후 delete 실패 시뮬레이션 (archive 중복 허용)
- `tests/Unit/Services/Review/UploadHistoryArchiveServiceTest.php`
  - chunk size 경계 (정확히 500, 501, 1000)
  - 아카이브 도큐먼트 메타 필드 검증

## 엣지 케이스

### E1. 동일 매핑을 두 운영자가 동시에 실행
- 두 호출이 겹치면 MongoDB `find limit 500` 이 겹치는 문서를 읽을 수 있음
- `insertMany` 는 새 `_id` 로 복사 → archive 에 중복 도큐먼트 생성 (유니크 인덱스 없어 허용됨)
- `deleteMany` 는 `_id $in` 이라 중복 삭제 시도해도 영향 없음 (이미 삭제됨)
- 결과: archive 에 동일 원본을 가리키는 중복 도큐먼트가 최대 N-1 개 남음. 드문 케이스라 무시.

### E2. 중간에 새 이관 레코드가 insert 됨
- 업로드 워커가 계속 돌면서 `review_upload_target_list` 에 새 레코드를 만듦
- 프론트가 첫 호출 응답의 `total` 을 기반으로 진행률을 계산했으므로, 실제 처리량이 total 을 초과할 수 있음
- 수용: 진행 바가 100% 를 살짝 넘거나 새로 증가. 사용자 혼란 최소화를 위해 progress clamp (`Math.min(processed, total)`) 적용, 필요 시 안내 문구 추가 여부는 구현 단계 판단.

### E3. target_database_hive 가 `null` 또는 공백
- 검증에서 422 로 반환 (`클라이언트 설정이 불완전합니다`)
- MongoDB 선택 직전 double-check

### E4. 클라이언트는 있지만 MongoDB DB 자체가 존재하지 않음
- MongoDB 는 존재하지 않는 DB/컬렉션을 쿼리해도 에러가 아닌 빈 결과 반환
- `archived_count=0, has_more=false` 응답. 멱등 성공 처리.

### E5. 매우 큰 이관 이력 (예: 10만건)
- 10만 / 500 = 200 회 호출 × 300ms delay = 약 1분 + API 처리 시간
- 사용자 UI 대기 시간 수분 단위 가능. 다이얼로그에 경고 문구 (예: "양이 많으면 수 분 걸릴 수 있습니다") 표시.
- 도중 취소 가능. 이어서 재실행 가능.

### E6. HTTP 타임아웃
- chunk 500 + countDocuments 1회 = 수백 ms 예상. 일반 타임아웃 내.
- 느려지면 chunk size 를 200 등으로 조정 (상수 하나).

### E7. 매핑이 이미 삭제된 후 운영자가 동일 튜플로 정리
- 엔드포인트는 매핑 존재 여부 검증하지 않음
- `TargetItemMap` 레코드가 없으면 `archived_mapping_id = null` 로 기록
- UI 에선 기본 노출 안 됨 (선택지 목록에 없으니), 운영자가 API 직접 호출 시나리오.

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
- 현재 엔드포인트는 per-mapping (1건씩) 이므로 10 제한은 UX 가드 뿐
- 악의적 사용자 차단 목적이 아니라 실수 방지 목적 — 엔드포인트 자체에 rate limit 은 불필요
- 필요 시 Laravel `throttle` 미들웨어로 분당 호출 수 제한 고려 (본 스펙 밖)

## 배포 및 릴리즈

- SVGW 단독 변경 (Python 워커 영향 없음)
- MongoDB 컬렉션 `review_upload_target_list_archive` 는 첫 호출 시 암묵적으로 생성됨 — 사전 마이그레이션 불필요
- PR 1개 (백엔드 + 프론트엔드 + 테스트 묶음)
- 릴리즈 방식: 기존 SVGW 패턴 — PR 머지 → 자동 GitHub Actions 배포

## 완료 기준

- [ ] 엔드포인트 구현 + 검증 + 예외 처리
- [ ] 서비스 계층 단위 테스트 (chunk 경계, 메타 필드)
- [ ] Feature 테스트 6 케이스 (정상/토큰/cross-client/삭제된 매핑/0건 멱등/delete 실패)
- [ ] 프론트 확인 다이얼로그 + 진행 다이얼로그
- [ ] 취소 동작 검증 (수동 QA)
- [ ] 실제 curlyshyll 매핑 303315 로 스테이징 동작 확인 후 운영 배포
- [ ] 배포 후 운영자가 대기 중인 요청 처리

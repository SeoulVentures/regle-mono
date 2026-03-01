# Utility 파일 업로드 MCP 기능 설계

**작성일**: 2026-03-01
**대상 저장소**: `regle-mcp-server`, `SeoulVenturesGroupware`
**관련 URL**: https://groupware.seoulventures.net/utility

---

## 개요

두 가지 기능을 동시에 구현한다:

1. **MCP 도구**: `upload_utility_file` — S3에 파일을 업로드하고 공개 URL 반환
2. **Utility 페이지 개선**: 등록 날짜 컬럼 추가 + 전체 컬럼 정렬 기능

---

## 아키텍처

```
Claude/Agent
    │
    ├─ [upload_utility_file 도구]
    │       │ mode: base64 | url
    │       ▼
    │  regle-mcp-server (server.ts)
    │       │ POST /mcp/utility/upload
    │       ▼
    │  SeoulVenturesGroupware (Laravel)
    │       │ S3 업로드 → /img/YYYY/MM/[subdirectory/]파일명
    │       │ 반환: { success, name, url }
    │       ▼
    │  S3 → CDN (https://static.seoul.ventures/)
    │
    └─ [Utility 페이지 /utility]
            │ GET /api/utility (index)
            ▼
       UtilityController::index()
            │ AWS SDK ListObjectsV2 (Key + LastModified)
            │ 반환: { name, url, lastModified }
            ▼
       프론트엔드 VDataTable
            - 등록 날짜 컬럼 추가 (sortable)
            - 파일 이름 컬럼 정렬 가능
```

---

## 변경 범위

### A. regle-mcp-server

#### `src/server.ts`
- `upload_utility_file` 도구 추가

```typescript
server.registerTool('upload_utility_file', {
  title: 'S3 파일 업로드',
  description: [
    '파일을 S3에 업로드하고 공개 CDN URL을 반환합니다.',
    'mode=base64: base64 인코딩된 파일 내용을 전달합니다.',
    'mode=url: 외부 URL(Slack 등)에서 파일을 다운로드하여 업로드합니다.',
    '로컬 파일의 경우 Claude Code가 파일을 읽어 base64로 변환 후 mode=base64로 전달하세요.',
  ].join(' '),
  inputSchema: {
    mode: z.enum(['base64', 'url']).describe(
      'base64: 파일 내용을 base64로 전달 | url: 외부 URL에서 다운로드'
    ),
    base64Content: z.string().optional().describe('base64 인코딩된 파일 내용 (mode=base64 시 필수)'),
    filename: z.string().optional().describe('저장할 파일명, 확장자 포함 (mode=base64 시 필수)'),
    fileUrl: z.string().optional().describe('다운로드할 파일의 URL (mode=url 시 필수)'),
    subdirectory: z.string().optional().describe(
      '날짜 폴더 내 하위 경로. 출처 구분용. 예: slack, manual, claude'
    ),
  },
})
// 저장 경로: /img/{YYYY}/{MM}/[{subdirectory}/]{filename}
// 반환: { url, name, path }
```

#### `src/api/groupware.ts`
- `uploadUtilityFile(params)` 메서드 추가 (multipart/form-data 또는 JSON POST)

---

### B. SeoulVenturesGroupware

#### `routes/api.php`
MCP 라우트 그룹에 추가:
```php
Route::post('utility/upload', [UtilityController::class, 'mcpUpload']);
```

#### `app/Http/Controllers/UtilityController.php`

**`index()` 개선** — `allFiles()` 대신 AWS SDK `ListObjectsV2` 사용:
```php
public function index()
{
    $s3Client = Storage::disk('s3')->getClient();
    $bucket = config('filesystems.disks.s3.bucket');

    $result = $s3Client->listObjectsV2([
        'Bucket' => $bucket,
        'Prefix' => 'img/',
    ]);

    return collect($result['Contents'] ?? [])
        ->map(fn($obj) => [
            'name' => $obj['Key'],
            'url'  => Storage::disk('s3')->url($obj['Key']),
            'lastModified' => $obj['LastModified']->toIso8601String(),
        ])
        ->values();
}
```

**`mcpUpload()` 추가** — base64 또는 URL 방식으로 S3 업로드:
```php
public function mcpUpload(Request $request)
{
    $request->validate([
        'mode'         => 'required|in:base64,url',
        'base64Content'=> 'required_if:mode,base64|string',
        'filename'     => 'required_if:mode,base64|string',
        'fileUrl'      => 'required_if:mode,url|url',
        'subdirectory' => 'nullable|string|alpha_dash',
    ]);

    $subdir = $request->subdirectory
        ? '/' . $request->subdirectory
        : '';
    $prefix = 'img/' . now()->format('Y/m') . $subdir;

    if ($request->mode === 'base64') {
        $content  = base64_decode($request->base64Content);
        $filename = $request->filename;
        $path     = "$prefix/$filename";
        Storage::disk('s3')->put($path, $content, 'public');
    } else {
        // mode=url: 외부 URL 다운로드
        $content  = file_get_contents($request->fileUrl);
        $filename = basename(parse_url($request->fileUrl, PHP_URL_PATH));
        $path     = "$prefix/$filename";
        Storage::disk('s3')->put($path, $content, 'public');
    }

    return response()->json([
        'success' => true,
        'name'    => $path,
        'url'     => Storage::disk('s3')->url($path),
    ]);
}
```

---

### C. SeoulVenturesGroupware 프론트엔드

#### `frontend/resources/ts/pages/utility/index.vue`

**인터페이스 변경:**
```typescript
interface S3File {
  name: string
  url: string
  lastModified: string  // ISO8601 형식
  selected?: boolean
}
```

**헤더 변경:**
```typescript
const headers = [
  { title: '#',       key: 'index',        sortable: false, width: '60px' },
  { title: '파일 이름', key: 'name',        sortable: true },
  { title: '파일 URL', key: 'url',          sortable: false },
  { title: '등록 날짜', key: 'lastModified', sortable: true },  // 추가
  { title: '선택',    key: 'selected',      sortable: false, width: '80px' },
]
```

**날짜 포맷 헬퍼:**
```typescript
const formatDate = (iso: string) =>
  new Date(iso).toLocaleString('ko-KR', {
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit',
  })
```

**템플릿에 `등록 날짜` 슬롯 추가:**
```html
<template #item.lastModified="{ item }">
  {{ formatDate(item.lastModified) }}
</template>
```

---

## 엣지 케이스

| 케이스 | 처리 방법 |
|--------|-----------|
| base64 디코딩 실패 | `base64_decode()` 실패 시 422 반환 |
| 외부 URL 접근 불가 | `file_get_contents` 실패 시 502 반환 |
| 파일명 충돌 | 동일 경로에 덮어씌움 (S3 put은 upsert) |
| S3 ListObjectsV2 1000개 초과 | `NextContinuationToken`으로 페이지네이션 처리 |
| 파일명 특수문자/인코딩 | 기존 `decodeName()` 함수로 처리 |

---

## 구현 순서

1. **SeoulVenturesGroupware 백엔드**
   - `UtilityController::index()` 개선 (ListObjectsV2)
   - `UtilityController::mcpUpload()` 추가
   - `routes/api.php` MCP 라우트 추가

2. **SeoulVenturesGroupware 프론트엔드**
   - `utility/index.vue` 인터페이스 + 헤더 + 날짜 포맷 업데이트

3. **regle-mcp-server**
   - `groupware.ts` API 클라이언트 메서드 추가
   - `server.ts` MCP 도구 등록

4. **테스트 및 배포**

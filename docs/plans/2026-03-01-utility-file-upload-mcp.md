# Utility 파일 업로드 MCP 기능 구현 계획

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** S3 파일 업로드 MCP 도구 추가 + Utility 페이지에 등록 날짜/정렬 기능 추가

**Architecture:** Groupware API 경유 방식 — MCP 서버가 `POST /mcp/utility/upload`를 호출하고, Laravel이 S3에 업로드. Utility 페이지 목록 조회는 AWS SDK `ListObjectsV2`로 LastModified를 한 번에 조회.

**Tech Stack:** TypeScript (Bun), Laravel 12, AWS SDK v3 (via flysystem-aws-s3-v3), Vue 3 + Vuetify

---

## 작업 저장소 경로

- **MCP 서버**: `/opt/SeoulVentures/regle/regle-mcp-server/`
- **Groupware 백엔드**: `/opt/SeoulVentures/regle/SeoulVenturesGroupware/`
- **Groupware 프론트엔드**: `/opt/SeoulVentures/regle/SeoulVenturesGroupware/frontend/`

---

### Task 1: UtilityController::index() 개선 — LastModified 포함 조회

**Files:**
- Modify: `SeoulVenturesGroupware/app/Http/Controllers/UtilityController.php`

**배경:**
현재 `index()`는 `Storage::disk('s3')->allFiles('/img')`를 사용해 파일명만 반환한다.
AWS SDK의 `ListObjectsV2`를 직접 호출하면 `LastModified`를 N+1 없이 가져올 수 있다.
Laravel Flysystem S3 어댑터에서 `Storage::disk('s3')->getAdapter()->getClient()`로 S3Client에 접근 가능하다.

**Step 1: `index()` 메서드 수정**

`UtilityController::index()` 전체를 다음으로 교체한다:

```php
public function index()
{
    $disk   = Storage::disk('s3');
    $adapter = $disk->getAdapter();
    // FlysystemS3Adapter에서 S3Client 추출
    $s3Client = $adapter->getClient();
    $bucket   = config('filesystems.disks.s3.bucket');

    $objects = [];
    $args    = ['Bucket' => $bucket, 'Prefix' => 'img/'];

    do {
        $result  = $s3Client->listObjectsV2($args);
        $objects = array_merge($objects, $result['Contents'] ?? []);
        $args['ContinuationToken'] = $result['NextContinuationToken'] ?? null;
    } while ($result['IsTruncated'] ?? false);

    return collect($objects)
        ->filter(fn($obj) => $obj['Key'] !== 'img/')  // 폴더 자체 제외
        ->map(fn($obj) => [
            'name'         => $obj['Key'],
            'url'          => $disk->url($obj['Key']),
            'lastModified' => $obj['LastModified']->toIso8601String(),
        ])
        ->values();
}
```

**Step 2: import 확인**

파일 상단 use 블록에 `Storage` 이미 있음. `Utility` 모델 import는 사용하지 않으므로 제거해도 무방하나, 그대로 두어도 무관.

**Step 3: 커밋**

```bash
cd /opt/SeoulVentures/regle/SeoulVenturesGroupware
git add app/Http/Controllers/UtilityController.php
git commit -m "feat: utility index에 S3 ListObjectsV2로 lastModified 포함 조회"
```

---

### Task 2: UtilityController::mcpUpload() 추가 + MCP 라우트 등록

**Files:**
- Modify: `SeoulVenturesGroupware/app/Http/Controllers/UtilityController.php`
- Modify: `SeoulVenturesGroupware/routes/api.php`

**Step 1: `mcpUpload()` 메서드 추가**

`UtilityController` 클래스 내 `destroy()` 메서드 다음에 추가:

```php
/**
 * MCP 서버에서 호출하는 파일 업로드 엔드포인트.
 * mode=base64: base64 인코딩된 파일 내용을 전달.
 * mode=url: 외부 URL에서 파일을 다운로드 후 업로드.
 * 저장 경로: img/{Y}/{m}/[{subdirectory}/]{filename}
 */
public function mcpUpload(Request $request)
{
    $request->validate([
        'mode'          => 'required|in:base64,url',
        'base64Content' => 'required_if:mode,base64|string',
        'filename'      => 'required_if:mode,base64|string|max:255',
        'fileUrl'       => 'required_if:mode,url|url',
        'subdirectory'  => 'nullable|string|alpha_dash|max:64',
    ]);

    $subdir = $request->filled('subdirectory')
        ? '/' . $request->subdirectory
        : '';
    $prefix = 'img/' . now()->format('Y/m') . $subdir;

    if ($request->mode === 'base64') {
        $decoded = base64_decode($request->base64Content, strict: true);
        if ($decoded === false) {
            return response()->json([
                'success' => false,
                'message' => 'base64 디코딩에 실패했습니다.',
            ], 422);
        }
        $filename = $request->filename;
        $path     = "{$prefix}/{$filename}";
        Storage::disk('s3')->put($path, $decoded, 'public');
    } else {
        // mode=url
        $context = stream_context_create(['http' => ['timeout' => 30]]);
        $content = @file_get_contents($request->fileUrl, false, $context);
        if ($content === false) {
            return response()->json([
                'success' => false,
                'message' => '파일 URL에서 다운로드에 실패했습니다.',
            ], 502);
        }
        $filename = basename(parse_url($request->fileUrl, PHP_URL_PATH)) ?: 'file';
        $path     = "{$prefix}/{$filename}";
        Storage::disk('s3')->put($path, $content, 'public');
    }

    return response()->json([
        'success' => true,
        'name'    => $path,
        'url'     => Storage::disk('s3')->url($path),
    ]);
}
```

**Step 2: MCP 라우트 등록**

`routes/api.php`의 `mcp.auth` 미들웨어 그룹 (379번 줄) 내부 마지막에 추가:

```php
// === Utility (파일 업로드) ===
Route::post('utility/upload', [\App\Http\Controllers\UtilityController::class, 'mcpUpload']);
```

**Step 3: 수동 동작 확인 (선택)**

```bash
# 로컬 서버가 있다면 아래로 테스트 가능
curl -X POST http://localhost:8000/api/mcp/utility/upload \
  -H "Authorization: Bearer {MCP_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"mode":"base64","base64Content":"dGVzdA==","filename":"test.txt"}'
```

**Step 4: 커밋**

```bash
cd /opt/SeoulVentures/regle/SeoulVenturesGroupware
git add app/Http/Controllers/UtilityController.php routes/api.php
git commit -m "feat: MCP utility upload 엔드포인트 추가 (base64/url 방식)"
```

---

### Task 3: Groupware API 클라이언트에 업로드 메서드 추가

**Files:**
- Modify: `regle-mcp-server/src/api/groupware.ts`

**배경:**
`GroupwareApiClient`의 기존 `post()` 메서드는 JSON body를 사용한다.
파일 업로드는 JSON body로 base64 또는 url을 전달하므로 기존 `post()` 활용 가능.
단, MCP 도구 레이어에서 직접 `api.post()`를 사용해도 되지만, 타입 명확성을 위해 래퍼 메서드를 추가한다.

**Step 1: `uploadUtilityFile()` 메서드 추가**

`groupware.ts` 파일 마지막 `delete()` 메서드 다음에 추가:

```typescript
async uploadUtilityFile(params: {
  mode: 'base64' | 'url';
  base64Content?: string;
  filename?: string;
  fileUrl?: string;
  subdirectory?: string;
}): Promise<{ success: boolean; name: string; url: string }> {
  return this.post('/mcp/utility/upload', params);
}
```

**Step 2: 커밋**

```bash
cd /opt/SeoulVentures/regle/regle-mcp-server
git add src/api/groupware.ts
git commit -m "feat: groupware 클라이언트에 uploadUtilityFile 메서드 추가"
```

---

### Task 4: MCP 서버에 upload_utility_file 도구 등록

**Files:**
- Modify: `regle-mcp-server/src/server.ts`

**배경:**
`server.ts`는 `createMcpServer()` 함수 안에 모든 도구를 등록한다.
기존 도구 그룹들 마지막 (719번 줄 부근) 에 새 그룹을 추가한다.

**Step 1: 도구 등록 코드 추가**

`server.ts`의 마지막 `server.registerTool(...)` 블록 다음, `return server;` 바로 위에 추가:

```typescript
  // ============================================
  // Utility Tools (파일 업로드)
  // ============================================

  server.registerTool(
    'upload_utility_file',
    {
      title: 'S3 파일 업로드',
      description: [
        '파일을 S3에 업로드하고 공개 CDN URL을 반환합니다.',
        'mode=base64: base64로 인코딩된 파일 내용과 파일명을 전달합니다.',
        '  - 로컬 파일: Claude Code가 Read 도구로 파일을 읽고 btoa()로 변환 후 전달하세요.',
        'mode=url: Slack 등 외부 URL을 지정하면 서버가 다운로드 후 업로드합니다.',
        '저장 경로: /img/{연}/{월}/[{subdirectory}/]{파일명}',
        '반환 URL: https://static.seoul.ventures/{저장경로}',
      ].join('\n'),
      inputSchema: {
        mode: z.enum(['base64', 'url']).describe(
          'base64: 파일 내용을 base64로 전달 | url: 외부 URL에서 다운로드'
        ),
        base64Content: z.string().optional().describe(
          'base64 인코딩된 파일 내용 (mode=base64 시 필수)'
        ),
        filename: z.string().optional().describe(
          '저장할 파일명, 확장자 포함 (mode=base64 시 필수). 예: image.png'
        ),
        fileUrl: z.string().optional().describe(
          '다운로드할 파일의 URL (mode=url 시 필수). 예: https://files.slack.com/...'
        ),
        subdirectory: z.string().optional().describe(
          '날짜 폴더 내 하위 디렉토리. 출처 구분용. 예: slack, manual, claude'
        ),
      },
    },
    async ({ mode, base64Content, filename, fileUrl, subdirectory }) => {
      // 입력 유효성 검사
      if (mode === 'base64' && (!base64Content || !filename)) {
        return {
          content: [{
            type: 'text' as const,
            text: '오류: mode=base64 일 때 base64Content와 filename이 필요합니다.',
          }],
        };
      }
      if (mode === 'url' && !fileUrl) {
        return {
          content: [{
            type: 'text' as const,
            text: '오류: mode=url 일 때 fileUrl이 필요합니다.',
          }],
        };
      }

      const result = await api.uploadUtilityFile({
        mode,
        base64Content,
        filename,
        fileUrl,
        subdirectory,
      });

      if (!result.success) {
        return {
          content: [{
            type: 'text' as const,
            text: '파일 업로드에 실패했습니다.',
          }],
        };
      }

      return {
        content: [{
          type: 'text' as const,
          text: JSON.stringify({
            url: result.url,
            name: result.name,
            message: '파일이 성공적으로 업로드되었습니다.',
          }, null, 2),
        }],
      };
    }
  );
```

**Step 2: 타입 체크**

```bash
cd /opt/SeoulVentures/regle/regle-mcp-server
bun run typecheck
```

오류 없이 통과해야 한다.

**Step 3: 커밋**

```bash
git add src/server.ts
git commit -m "feat: upload_utility_file MCP 도구 추가 (base64/url 모드)"
```

---

### Task 5: Utility 페이지 프론트엔드 개선

**Files:**
- Modify: `SeoulVenturesGroupware/frontend/resources/ts/pages/utility/index.vue`

**배경:**
현재 `S3File` 인터페이스에 `lastModified` 없음. 헤더에 정렬 기능 없음.
`VDataTable`의 `headers`에 `sortable: true`를 추가하면 자동으로 정렬 가능.

**Step 1: 인터페이스 수정**

`index.vue` 파일에서 `S3File` 인터페이스를 찾아 수정:

```typescript
// 변경 전
interface S3File {
  name: string
  selected?: boolean
}

// 변경 후
interface S3File {
  name: string
  url: string
  lastModified: string  // ISO8601 형식 (서버에서 제공)
  selected?: boolean
}
```

**Step 2: 날짜 포맷 헬퍼 추가**

`urlStaticText` 상수 선언 다음에 추가:

```typescript
// 날짜 포맷 (ISO8601 → 한국 로케일)
const formatDate = (iso: string) =>
  new Date(iso).toLocaleString('ko-KR', {
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
  })
```

**Step 3: 헤더 수정**

```typescript
// 변경 전
const headers = [
  { title: '#', key: 'index', width: '60px' },
  { title: '파일 이름', key: 'name' },
  { title: '파일 URL', key: 'url' },
  { title: '선택', key: 'selected', width: '80px' },
]

// 변경 후
const headers = [
  { title: '#', key: 'index', sortable: false, width: '60px' },
  { title: '파일 이름', key: 'name', sortable: true },
  { title: '파일 URL', key: 'url', sortable: false },
  { title: '등록 날짜', key: 'lastModified', sortable: true, width: '180px' },
  { title: '선택', key: 'selected', sortable: false, width: '80px' },
]
```

**Step 4: 템플릿에 등록 날짜 슬롯 추가**

`index.vue` 템플릿에서 `#item.url` 슬롯 다음에 추가:

```html
<template #item.lastModified="{ item }">
  {{ formatDate(item.lastModified) }}
</template>
```

**Step 5: 커밋**

```bash
cd /opt/SeoulVentures/regle/SeoulVenturesGroupware
git add frontend/resources/ts/pages/utility/index.vue
git commit -m "feat: utility 페이지에 등록 날짜 컬럼 + 정렬 기능 추가"
```

---

### Task 6: 서브모듈 업데이트 및 최종 커밋

**Step 1: SeoulVenturesGroupware 서브모듈 커밋 확인**

```bash
cd /opt/SeoulVentures/regle
git status
# SeoulVenturesGroupware, regle-mcp-server가 변경됨으로 표시되어야 함
```

**Step 2: 서브모듈 업데이트**

```bash
cd /opt/SeoulVentures/regle
git add SeoulVenturesGroupware regle-mcp-server
git commit -m "chore: utility 파일 업로드 MCP 기능 서브모듈 업데이트"
```

---

## 검증 체크리스트

- [ ] `UtilityController::index()` 응답에 `lastModified` 필드 포함
- [ ] `POST /mcp/utility/upload` (mode=base64)로 파일 업로드 성공
- [ ] `POST /mcp/utility/upload` (mode=url)로 외부 URL 다운로드 업로드 성공
- [ ] 저장 경로가 `/img/YYYY/MM/filename` 형식인지 확인
- [ ] MCP 도구 `upload_utility_file` 등록 및 타입 체크 통과
- [ ] Utility 페이지에 `등록 날짜` 컬럼 표시
- [ ] 파일 이름, 등록 날짜 컬럼 클릭 시 정렬 동작

## 엣지 케이스 처리 확인

- [ ] base64 잘못된 값 → 422 응답
- [ ] fileUrl 접근 불가 → 502 응답
- [ ] S3 객체 1000개 초과 → 페이지네이션(ContinuationToken) 동작
- [ ] 폴더 키 (`img/`) 필터링되어 목록에 미포함

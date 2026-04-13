# Target 액션을 매핑 관리 페이지로 이동 — 구현 계획

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 매핑 입력 페이지의 Target 액션 3개(상품명 초기화, 직진배송 삭제, 유사도 계산)를 매핑 관리 페이지의 row action으로 이동

**Architecture:** 백엔드 API에 `target_id`를 추가하고, 프론트엔드에서 매핑 테이블의 행 메뉴에 3개 액션을 추가. 기존 매핑 입력 페이지에서 해당 섹션 제거.

**Tech Stack:** Laravel (PHP), Vue 3, Vuetify 3, TypeScript

---

### Task 1: 백엔드 — API 응답에 target_id 추가

**Files:**
- Modify: `SeoulVenturesGroupware/app/Services/Review/TargetItemMapService.php:57-72` (select 목록)

**Step 1: target_id를 select에 추가**

`buildBaseQuery` 메서드의 select 배열에 `'rt.id as target_id'`를 추가:

```php
// 기존 select 배열 마지막에 추가
'rt.id as target_id',
```

`'rt.url as target_item_url'` 다음 줄에 추가하면 됨.

**Step 2: 커밋**

```bash
git add SeoulVenturesGroupware/app/Services/Review/TargetItemMapService.php
git commit -m "feat: TargetItemMap API 응답에 target_id 추가"
```

---

### Task 2: 프론트엔드 — 매핑 관리 페이지에 Target 액션 추가

**Files:**
- Modify: `SeoulVenturesGroupware/frontend/resources/ts/pages/review/data/index.vue`

**Step 1: TargetItemMap 인터페이스에 target_id 추가**

`pages/review/data/index.vue`의 `TargetItemMap` 인터페이스(39~57줄)에 추가:

```typescript
interface TargetItemMap {
  id: number
  config_id: number
  client_id: number
  target_id: number | null  // 추가
  driver_name: string
  // ... 나머지 동일
}
```

**Step 2: targetActionsApi와 targetItemMapActionsApi import 추가**

기존 import 영역에 추가:

```typescript
import { targetActionsApi } from '@/api/entities/review/targetActions'
import { targetItemMapActionsApi } from '@/api/entities/review/targetItemMapActions'
```

**Step 3: 액션 로딩 상태 추가**

```typescript
const targetActionLoading = ref<string | null>(null)
```

**Step 4: 3개 액션 함수 추가**

```typescript
// 상품명 초기화
const clearItemTitle = (mapping: TargetItemMap) => {
  if (!mapping.target_id) return

  showConfirm(`Target ${mapping.target_id}의 상품명을 초기화하시겠습니까?`, async () => {
    targetActionLoading.value = 'clearItemTitle'
    try {
      const { success } = await targetActionsApi.clearItemTitle(mapping.target_id!)
      if (success) {
        snackbar.success('상품명이 초기화되었습니다.')
        await loadMappings()
      }
    }
    catch (error) {
      handleError(error, { notificationMessage: '상품명 초기화에 실패했습니다.' })
    }
    finally {
      targetActionLoading.value = null
    }
  })
}

// 직진배송 삭제
const deleteZzExpress = (mapping: TargetItemMap) => {
  if (!mapping.target_id) return

  showConfirm(`Target ${mapping.target_id}의 직진배송 상품을 삭제하시겠습니까? 이 작업은 되돌릴 수 없습니다.`, async () => {
    targetActionLoading.value = 'deleteZzExpress'
    try {
      const { success } = await targetActionsApi.deleteZzExpress(mapping.target_id!)
      if (success) {
        snackbar.success('직진배송 상품이 삭제되었습니다.')
        await loadMappings()
      }
    }
    catch (error) {
      handleError(error, { notificationMessage: '직진배송 삭제에 실패했습니다.' })
    }
    finally {
      targetActionLoading.value = null
    }
  })
}

// 유사도 계산 (단일)
const generateSimilarityForMapping = (mapping: TargetItemMap) => {
  showConfirm(`매핑 ${mapping.id}의 유사도를 계산하시겠습니까?`, async () => {
    targetActionLoading.value = 'generateSimilarity'
    try {
      const { success } = await targetItemMapActionsApi.generateSimilarity(mapping.id)
      if (success)
        snackbar.success('유사도 계산이 요청되었습니다.')
    }
    catch (error) {
      handleError(error, { notificationMessage: '유사도 계산 요청에 실패했습니다.' })
    }
    finally {
      targetActionLoading.value = null
    }
  })
}
```

**Step 5: row action 메뉴(template)에 3개 액션 추가**

`#item.actions` 템플릿의 VList에서, "리뷰 수집" 항목과 "수정" 항목 사이(VDivider 앞)에 추가:

```html
<VDivider />
<VListItem
  :disabled="!item.target_id"
  @click="clearItemTitle(item)"
>
  <template #prepend>
    <VIcon
      icon="tabler-eraser"
      size="16"
    />
  </template>
  상품명 초기화
</VListItem>
<VListItem
  :disabled="!item.target_id"
  @click="deleteZzExpress(item)"
>
  <template #prepend>
    <VIcon
      icon="tabler-truck-off"
      size="16"
    />
  </template>
  직진배송 삭제
</VListItem>
<VListItem @click="generateSimilarityForMapping(item)">
  <template #prepend>
    <VIcon
      icon="tabler-percentage"
      size="16"
    />
  </template>
  유사도 계산
</VListItem>
```

**Step 6: 커밋**

```bash
git add SeoulVenturesGroupware/frontend/resources/ts/pages/review/data/index.vue
git commit -m "feat: 매핑 관리 페이지에 Target 액션 추가 (상품명 초기화, 직진배송 삭제, 유사도 계산)"
```

---

### Task 3: 매핑 입력 페이지에서 Target 액션 섹션 제거

**Files:**
- Modify: `SeoulVenturesGroupware/frontend/resources/ts/pages/review/mapping-manager/index.vue`

**Step 1: import 제거**

8~9줄의 import 제거:
```typescript
// 삭제:
import { targetActionsApi } from '@/api/entities/review/targetActions'
import { targetItemMapActionsApi } from '@/api/entities/review/targetItemMapActions'
```

**Step 2: script에서 Target 액션 관련 코드 제거**

386~483줄 전체 삭제 (주석 `// ===== Target 액션 =====`부터 `generateSimilarity` 함수 끝까지)

**Step 3: template에서 Target 액션 카드 제거**

771~893줄 (`<!-- Target 액션 카드 -->` VCol 블록 전체) 삭제

**Step 4: 직진배송 삭제 확인 다이얼로그 제거**

931~960줄 (`<!-- 직진배송 삭제 확인 다이얼로그 -->` VDialog 블록 전체) 삭제

**Step 5: 커밋**

```bash
git add SeoulVenturesGroupware/frontend/resources/ts/pages/review/mapping-manager/index.vue
git commit -m "refactor: 매핑 입력 페이지에서 Target 액션 섹션 제거 (매핑 관리로 이동)"
```

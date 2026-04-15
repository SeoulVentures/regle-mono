# review/data 자사몰 상품명 초기화·강제수집 버튼 — 구현 플랜

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** SVGW `/review/data` 페이지에 자사몰 상품명 **초기화**·**강제 수집** 버튼 2개 (선택/전체 모드) 를 추가하여 `is_name_checked=1` 로 고착된 placeholder 상품명을 운영자가 복구할 수 있게 한다.

**Architecture:** regle 쪽은 기존 `scan_client_items` 에 `flag_force` 파라미터만 추가 (채널용 `scan_target_titles_by_review_target_item_maps(flag_force=True)` 의 대칭). SVGW 쪽은 기존 `ReviewScanController` 에 `resetClientItemNames` 액션 추가 + `scanClientItems` 에 `force` 쿼리 수용. dispatch 는 기존 `RegleEcsService` (ECS RunTask) 재사용.

**Tech Stack:**
- regle: Python 3.12, SQLModel, Typer, pytest
- SVGW: Laravel 10, Vue 3 + TypeScript + Vuetify 3, Bun, PHPUnit
- dispatch: AWS ECS Fargate (기존 `regle-worker-cli-production` 태스크 정의)

**Spec:** `docs/superpowers/specs/2026-04-15-review-data-item-name-buttons-design.md`

---

## 전체 순서

**Phase A (regle)**: Task 1~5 — `flag_force` 파라미터 추가 + CLI + pytest + PR
**Phase Gate**: regle PR 머지 + ECS 이미지 배포 확인
**Phase B (SVGW)**: Task 6~13 — 초기화 API + 강제 수집 force + 프론트 버튼 + PR

regle 은 하위 호환 (default False) 이므로 SVGW 가 regle 보다 먼저 올라가면 SVGW 에서 force 요청해도 regle 구버전이 무시하고 기존 동작. 동작은 하지만 "강제" 가 되지 않으므로 운영상 regle 이 먼저 올라가야 함.

---

## File Structure

### regle (review-moai-refactoring 서브모듈)
- Modify: `app/drivers/BaseUploadDriver.py:473-540` — `scan_client_items` 시그니처 + 스킵 가드
- Modify: `regle/services/review/client_service.py:75-80` — `flag_force` 전달
- Modify: `regle/typer_cli/task_cli.py:55-63` — `--force` CLI 옵션
- Create: `tests/unit/drivers/test_base_upload_scan_force.py` — pytest

### SVGW (SeoulVenturesGroupware 서브모듈)
- Modify: `app/Http/Controllers/ReviewUploader/ReviewScanController.php` — `force` 파라미터 수용 + `resetClientItemNames` 메서드 신규
- Modify: `app/Services/RegleEcsService.php:295-302` — `scanClientItems` 에 `force` 인자
- Modify: `routes/api.php:402` 부근 — reset 엔드포인트 추가
- Create: `tests/Feature/Review/ResetClientItemNamesTest.php`
- Create: `tests/Feature/Review/ForceScanClientItemsTest.php`
- Modify: `frontend/resources/ts/api/entities/review/clientItems.ts` — `resolveProductNames` 에 `force` 옵션 + `resetProductNames` 메서드 신규
- Modify: `frontend/resources/ts/pages/review/data/index.vue:539-617 부근` — 버튼 2개 + 핸들러 4개 (선택·전체 × 초기화·강제)

---

# Phase A — regle 변경

## Task 1: `BaseUploadDriver.scan_client_items` 에 `flag_force` 파라미터 추가

**Files:**
- Modify: `review-moai-refactoring/app/drivers/BaseUploadDriver.py:473-504`
- Test: `review-moai-refactoring/tests/unit/drivers/test_base_upload_scan_force.py` (create)

현재 `scan_client_items(target_item_maps: str = None)` 의 스킵 가드:
```python
flag_try = True
if review_client_item.item_name is not None:
    if review_client_item.item_name.strip() != "":
        flag_try = False
        if "403" in review_client_item.item_name and "Forbidden" in review_client_item.item_name:
            flag_try = True
if review_client_item.item_url is None:
    flag_try = True
if review_client_item.is_name_checked is not True:
    flag_try = True

if not flag_try:
    continue
```

→ `flag_force=True` 일 때는 위 가드 전체를 우회하고 무조건 수집 시도.

- [ ] **Step 1: regle 브랜치 생성**

Run:
```bash
cd /opt/SeoulVentures/regle/review-moai-refactoring
git checkout -b feature/scan-client-items-force
```

- [ ] **Step 2: 실패하는 pytest 작성** — 새 파일 `tests/unit/drivers/test_base_upload_scan_force.py`

```python
"""scan_client_items 의 flag_force 동작 검증."""
from unittest.mock import MagicMock, patch

import pytest

from app.drivers.BaseUploadDriver import BaseUploadDriver


def _make_driver_with_item(*, item_name: str, is_name_checked: bool, item_url: str = "https://example.com/p/1"):
    client = MagicMock()
    client.product_url_pattern = "https://example.com/p/{product_id}"
    client.product_scan_type = "head"
    client.review_service = "crema"

    item = MagicMock()
    item.item_name = item_name
    item.is_name_checked = is_name_checked
    item.item_url = item_url
    item.item_code = "1"

    map_row = MagicMock()
    map_row.get_review_client_item.return_value = item
    client.get_review_target_item_maps.return_value = [map_row]

    driver = BaseUploadDriver.__new__(BaseUploadDriver)
    driver._review_client = client
    driver._BaseUploadDriver__validate_and_fix_items = MagicMock()  # private method no-op
    return driver, item


def test_scan_skips_when_name_checked_and_default_mode():
    """default (flag_force=False) 는 is_name_checked=True + 정상 name 이면 스킵."""
    driver, item = _make_driver_with_item(item_name="바닐라코 상품", is_name_checked=True)
    with patch("app.drivers.BaseUploadDriver.get_redis_conn") as redis_mock, \
         patch("app.drivers.BaseUploadDriver.requests.get") as req_mock:
        redis_mock.return_value.__enter__.return_value.exists.return_value = True
        redis_mock.return_value.__enter__.return_value.get.return_value = b"1"
        driver.scan_client_items()
    req_mock.assert_not_called()  # 스킵되어야 함


def test_scan_forces_recollect_when_flag_force_true():
    """flag_force=True 는 is_name_checked=True + 정상 name 이어도 수집 시도."""
    driver, item = _make_driver_with_item(item_name="바닐라코 상품", is_name_checked=True)
    with patch("app.drivers.BaseUploadDriver.get_redis_conn") as redis_mock, \
         patch("app.drivers.BaseUploadDriver.requests.get") as req_mock:
        redis_mock.return_value.__enter__.return_value.exists.return_value = True
        redis_mock.return_value.__enter__.return_value.get.return_value = b"1"
        req_mock.return_value.status_code = 200
        req_mock.return_value.encoding = "utf-8"
        req_mock.return_value.apparent_encoding = "utf-8"
        req_mock.return_value.content = b"<html><head><title>새 상품명</title></head></html>"
        driver.scan_client_items(flag_force=True)
    req_mock.assert_called_once()  # 강제 수집되어야 함
```

- [ ] **Step 3: 테스트 실행 — 실패 확인**

Run:
```bash
cd /opt/SeoulVentures/regle/review-moai-refactoring
.venv/bin/pytest tests/unit/drivers/test_base_upload_scan_force.py -v
```
Expected: `TypeError: scan_client_items() got an unexpected keyword argument 'flag_force'` (test_scan_forces_recollect_when_flag_force_true 실패)

- [ ] **Step 4: `BaseUploadDriver.scan_client_items` 수정**

Edit `app/drivers/BaseUploadDriver.py:473`. 시그니처 변경:

```python
# BEFORE (line 473)
def scan_client_items(self, target_item_maps: str = None):

# AFTER
def scan_client_items(self, target_item_maps: str = None, flag_force: bool = False):
```

그리고 스킵 가드 직후 (기존 `if not flag_try: continue` 의 바로 위, 약 line 503 부근) 에 추가:

```python
                if flag_force:
                    flag_try = True
                if not flag_try:
                    continue
```

최종적인 스킵 블록:
```python
                flag_try = True
                if review_client_item.item_name is not None:
                    if review_client_item.item_name.strip() != "":
                        flag_try = False
                        if "403" in review_client_item.item_name and "Forbidden" in review_client_item.item_name:
                            flag_try = True
                if review_client_item.item_url is None:
                    flag_try = True
                if review_client_item.is_name_checked is not True:
                    flag_try = True
                if flag_force:
                    flag_try = True

                if not flag_try:
                    continue
```

- [ ] **Step 5: 테스트 실행 — 통과 확인**

Run:
```bash
cd /opt/SeoulVentures/regle/review-moai-refactoring
.venv/bin/pytest tests/unit/drivers/test_base_upload_scan_force.py -v
```
Expected: 2 passed

- [ ] **Step 6: ruff lint + format**

Run:
```bash
.venv/bin/ruff check app/drivers/BaseUploadDriver.py tests/unit/drivers/test_base_upload_scan_force.py --fix
.venv/bin/ruff format app/drivers/BaseUploadDriver.py tests/unit/drivers/test_base_upload_scan_force.py
```

- [ ] **Step 7: 커밋**

```bash
git add app/drivers/BaseUploadDriver.py tests/unit/drivers/test_base_upload_scan_force.py
git commit -m "feat(scan): scan_client_items 에 flag_force 파라미터 추가

채널용 scan_target_titles_by_review_target_item_maps 와 대칭을 맞춰
자사몰 상품명 수집에서도 is_name_checked=True 상품을 강제로 덮어쓸 수
있게 한다. default False 로 기존 호출부 동작은 불변."
```

---

## Task 2: `ClientService.scan_client_items` 에 `flag_force` 전달

**Files:**
- Modify: `review-moai-refactoring/regle/services/review/client_service.py:75-80`

현재:
```python
@ToSlackClient("<@{user}> {client_name}의 자사몰 상품명 수집")
def scan_client_items(self, maps=None):
    upload_driver = self.client.get_upload_drvier()
    if not upload_driver:
        upload_driver = BaseUploadDriver(self.client)
    upload_driver.scan_client_items(maps)
```

- [ ] **Step 1: 코드 수정**

Edit `regle/services/review/client_service.py:75-80`:

```python
@ToSlackClient("<@{user}> {client_name}의 자사몰 상품명 수집")
def scan_client_items(self, maps=None, flag_force: bool = False):
    upload_driver = self.client.get_upload_drvier()
    if not upload_driver:
        upload_driver = BaseUploadDriver(self.client)
    upload_driver.scan_client_items(maps, flag_force=flag_force)
```

- [ ] **Step 2: 기존 호출부 확인**

Run:
```bash
grep -rn "scan_client_items" regle/ app/ --include="*.py"
```

Expected: 기존 호출부는 `ClientService(id, user).scan_client_items(map_ids)` 형태로 `flag_force` 미전달 → default False → 기존 동작 유지. 수정 불필요.

- [ ] **Step 3: 전체 pytest 실행 — 회귀 없음 확인**

Run:
```bash
.venv/bin/pytest tests/ -x -q 2>&1 | tail -20
```

Expected: 기존 테스트가 깨지지 않음 (기존 호출부 동작 불변)

- [ ] **Step 4: 커밋**

```bash
git add regle/services/review/client_service.py
git commit -m "feat(scan): ClientService.scan_client_items 에 flag_force 전달"
```

---

## Task 3: CLI `--force` 옵션 추가

**Files:**
- Modify: `review-moai-refactoring/regle/typer_cli/task_cli.py:55-63`

- [ ] **Step 1: 코드 수정**

Edit `regle/typer_cli/task_cli.py:55-63`. 시그니처/본문 변경:

```python
@app.command()
def scan_client_items(
    id: Annotated[Optional[int], typer.Option()] = None,
    user: Annotated[Optional[str], typer.Option()] = None,
    map_ids: Annotated[Optional[str], typer.Option()] = None,
    force: Annotated[bool, typer.Option("--force/--no-force")] = False,
):
    print(f"상품 스캔을 시작합니다.{id} force={force}")
    ClientService(id, user).scan_client_items(map_ids, flag_force=force)
    print(f"상품 스캔이 완료되었습니다.{id}")
```

- [ ] **Step 2: CLI 스모크 테스트**

Run:
```bash
.venv/bin/python regle_cli.py scan-client-items --help
```

Expected: `--force` 와 `--no-force` 옵션이 help 에 노출

- [ ] **Step 3: 커밋**

```bash
git add regle/typer_cli/task_cli.py
git commit -m "feat(cli): scan-client-items 에 --force 옵션 추가"
```

---

## Task 4: 전체 테스트 + ruff 최종 점검

- [ ] **Step 1: 전체 pytest**

Run:
```bash
.venv/bin/pytest tests/ -q
```

Expected: 전 테스트 통과 (신규 2건 포함)

- [ ] **Step 2: ruff 전체 점검**

Run:
```bash
.venv/bin/ruff check app/ regle/ tests/
```

Expected: 0 issues (신규 변경 범위 한정)

- [ ] **Step 3: 수정 필요 시 반영 후 재실행. 문제 없으면 다음 태스크로.**

---

## Task 5: regle PR 생성

- [ ] **Step 1: 푸시**

Run:
```bash
cd /opt/SeoulVentures/regle/review-moai-refactoring
git push -u origin feature/scan-client-items-force
```

- [ ] **Step 2: Draft PR 생성**

Run:
```bash
gh pr create --draft \
  --title "feat(scan): scan_client_items 에 flag_force 파라미터 추가" \
  --body "$(cat <<'EOF'
## Summary
- `BaseUploadDriver.scan_client_items` 에 `flag_force: bool = False` 파라미터 추가
- `ClientService.scan_client_items` 가 이를 전달
- CLI `scan-client-items` 에 `--force` 옵션 노출
- 채널용 `scan_target_titles_by_review_target_item_maps(flag_force=True)` 와 대칭 구조

## Spec
regle/docs/superpowers/specs/2026-04-15-review-data-item-name-buttons-design.md (메인 repo)

## 배경
`/review/data` 페이지의 자사몰 상품명 수집 버튼이 `is_name_checked=1` 상품에 대해 스킵 → placeholder 값 (예: 몰 이름) 이 고착. 강제 덮어쓰기 수단 필요. 이 PR 은 워커 쪽 대칭만 제공. SVGW 쪽에서 `force` 쿼리로 활용 예정.

## 호환성
- `flag_force` default `False` — 기존 호출부 동작 완전 불변
- 기존 호출부 grep: `regle/typer_cli/task_cli.py:62` 와 `periodic_regle.py`, `ConfigService` 등 모두 `flag_force` 미전달. default False 로 동작

## Test plan
- [x] pytest 통과 (`tests/unit/drivers/test_base_upload_scan_force.py` 신규 2건)
- [x] 기존 pytest 회귀 없음
- [x] ruff 통과
- [ ] 리뷰 후 ready → 머지 → ECS 이미지 배포 → SVGW PR 진행
EOF
)"
```

- [ ] **Step 3: PR URL 기록** — 이후 SVGW PR 본문에 참조하기 위해 URL 저장

---

## Phase Gate — regle 머지 후 ECS 이미지 반영 확인

이 단계는 **사용자 승인 필요**. 자동 진행 금지.

- [ ] **Step 1: regle PR 리뷰 → 사용자 승인 후 머지** (외부 액션)

- [ ] **Step 2: GitHub Actions 배포 완료 대기**

Run:
```bash
cd /opt/SeoulVentures/regle/review-moai-refactoring
gh run list --workflow=deploy.yml --limit=3
```

Expected: 최신 master 빌드가 `completed success`

- [ ] **Step 3: ECS 태스크 정의의 이미지 태그 갱신 확인**

Run:
```bash
aws ecs describe-task-definition --task-definition regle-worker-cli-production \
  --region ap-northeast-2 \
  --query 'taskDefinition.{revision:revision,image:containerDefinitions[0].image}' \
  --output json
```

Expected: revision 이 증가 + image tag 가 새 SHA

- [ ] **Step 4: 신규 이미지로 `--help` dry-run**

Run:
```bash
aws ecs run-task --cluster regle-worker \
  --task-definition regle-worker-cli-production \
  --launch-type FARGATE --platform-version LATEST \
  --network-configuration 'awsvpcConfiguration={subnets=[subnet-2a24cc66],assignPublicIp=ENABLED}' \
  --overrides '{"containerOverrides":[{"name":"regle-worker","command":["python","regle_cli.py","scan-client-items","--help"]}]}' \
  --region ap-northeast-2 --query 'tasks[0].taskArn' --output text
```

그리고 30-60초 후 CloudWatch 로그 확인:
```bash
aws logs filter-log-events --log-group-name /ecs/regle-worker-cli-production \
  --region ap-northeast-2 \
  --start-time $(( $(date +%s) * 1000 - 300000 )) \
  --filter-pattern '"--force"' --max-items 5 \
  --query 'events[].message' --output text
```

Expected: `--force` 옵션이 help 출력에 포함

- [ ] **Step 5: Phase B 진행 승인 받기**

---

# Phase B — SVGW 변경

## Task 6: SVGW 브랜치 생성 + 기존 코드 재확인

- [ ] **Step 1: 브랜치 생성**

Run:
```bash
cd /opt/SeoulVentures/regle/SeoulVenturesGroupware
git checkout master && git pull
git checkout -b feature/review-data-item-name-reset-force
```

- [ ] **Step 2: routes 구조 확인**

Run:
```bash
grep -n "scan-client-items\|review-uploader/clients" routes/api.php | head -10
```

Expected: `routes/api.php:255` 와 `:402` 에 유사 라우트 2개 (중복 등록 → 하나의 그룹 내). 신규 reset 엔드포인트는 :402 구간의 그룹에 추가.

---

## Task 7: `RegleEcsService::scanClientItems` 에 `force` 인자 추가

**Files:**
- Modify: `SeoulVenturesGroupware/app/Services/RegleEcsService.php:295-302`
- Test: `SeoulVenturesGroupware/tests/Feature/Review/ForceScanClientItemsTest.php` (create)

현재:
```php
public function scanClientItems(int $clientId, ?array $targetItemMaps = null, ?string $requestUser = null): array
{
    return $this->runTask('scan-client-items', [
        'id' => $clientId,
        'user' => $requestUser,
        'map_ids' => $targetItemMaps ? implode(',', $targetItemMaps) : null,
    ]);
}
```

- [ ] **Step 1: 실패하는 feature 테스트 작성** — `tests/Feature/Review/ForceScanClientItemsTest.php`

```php
<?php

namespace Tests\Feature\Review;

use App\Services\RegleEcsService;
use Mockery;
use Tests\TestCase;

class ForceScanClientItemsTest extends TestCase
{
    public function test_force_true_passes_force_flag_to_ecs_service(): void
    {
        $mock = Mockery::mock(RegleEcsService::class);
        $mock->shouldReceive('scanClientItems')
            ->once()
            ->with(1538, null, null, true)
            ->andReturn(['success' => true, 'taskArn' => 'arn:test']);
        $this->app->instance(RegleEcsService::class, $mock);

        $res = $this->postJson('/api/review-uploader/clients/1538/scan-client-items', [
            'force' => true,
        ]);

        $res->assertOk()->assertJson(['success' => true]);
    }

    public function test_force_default_false_preserves_existing_behavior(): void
    {
        $mock = Mockery::mock(RegleEcsService::class);
        $mock->shouldReceive('scanClientItems')
            ->once()
            ->with(1538, null, null, false)
            ->andReturn(['success' => true]);
        $this->app->instance(RegleEcsService::class, $mock);

        $res = $this->postJson('/api/review-uploader/clients/1538/scan-client-items');

        $res->assertOk();
    }
}
```

- [ ] **Step 2: 테스트 실행 — 실패 확인**

Run:
```bash
cd /opt/SeoulVentures/regle/SeoulVenturesGroupware
vendor/bin/phpunit --filter=ForceScanClientItemsTest
```

Expected: `TooManyArguments` 또는 method signature mismatch 로 실패

- [ ] **Step 3: `RegleEcsService::scanClientItems` 시그니처 확장**

Edit `app/Services/RegleEcsService.php:295`:

```php
public function scanClientItems(
    int $clientId,
    ?array $targetItemMaps = null,
    ?string $requestUser = null,
    bool $force = false,
): array {
    $params = [
        'id' => $clientId,
        'user' => $requestUser,
        'map_ids' => $targetItemMaps ? implode(',', $targetItemMaps) : null,
    ];
    if ($force) {
        $params['force'] = true;
    }

    return $this->runTask('scan-client-items', $params);
}
```

주의: `buildArgs` 가 bool true 를 `--force` 플래그로 변환하는지 확인:

Run:
```bash
grep -n "buildArgs\|--'" app/Services/RegleEcsService.php | head -20
```

만약 bool 처리가 없으면 해당 부분도 추가해야 함 (Task 7a 로 취급). 확인 후 필요 시 아래 step 으로.

- [ ] **Step 3a (조건부): `buildArgs` 에 bool flag 지원 추가**

`buildArgs` 가 `bool true` 를 `--force` 단일 토큰으로, `false`/null 은 생략하는 방식인지 확인. 기존 구현 예시:

```php
private function buildArgs(array $params): array
{
    $args = [];
    foreach ($params as $key => $value) {
        if ($value === null || $value === false) continue;
        if ($value === true) {
            $args[] = "--{$key}";
        } else {
            $args[] = "--{$key}={$value}";
        }
    }
    return $args;
}
```

기존 구현이 이와 다르면 동등하게 맞춰 수정. 변경 시 `RegleEcsService` 내부 다른 사용처 회귀 확인 필수 (`scanItemTitles`, `scanTargets`, `buildSimilarity` 등 모두 bool 파라미터가 없는 메서드이므로 회귀 영향 없음).

- [ ] **Step 4: `ReviewScanController::scanClientItems` 가 `force` 를 읽도록 수정**

Edit `app/Http/Controllers/ReviewUploader/ReviewScanController.php:62-73`:

```php
        $targetItemMaps = $request->has('target_item_maps')
            ? explode(',', $request->get('target_item_maps'))
            : null;

        $force = filter_var($request->input('force', false), FILTER_VALIDATE_BOOLEAN);

        $result = $this->ecsService->scanClientItems(
            $clientId,
            $targetItemMaps,
            $request->header('X-Request-User'),
            $force,
        );

        return response()->json($result, $result['success'] ? 200 : 500);
```

- [ ] **Step 5: 기존 scan-client-items 라우트에 POST 메서드 추가**

기존 라우트는 GET 임 (`routes/api.php:402`). `force` 를 body 로 받기 위해 POST 도 허용:

Edit `routes/api.php:402` 라인을:

```php
Route::match(['get', 'post'], 'review-uploader/clients/{clientId}/scan-client-items', [ReviewScanController::class, 'scanClientItems']);
```

마찬가지로 `routes/api.php:255` 의 동일 중복 라우트도 같은 방식으로 수정.

- [ ] **Step 6: 테스트 실행 — 통과 확인**

Run:
```bash
vendor/bin/phpunit --filter=ForceScanClientItemsTest
```

Expected: 2 passed

- [ ] **Step 7: 커밋**

```bash
git add app/Services/RegleEcsService.php app/Http/Controllers/ReviewUploader/ReviewScanController.php routes/api.php tests/Feature/Review/ForceScanClientItemsTest.php
git commit -m "feat(review-scan): scan-client-items 에 force 파라미터 수용

body 또는 query 로 force=true 전달 시 regle CLI 에 --force 플래그 추가.
default false 로 기존 GET 호출 동작 불변."
```

---

## Task 8: `resetClientItemNames` 액션 추가 (Controller + Service + Routes)

**Files:**
- Modify: `SeoulVenturesGroupware/app/Http/Controllers/ReviewUploader/ReviewScanController.php` — 메서드 추가
- Modify: `SeoulVenturesGroupware/routes/api.php` — 엔드포인트 추가
- Test: `SeoulVenturesGroupware/tests/Feature/Review/ResetClientItemNamesTest.php` (create)

- [ ] **Step 1: 실패하는 feature 테스트 작성** — `tests/Feature/Review/ResetClientItemNamesTest.php`

```php
<?php

namespace Tests\Feature\Review;

use App\Models\Review\Client;
use App\Models\Review\ClientItem;
use App\Models\Review\TargetItemMap;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class ResetClientItemNamesTest extends TestCase
{
    use RefreshDatabase;

    private function makeClient(int $id = 1538): Client
    {
        return Client::factory()->create(['id' => $id, 'name' => '바닐라코']);
    }

    public function test_reset_selected_map_ids_clears_item_name_and_flag(): void
    {
        $client = $this->makeClient();
        $item = ClientItem::factory()->create([
            'client_id' => $client->id,
            'item_code' => '1177',
            'item_name' => '바닐라닷컴',
            'is_name_checked' => 1,
        ]);
        $map = TargetItemMap::factory()->create([
            'client_id' => $client->id,
            'client_item_code' => $item->item_code,
        ]);

        $res = $this->postJson(
            "/api/review-uploader/clients/{$client->id}/reset-client-item-names",
            ['map_ids' => [$map->id], 'all' => false],
        );

        $res->assertOk()->assertJson(['success' => true, 'reset_count' => 1]);
        $this->assertDatabaseHas('review_client_items', [
            'id' => $item->id, 'item_name' => null, 'is_name_checked' => 0,
        ]);
    }

    public function test_reset_all_mode_resets_every_mapped_item_for_client(): void
    {
        $client = $this->makeClient();
        foreach (['a', 'b'] as $code) {
            $item = ClientItem::factory()->create([
                'client_id' => $client->id, 'item_code' => $code,
                'item_name' => 'X', 'is_name_checked' => 1,
            ]);
            TargetItemMap::factory()->create([
                'client_id' => $client->id, 'client_item_code' => $code,
            ]);
        }

        $res = $this->postJson(
            "/api/review-uploader/clients/{$client->id}/reset-client-item-names",
            ['all' => true],
        );

        $res->assertOk()->assertJson(['reset_count' => 2]);
    }

    public function test_reset_does_not_touch_other_clients(): void
    {
        $own = $this->makeClient(1538);
        $other = $this->makeClient(1539);

        ClientItem::factory()->create([
            'client_id' => $other->id, 'item_code' => 'zz',
            'item_name' => 'keep', 'is_name_checked' => 1,
        ]);
        TargetItemMap::factory()->create([
            'client_id' => $other->id, 'client_item_code' => 'zz',
        ]);

        $this->postJson(
            "/api/review-uploader/clients/{$own->id}/reset-client-item-names",
            ['all' => true],
        )->assertOk();

        $this->assertDatabaseHas('review_client_items', [
            'client_id' => $other->id, 'item_name' => 'keep', 'is_name_checked' => 1,
        ]);
    }

    public function test_missing_map_ids_and_all_false_returns_422(): void
    {
        $client = $this->makeClient();
        $this->postJson(
            "/api/review-uploader/clients/{$client->id}/reset-client-item-names",
            ['all' => false],
        )->assertStatus(422);
    }
}
```

- [ ] **Step 2: 테스트 실행 — 실패 확인**

Run:
```bash
vendor/bin/phpunit --filter=ResetClientItemNamesTest
```

Expected: 404 (route 없음) 또는 method not found

- [ ] **Step 3: Controller 에 `resetClientItemNames` 메서드 추가**

Append to `app/Http/Controllers/ReviewUploader/ReviewScanController.php` (use 구문 상단에 필요한 모델 추가):

```php
use App\Models\Review\ClientItem;
use App\Models\Review\TargetItemMap;
```

메서드 본문 (클래스 내부, 기존 메서드 뒤에 추가):

```php
    /**
     * 자사몰 상품명 초기화
     *
     * 선택된 매핑 (또는 전체) 의 연결 자사몰 상품에 대해 item_name=NULL,
     * is_name_checked=0 으로 리셋한다. 수집 트리거는 하지 않는다.
     *
     * @urlParam clientId integer required 클라이언트 ID. Example: 1538
     * @bodyParam map_ids array 선택 매핑 ID. all=true 면 무시. Example: [2362283, 2362284]
     * @bodyParam all boolean 전체 모드. Example: false
     *
     * @response 200 {"success": true, "reset_count": 2}
     */
    public function resetClientItemNames(Request $request, int $clientId): JsonResponse
    {
        $validated = $request->validate([
            'all' => ['required', 'boolean'],
            'map_ids' => ['required_unless:all,true', 'array'],
            'map_ids.*' => ['integer'],
        ]);

        if (!Client::find($clientId)) {
            return response()->json([
                'success' => false,
                'error' => 'Client not found',
            ], 404);
        }

        $mapTable = (new TargetItemMap())->getTable();
        $itemTable = (new ClientItem())->getTable();

        $itemIdsQuery = ClientItem::query()
            ->where('client_id', $clientId)
            ->whereIn('item_code', function ($q) use ($mapTable, $clientId, $validated) {
                $q->select('client_item_code')
                  ->from($mapTable)
                  ->where('client_id', $clientId);
                if (empty($validated['all'])) {
                    $q->whereIn('id', $validated['map_ids']);
                }
            });

        $total = 0;
        $itemIdsQuery->chunkById(1000, function ($items) use (&$total, $itemTable) {
            $ids = $items->pluck('id')->all();
            $total += \DB::table($itemTable)->whereIn('id', $ids)->update([
                'item_name' => null,
                'is_name_checked' => 0,
                'updated_at' => now(),
            ]);
        });

        return response()->json([
            'success' => true,
            'reset_count' => $total,
        ]);
    }
```

- [ ] **Step 4: 라우트 등록**

Edit `routes/api.php`, Task 7 에서 수정한 `scan-client-items` 라우트 바로 아래에 추가 (두 구간 — :255 그룹, :402 그룹 둘 다):

```php
Route::post('review-uploader/clients/{clientId}/reset-client-item-names', [ReviewScanController::class, 'resetClientItemNames']);
```

- [ ] **Step 5: 테스트 실행 — 통과 확인**

Run:
```bash
vendor/bin/phpunit --filter=ResetClientItemNamesTest
```

Expected: 4 passed

- [ ] **Step 6: 커밋**

```bash
git add app/Http/Controllers/ReviewUploader/ReviewScanController.php routes/api.php tests/Feature/Review/ResetClientItemNamesTest.php
git commit -m "feat(review-scan): 자사몰 상품명 초기화 API 추가

POST /review-uploader/clients/{id}/reset-client-item-names
선택 매핑 또는 전체 매핑 연결 자사몰 상품의 item_name/is_name_checked 리셋.
placeholder 상품명 고착 해소용."
```

---

## Task 9: 프론트엔드 API 엔티티 확장

**Files:**
- Modify: `SeoulVenturesGroupware/frontend/resources/ts/api/entities/review/clientItems.ts`

현재 파일은 `get` import 만 하지만 POST 가 필요. `@/api` 의 `post` 도 import.

- [ ] **Step 1: 파일 교체**

Edit `frontend/resources/ts/api/entities/review/clientItems.ts` 전체 교체:

```typescript
import { type ApiResponse, get, post } from '@/api'

export interface ClientItem {
  id: number
  client_id: number
  item_code: string | null
  item_name: string | null
  item_url: string | null
  created_at: string | null
  updated_at: string | null
}

export const clientItemsApi = {
  resolveProductNames: (clientId: number | string, opts?: { force?: boolean }): Promise<ApiResponse> =>
    opts?.force
      ? post(`/review-uploader/clients/${clientId}/scan-client-items`, { force: true })
      : get(`/review-uploader/clients/${clientId}/scan-client-items`),

  resolveProductNamesByTargetItemMapIds: (
    clientId: number | string,
    targetItemMapIds: number[],
    opts?: { force?: boolean },
  ): Promise<ApiResponse> =>
    opts?.force
      ? post(`/review-uploader/clients/${clientId}/scan-client-items`, {
          target_item_maps: targetItemMapIds.join(','),
          force: true,
        })
      : get(`/review-uploader/clients/${clientId}/scan-client-items`, {
          target_item_maps: targetItemMapIds.join(','),
        }),

  resetProductNames: (clientId: number | string): Promise<ApiResponse> =>
    post(`/review-uploader/clients/${clientId}/reset-client-item-names`, { all: true }),

  resetProductNamesByTargetItemMapIds: (
    clientId: number | string,
    targetItemMapIds: number[],
  ): Promise<ApiResponse> =>
    post(`/review-uploader/clients/${clientId}/reset-client-item-names`, {
      all: false,
      map_ids: targetItemMapIds,
    }),
}

export default clientItemsApi
```

- [ ] **Step 2: 타입 체크**

Run:
```bash
cd frontend
bun run typecheck 2>&1 | tail -20
```

Expected: 신규 API 관련 에러 없음 (기존 호출부는 1-인자 형태 그대로 — opts 가 optional 이므로 호환)

- [ ] **Step 3: 커밋**

```bash
cd /opt/SeoulVentures/regle/SeoulVenturesGroupware
git add frontend/resources/ts/api/entities/review/clientItems.ts
git commit -m "feat(frontend): clientItemsApi 에 reset + force 옵션 추가"
```

---

## Task 10: `/review/data` 페이지에 버튼 4개 + 핸들러 추가

**Files:**
- Modify: `SeoulVenturesGroupware/frontend/resources/ts/pages/review/data/index.vue`

기존 `resolveClientProductNames`, `resolveClientProductNamesForMappings` (line 540-594) 아래에 핸들러 4개 추가 + template 에 버튼 UI 추가.

- [ ] **Step 1: 스크립트 섹션에 핸들러 4개 추가**

`index.vue` 의 `<script setup>` 섹션, 기존 `resolveClientProductNamesForMappings` (line 594) 직후에 삽입:

```typescript
// 자사몰 상품명 초기화 - 전체
const resetClientProductNames = () => {
  if (!selectedClient.value?.id)
    return

  showConfirm('전체 매핑의 자사몰 상품명을 초기화하시겠습니까? (item_name=NULL, is_name_checked=0)', async () => {
    try {
      const { success, reset_count } = await clientItemsApi.resetProductNames(selectedClient.value!.id)
      if (success)
        snackbar.success(`자사몰 상품명 ${reset_count}건 초기화됨.`)
      else
        snackbar.error('자사몰 상품명 초기화에 실패했습니다.')
    }
    catch (error) {
      handleError(error, { notificationMessage: '자사몰 상품명 초기화에 실패했습니다.' })
    }
  })
}

// 자사몰 상품명 초기화 - 선택된 매핑
const resetClientProductNamesForMappings = () => {
  if (!selectedClient.value?.id || selectedMappings.value.length === 0)
    return

  showConfirm(`선택된 ${selectedMappings.value.length}건 매핑의 자사몰 상품명을 초기화하시겠습니까?`, async () => {
    try {
      const mappingIds = selectedMappings.value.map(m => m.id)
      const { success, reset_count } = await clientItemsApi.resetProductNamesByTargetItemMapIds(
        selectedClient.value!.id,
        mappingIds,
      )
      if (success)
        snackbar.success(`자사몰 상품명 ${reset_count}건 초기화됨.`)
      else
        snackbar.error('자사몰 상품명 초기화에 실패했습니다.')
    }
    catch (error) {
      handleError(error, { notificationMessage: '자사몰 상품명 초기화에 실패했습니다.' })
    }
  })
}

// 자사몰 상품명 강제 수집 - 전체 (force=true)
const forceResolveClientProductNames = () => {
  if (!selectedClient.value?.id)
    return

  showConfirm('전체 매핑의 자사몰 상품명 강제 수집을 요청하시겠습니까? (기존 값 덮어씀)', async () => {
    try {
      const { success } = await clientItemsApi.resolveProductNames(selectedClient.value!.id, { force: true })
      if (success)
        snackbar.success('자사몰 상품명 강제 수집이 요청되었습니다. 완료 시 슬랙으로 알려드립니다.')
      else
        snackbar.error('자사몰 상품명 강제 수집 요청에 실패했습니다.')
    }
    catch (error) {
      handleError(error, { notificationMessage: MSG_PRODUCT_NAME_COLLECT_FAILED })
    }
  })
}

// 자사몰 상품명 강제 수집 - 선택된 매핑
const forceResolveClientProductNamesForMappings = () => {
  if (!selectedClient.value?.id || selectedMappings.value.length === 0)
    return

  showConfirm(`선택된 ${selectedMappings.value.length}건 매핑의 자사몰 상품명 강제 수집을 요청하시겠습니까? (기존 값 덮어씀)`, async () => {
    try {
      const mappingIds = selectedMappings.value.map(m => m.id)
      const { success } = await clientItemsApi.resolveProductNamesByTargetItemMapIds(
        selectedClient.value!.id,
        mappingIds,
        { force: true },
      )
      if (success)
        snackbar.success('선택된 매핑의 자사몰 상품명 강제 수집이 요청되었습니다.')
      else
        snackbar.error('자사몰 상품명 강제 수집 요청에 실패했습니다.')
    }
    catch (error) {
      handleError(error, { notificationMessage: MSG_PRODUCT_NAME_COLLECT_FAILED })
    }
  })
}
```

- [ ] **Step 2: 템플릿에 버튼 UI 추가**

`index.vue` 의 template 섹션에서 기존 `resolveClientProductNames` 를 호출하는 버튼을 찾고, 같은 툴바 그룹에 버튼 4개를 추가. 예시 (기존 버튼 배치를 따라 Vuetify `VBtn` 사용):

```vue
<!-- 기존 "자사몰 상품명 수집" 버튼 옆에 추가 -->

<VMenu>
  <template #activator="{ props }">
    <VBtn v-bind="props" variant="outlined" prepend-icon="mdi-restore" :disabled="!selectedClient">
      자사몰 상품명 초기화
    </VBtn>
  </template>
  <VList>
    <VListItem
      :disabled="selectedMappings.length === 0"
      @click="resetClientProductNamesForMappings"
    >
      <VListItemTitle>선택된 {{ selectedMappings.length }}건</VListItemTitle>
    </VListItem>
    <VListItem @click="resetClientProductNames">
      <VListItemTitle>전체 매핑</VListItemTitle>
    </VListItem>
  </VList>
</VMenu>

<VMenu>
  <template #activator="{ props }">
    <VBtn v-bind="props" variant="outlined" color="warning" prepend-icon="mdi-reload-alert" :disabled="!selectedClient">
      자사몰 상품명 강제 수집
    </VBtn>
  </template>
  <VList>
    <VListItem
      :disabled="selectedMappings.length === 0"
      @click="forceResolveClientProductNamesForMappings"
    >
      <VListItemTitle>선택된 {{ selectedMappings.length }}건</VListItemTitle>
    </VListItem>
    <VListItem @click="forceResolveClientProductNames">
      <VListItemTitle>전체 매핑</VListItemTitle>
    </VListItem>
  </VList>
</VMenu>
```

**주의**: 실제 아이콘명과 툴바 래퍼 (`VBtnGroup`, `VToolbarItems`, `VRow` 등) 는 기존 `resolveClientProductNames` 버튼의 주변 마크업을 따른다. 주변 구조에 맞게 감싸기만 통일.

- [ ] **Step 3: 린트 + 타입체크**

Run:
```bash
cd frontend
bun run lint
bun run typecheck 2>&1 | tail -30
```

Expected: 에러 없음

- [ ] **Step 4: 개발 서버 스모크 테스트**

Run (별도 터미널 권장):
```bash
cd frontend
bun run dev
```

브라우저에서 `/review/data` 로 접속, 클라이언트 선택 후:
- 새 버튼 2개 노출 확인
- 드롭다운에 "선택된 N건" / "전체 매핑" 2개 옵션
- 선택 모드는 체크박스 0건 시 disabled
- 클라이언트 미선택 시 두 버튼 disabled

- [ ] **Step 5: 커밋**

```bash
cd /opt/SeoulVentures/regle/SeoulVenturesGroupware
git add frontend/resources/ts/pages/review/data/index.vue
git commit -m "feat(review-data): 자사몰 상품명 초기화·강제수집 버튼 추가

선택/전체 모드 드롭다운. 초기화는 DB 리셋 (수집 트리거 없음),
강제 수집은 force=true 로 is_name_checked 무시하고 덮어쓰기."
```

---

## Task 11: SVGW 전체 테스트 스위트

- [ ] **Step 1: PHPUnit 전체**

Run:
```bash
cd /opt/SeoulVentures/regle/SeoulVenturesGroupware
vendor/bin/phpunit --filter="Review"
```

Expected: 신규 2 class 포함 전부 통과

- [ ] **Step 2: PHPUnit 기존 회귀**

Run:
```bash
vendor/bin/phpunit
```

Expected: 기존 테스트 전부 통과

- [ ] **Step 3: 프론트 typecheck + lint**

Run:
```bash
cd frontend
bun run typecheck && bun run lint
```

Expected: 0 error

---

## Task 12: SVGW Draft PR 생성

- [ ] **Step 1: 푸시**

Run:
```bash
cd /opt/SeoulVentures/regle/SeoulVenturesGroupware
git push -u origin feature/review-data-item-name-reset-force
```

- [ ] **Step 2: Draft PR 생성**

Run:
```bash
gh pr create --draft \
  --title "feat(review-data): 자사몰 상품명 초기화·강제수집 버튼 추가" \
  --body "$(cat <<'EOF'
## Summary
- `/review/data` 페이지에 버튼 2개 추가: 자사몰 상품명 초기화 / 강제 수집
- 각 버튼 드롭다운으로 "선택된 N건" / "전체 매핑" 모드 제공
- 초기화: `item_name=NULL, is_name_checked=0` 리셋만 (수집 트리거 없음)
- 강제 수집: 기존 `scan-client-items` 엔드포인트에 `force=true` 전달 → regle 워커가 `is_name_checked` 무시하고 덮어쓰기

## Depends on
- regle PR: <regle PR URL — Task 5 Step 3 에서 기록한 URL>
- 위 PR 이 prod 에 배포되어 있어야 `force=true` 가 실제 강제수집 동작함 (구버전 regle 은 `--force` 무시)

## Spec
regle/docs/superpowers/specs/2026-04-15-review-data-item-name-buttons-design.md

## 배경
바닐라코 client_id=1538 의 자사몰 상품 item_code=1177 이 `item_name='바닐라닷컴'`, `is_name_checked=1` 로 고착. 기존 수집 버튼은 `is_name_checked=True` 이면 스킵. 운영자 복구 수단 부재.

## 변경 내역
### 백엔드
- `RegleEcsService::scanClientItems` 에 `bool $force` 파라미터 추가 (default false)
- `ReviewScanController::scanClientItems` 가 request `force` 파싱 → service 전달
- `ReviewScanController::resetClientItemNames` 신규 (POST)
- `routes/api.php`: scan 라우트 POST 허용 + reset 라우트 신규 등록

### 프론트엔드
- `clientItemsApi` 에 `resetProductNames`, `resetProductNamesByTargetItemMapIds` 추가
- `resolveProductNames` / `resolveProductNamesByTargetItemMapIds` 에 `{ force?: boolean }` optional 옵션 추가 (기존 호출부 호환)
- `/review/data` 페이지 index.vue 에 버튼 2개 + 핸들러 4개

### 마이그레이션
없음

## Test plan
- [x] PHPUnit `ResetClientItemNamesTest` (4 cases) 통과
- [x] PHPUnit `ForceScanClientItemsTest` (2 cases) 통과
- [x] PHPUnit 기존 스위트 회귀 없음
- [x] 프론트 typecheck / lint 통과
- [ ] 개발 서버에서 버튼 동작 스모크 (클라이언트 선택/미선택, 체크박스 0건/N건 × 4경로 + 초기화 후 실제 DB 리셋 확인 + 강제수집 ECS RunTask 발사 확인)
- [ ] regle PR 머지 + 이미지 배포 후 staging 에서 end-to-end 1회 (바닐라코 1538 / item_code=1177 실제 복구 시나리오)

## 배포 순서
1. regle PR 머지 → ECS 이미지 빌드 완료 확인 (`aws ecs describe-task-definition` 로 신규 revision)
2. 이 PR ready for review → 머지
3. SVGW prod 배포: gh release create 시 `--target "$(git ls-remote <repo> refs/heads/master | awk '{print $1}')" v<x.y.z>` (SHA 명시)
4. 직후 `git ls-remote <repo> refs/tags/v<x.y.z>` 로 master HEAD 와 일치 확인
EOF
)"
```

- [ ] **Step 3: PR URL 기록**

---

## Task 13: 스테이징/프로덕션 검증 (사용자 승인 후)

- [ ] **Step 1: regle PR + SVGW PR 모두 승인/머지**

- [ ] **Step 2: staging 배포 확인**

Run:
```bash
gh run list --workflow=deploy.yml --limit=3
```

- [ ] **Step 3: 바닐라코 1538 / item_code=1177 실제 복구 시나리오**

1. `/review/data` 접속, 클라이언트 `바닐라코` 선택
2. item_code=1177 매핑 2건 체크
3. "자사몰 상품명 초기화" → "선택된 2건" 클릭 → snackbar `2건 초기화됨`
4. DB 확인:
   ```bash
   cd /opt/SeoulVentures/regle/review-moai-refactoring
   .venv/bin/python -c "
   import os, pymysql
   from dotenv import load_dotenv
   load_dotenv()
   c = pymysql.connect(host=os.getenv('MYSQL_HOST'), user=os.getenv('MYSQL_USER'),
       password=os.getenv('MYSQL_PASSWD'), database=os.getenv('MYSQL_DATABASE'),
       port=int(os.getenv('MYSQL_PORT')), charset='utf8mb4')
   with c.cursor() as cur:
       cur.execute(\"SELECT item_name, is_name_checked FROM review_client_items WHERE client_id=1538 AND item_code='1177'\")
       print(cur.fetchall())
   "
   ```
   Expected: `((None, 0),)`
5. "자사몰 상품명 강제 수집" → "선택된 2건" 클릭 → snackbar `강제 수집이 요청되었습니다`
6. CloudWatch `/ecs/regle-worker-cli-production` 로그:
   ```bash
   NOW=$(date +%s)000
   START=$(( $(date -d '10 minutes ago' +%s) * 1000 ))
   aws logs filter-log-events --log-group-name /ecs/regle-worker-cli-production \
     --region ap-northeast-2 --start-time $START --end-time $NOW \
     --filter-pattern '"force=True"' --max-items 5 \
     --query 'events[].message' --output text
   ```
   Expected: `상품 스캔을 시작합니다.1538 force=True` 로그 확인
7. 5-10분 후 DB 재확인 → `item_name` 이 실제 자사몰 상품명으로 채워졌거나 (URL 패턴 수정 필요 시 여전히 실패 — 후속 이슈 범위)

- [ ] **Step 4: 메모리 업데이트**

`/opt/SeoulVentures/.claude/projects/-opt-SeoulVentures-regle/memory/` 에 이번 작업 결과 기록:
- `review-data-item-name-buttons-2026-04-15.md` 신규 (작업 요약, 교훈)
- `MEMORY.md` 에 한 줄 추가

- [ ] **Step 5: 후속 이슈 발행** (사용자 승인 후)

- `review-moai-refactoring`: `review_clients.product_url_pattern` 과 실제 `item_url` 형식 불일치 검증 로직
- `review-moai-refactoring`: 올리브영 403 우회 전략 (UA/프록시)
- SVGW: `review_clients.upload_driver_config` / `Authorization` NULL 상태 감지 & 알림 (크리마 업로드 설정 결손 대응)

---

## Self-Review 체크리스트 (구현자용)

- [ ] 스펙의 모든 요구 (초기화 선택/전체, 강제수집 선택/전체) 가 태스크로 매핑됨 — Task 1-13
- [ ] regle `flag_force` default False 로 기존 호출부 회귀 없음 — Task 2 Step 3 에서 전체 pytest
- [ ] SVGW `scanClientItems` 기존 GET 호출부 호환 — Task 7 Step 1 의 두 번째 테스트
- [ ] 프론트 `resolveProductNames` 기존 1-인자 호출부 호환 — `opts` 가 optional
- [ ] `(new Model())->getTable()` 사용 — Task 8 Step 3
- [ ] `chunkById(1000)` 사용 — Task 8 Step 3
- [ ] 클라이언트 scope 격리 — Task 8 Step 1 세 번째 테스트로 보증
- [ ] gh release SHA 명시 — Task 12 Step 2 PR body 에 명시

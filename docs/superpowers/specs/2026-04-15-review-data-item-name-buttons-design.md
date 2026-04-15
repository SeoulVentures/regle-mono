# review/data 자사몰 상품명 초기화 · 강제 수집 버튼

작성일: 2026-04-15
대상: SVGW `/review/data` 페이지 + regle 워커 (review-moai-refactoring)

## 배경

자사몰 상품의 `item_name` 이 placeholder (예: 몰 이름 `바닐라닷컴`) 로 남고 `is_name_checked=1` 이면, 기존 "자사몰 상품명 수집" 버튼을 눌러도 `BaseUploadDriver.scan_client_items` 가 스킵 (`if is_name_checked is not True` 가드, `app/drivers/BaseUploadDriver.py:501`) 하여 영원히 갱신되지 않는다. 운영자가 이 상태를 되돌릴 수단이 필요하다.

**이 스펙은 기존 대칭 구조를 자사몰 쪽에 적용하는 작업**이다:
- 채널 상품 쪽은 이미 `reset_product_names()` (`regle/services/review/config_service.py:243`) + `scan_target_titles_by_review_target_item_maps(flag_force=True)` (`app/drivers/BaseUploadDriver.py:1164`) 로 "리셋 + 강제 재수집" 대칭이 구현되어있다.
- 자사몰 쪽은 해당 대칭이 없다. 이 빈자리를 메운다.

본 스펙은 바닐라코 1538/1177 의 올리브영 403, 크리마 `upload_driver_config` 결손과는 별개다. 이 도구는 placeholder 상품명을 복구할 운영 수단만 제공한다.

## 범위

- 대상 페이지: SVGW `/review/data`
- 단위: `review_target_item_map` (매핑). 기존 체크박스 재사용.
- 버튼 2개 추가: **자사몰 상품명 초기화**, **자사몰 상품명 강제 수집**
- 각 버튼은 "선택 매핑" / "전체 (현재 클라이언트 매핑)" 두 모드 — 기존 `resolveClientProductNames` / `resolveClientProductNamesForMappings` 패턴 그대로

## 동작 정의

### 초기화
- 선택 매핑들의 `client_item_code` → `review_client_items` 집합 S 도출 (동일 `client_id` scope)
- `UPDATE review_client_items SET item_name = NULL, is_name_checked = 0 WHERE id IN S`
- `all=true` 면 해당 클라이언트의 모든 매핑이 대상
- 수집 트리거 없음

### 강제 수집
- 기존 `scanClientItems` 경로에 `force=true` 옵션을 전달하는 형태
- regle 워커는 `BaseUploadDriver.scan_client_items(maps, flag_force=True)` 로 호출되어 `is_name_checked` 무시하고 재수집, 성공 시 `item_name` 덮어쓰기

## 구현

### regle (review-moai-refactoring)

**`BaseUploadDriver.scan_client_items` 에 `flag_force` 파라미터 추가** — 이미 `scan_target_titles_by_review_target_item_maps` 에 존재하는 패턴을 자사몰 쪽에 대칭 적용.

```python
def scan_client_items(self, maps=None, flag_force: bool = False):
    ...
    if not flag_force and review_client_item.is_name_checked is True:
        continue  # 기존 스킵 로직
    ...
```

- default `False` → 기존 호출부 동작 완전 불변
- `ClientService.scan_client_items(maps=None, flag_force=False)` 도 동일 시그니처로 전달
- CLI: `regle/typer_cli/task_cli.py:55` 의 `scan_client_items` 커맨드에 `--force` 옵션 추가 (`python regle_cli.py scan-client-items --id=... --map-ids=... --force`)

### SVGW (Laravel + Vue)

**API 2개** — 기존 `ReviewScanController` 확장:

1. `POST /review-uploader/clients/{clientId}/reset-client-item-names`
   - body: `{ "map_ids"?: int[], "all": bool }`
   - 처리: `review_client_items` UPDATE (위 "초기화" 정의대로). 동기 응답.
   - 응답: `{ "success": true, "reset_count": N }`

2. **기존** `POST /review-uploader/clients/{clientId}/scan-client-items` **에 `force` 파라미터 추가**
   - body 에 `"force": true` 수용
   - `force=true` 시 regle CLI 호출에 `--force` 전달 (ECS RunTask payload)
   - dispatch 경로: 기존 `RegleEcsService` 재사용. **Laravel Queue 미사용** — 기존 상품명 수집 패턴과 일관 유지 (SVGW 의 Laravel Queue 는 다른 용도 전용)

**Vue 변경** (`frontend/resources/ts/pages/review/data/index.vue`):
- 기존 `resolveClientProductNames` / `resolveClientProductNamesForMappings` 옆에 버튼 2개 추가
- 비활성화: 클라이언트 미선택 시 disabled, 로딩 중 disabled. "선택" 모드는 체크박스 0건일 때 disabled
- 전체 모드: confirm dialog 에 대상 건수 표시 (PR #519 교훈)
- `{ success: false }` 분기에서 snackbar error (CLAUDE.md API 호출 패턴)
- 로딩 가드 (중복 요청 방지)

**구현 규칙**:
- `map_ids` validation: `required_unless:all,true | array`
- 모델 쿼리는 `(new ReviewTargetItemMap())->getTable()` 사용 (PR #519 교훈)
- 대량 업데이트는 `chunkById(1000)`

## 데이터 변경

- **마이그레이션 없음**
- 쓰기 영향: `retaku_admin.review_client_items` (`item_name`, `is_name_checked`, `updated_at`)

## 테스트

### regle (pytest)
- `scan_client_items(flag_force=True)` 는 `is_name_checked=1` 상품도 재수집
- `scan_client_items()` default 호출은 기존 동작 불변 (회귀)

### SVGW (PHPUnit)
- 초기화 API: 선택/전체 모드 동작
- 강제 수집: `force=true` 가 regle CLI 페이로드에 반영됨 (`RegleEcsService` mock)

## 배포 순서

1. **regle PR 머지** → ECS 이미지 빌드. `aws ecs describe-task-definition --task-definition regle-worker-cli-production` 로 신규 SHA 확인
2. **SVGW PR 머지** → `gh release create --target "$(git ls-remote <repo> refs/heads/master | awk '{print $1}')" v<x.y.z>` (SHA 명시 — 메모리 교훈 반영). 직후 `git ls-remote <repo> refs/tags/v<x.y.z>` 로 master HEAD 와 일치 확인

원칙: regle 는 하위 호환 (파라미터 추가만, default 가 기존 동작). SVGW 를 regle 보다 먼저 prod 로 올리지 않음.

## 후속 (별도 이슈로 발행)

- `review_clients.product_url_pattern` 과 실제 `item_url` 형식 불일치 검증 (바닐라코 루트 원인)
- 올리브영 403 우회 전략
- `review_clients.upload_driver_config` / `Authorization` NULL 상태 감지 & 알림

# Target 액션을 매핑 관리 페이지로 이동

## 날짜
2026-02-24

## 요약
매핑 입력 페이지(`/review/mapping-manager`)의 Target 액션 3개(상품명 초기화, 직진배송 삭제, 유사도 계산)를
매핑 관리 페이지(`/review/data`)로 이동하여, ID 수동 입력 대신 테이블에서 레코드를 선택하고 액션을 실행하는 방식으로 변경한다.

## 변경 대상

### 제거: 매핑 입력 페이지
- `pages/review/mapping-manager/index.vue`에서 Target 액션 섹션(약 771~893줄) 제거
- 관련 script 코드(386~483줄) 제거
- 직진배송 삭제 확인 다이얼로그(931~960줄) 제거
- `targetActionsApi`, `targetItemMapActionsApi` import 제거

### 추가: 매핑 관리 페이지
- `pages/review/data/index.vue`의 row action 메뉴(VMenu)에 3개 액션 추가:
  - **채널 상품명 초기화**: `targetActionsApi.clearItemTitle(target_id)` 호출
  - **직진배송 삭제**: 확인 다이얼로그 후 `targetActionsApi.deleteZzExpress(target_id)` 호출
  - **유사도 계산**: `targetItemMapActionsApi.generateSimilarity(mapping_id)` 호출

### API 확인 필요
- TargetItemMap 응답에 `target_id`가 포함되는지 확인
- 없으면 API에서 target_id를 추가해야 함

## 엣지 케이스
- target_id가 null인 매핑 → 상품명 초기화/직진배송 삭제 버튼 비활성화
- 직진배송이 아닌 Target에 직진배송 삭제 실행 → 서버에서 400 응답, 에러 메시지 표시

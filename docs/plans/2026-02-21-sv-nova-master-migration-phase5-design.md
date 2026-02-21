# sv-nova-master 마이그레이션 Phase 5~7 설계 — 운영 액션 이관 및 서비스 종료

**작성일:** 2026-02-21
**대상 리포:** regle-mono (서브모듈: sv-nova-master, SeoulVenturesGroupware)
**목표:** Phase 1~4에서 누락된 Nova Actions 및 모니터링 리소스를 SVGW로 이관하고, sv-nova-master를 완전히 제거

---

## 배경

Phase 1~4 완료 후 재점검 결과, 운영팀이 실제 사용 중인 Nova Actions 및 리소스 다수가 이관되지 않은 것을 확인. 총 3개 Phase로 나누어 처리.

### Phase 1~4 이관 완료 항목
- 통계 대시보드, 일일 리포트, NaverXls 임포트
- JobResource, CfClearance, ReviewApiUser, IssueCase (운영 도구 4종)

### 이관 제외 확정 항목
- `NotificationSetting` / `report:send-notification` — 알림톡 API 미완성 (`api.example.com` 플레이스홀더), 이관 없이 제거
- Filament MongoDBReviews / ReviewManagement — 사용자 결정으로 제외

---

## Phase 5 — 드라이버/클라이언트 핵심 운영 액션 이관

### 범위

#### DriverConfig 페이지 액션
| Nova Action | 역할 | SVGW 구현 위치 |
|-------------|------|----------------|
| `ClearLastCrawledDate` | DriverConfig/Target/TargetItemMap의 last_crawled_date 일괄 초기화 | 드라이버 상세 페이지 액션 버튼 |
| `CollectReviewsByDriverConfig` | ECS 리뷰 수집 태스크 실행 | 드라이버 상세 페이지 액션 버튼 |
| `RunPeriodicEcsTask` | 정기 이관 ECS 강제 실행 | 드라이버 상세 페이지 액션 버튼 |
| `RunWidgetEcsTask` | 위젯 처리 ECS 강제 실행 | 드라이버 상세 페이지 액션 버튼 |
| `UnlockSoldoutAction` | 품절(not_for_sale) 상태 해제 | 드라이버 상세 페이지 액션 버튼 |
| `BulkDeleteZzExpressFromDriverConfig` | Zigzag 직진배송 Target 일괄 삭제 | 드라이버 상세 페이지 액션 버튼 (Zigzag 드라이버에만 표시) |
| `UpdateLastCrawledDateToDriverConfig` | 모든 Target 중 최신 크롤링 날짜를 DriverConfig에 기록 | 드라이버 상세 페이지 액션 버튼 |

#### Client 페이지 액션
| Nova Action | 역할 | SVGW 구현 위치 |
|-------------|------|----------------|
| `BulkUpdateMonthlyState` | monthly_state Y/N 일괄 변경 + DriverConfig 연동 | 클라이언트 목록 페이지 일괄 액션 |
| `ImWebExcelAction` | MongoDB 리뷰를 Excel + 이미지 Zip으로 내보내기 | 클라이언트 상세 페이지 액션 버튼 |
| `UpdateReviewUploadReportAction` | MongoDB 업로드 상태 재집계 | 클라이언트 상세 페이지 액션 버튼 |
| `ClearUploadReadyState` | MongoDB review_upload_target_list에서 'ready' 상태 문서 일괄 삭제 | 클라이언트 상세 페이지 액션 버튼 |

### 아키텍처

```
SVGW API (auth:sanctum)
  Route::prefix('review')
    POST /driver-configs/{id}/actions/clear-last-crawled-date
    POST /driver-configs/{id}/actions/collect-reviews
    POST /driver-configs/{id}/actions/run-periodic-ecs
    POST /driver-configs/{id}/actions/run-widget-ecs
    POST /driver-configs/{id}/actions/unlock-soldout
    POST /driver-configs/{id}/actions/delete-zz-express
    POST /driver-configs/{id}/actions/update-last-crawled-date
    POST /clients/{id}/actions/bulk-update-monthly-state  (body: {ids[], state})
    POST /clients/{id}/actions/imweb-excel-export
    POST /clients/{id}/actions/update-upload-report
    POST /clients/{id}/actions/clear-upload-ready-state
```

### 컴포넌트 설계

#### 백엔드: DriverConfigActionController
`app/Http/Controllers/Review/DriverConfigActionController.php`

- `clearLastCrawledDate(DriverConfig $driverConfig)` — DriverConfig/Target/TargetItemMap의 last_crawled_date null 처리 (트랜잭션)
- `collectReviews(DriverConfig $driverConfig)` — `RegleEcsService::collectReviewsByDriverConfig()` 호출
- `runPeriodicEcs(DriverConfig $driverConfig)` — `RegleEcsService::runPeriodicTask()` 호출
- `runWidgetEcs(DriverConfig $driverConfig)` — `RegleEcsService::runWidgetTask()` 호출
- `unlockSoldout(DriverConfig $driverConfig)` — target_option에서 `status: not_for_sale` 제거
- `deleteZzExpress(DriverConfig $driverConfig)` — zz_express Target + TargetItemMap 일괄 삭제
- `updateLastCrawledDate(DriverConfig $driverConfig)` — Target 중 최신 last_crawled_date → DriverConfig JSON 업데이트

#### 백엔드: ClientActionController
`app/Http/Controllers/Review/ClientActionController.php`

- `bulkUpdateMonthlyState(Request $request)` — `{ids[], state: 'Y'|'N'}` 수신, Client + 연관 DriverConfig 일괄 업데이트
- `imwebExcelExport(Client $client)` — MongoDB standard_review_target에서 리뷰 조회 → Excel 생성 + 이미지 Zip → S3 업로드 → XlsFile 레코드 생성 → 다운로드 URL 반환
- `updateUploadReport(Client $client)` — MongoDB review_upload_target_list 상태 집계 → ReviewUploadReport 갱신
- `clearUploadReadyState(Client $client)` — MongoDB ready 상태 문서 삭제 후 집계 갱신

#### 프론트엔드
- 기존 드라이버 상세 페이지(`/review/download-driver/{id}`)에 액션 버튼 그룹 추가
- 기존 클라이언트 목록(`/review/client`)에 일괄 액션 체크박스 + BulkUpdateMonthlyState 추가
- 기존 클라이언트 상세 페이지에 액션 버튼 추가

### 에러 처리

| 상황 | 처리 방식 |
|------|----------|
| ECS 태스크 실행 실패 | HTTP 422 + 에러 메시지 |
| MongoDB 연결 실패 | HTTP 503 + 에러 메시지 |
| ImWeb Excel 생성 중 이미지 다운로드 실패 | 해당 이미지 skip, 나머지 계속 진행 |
| BulkUpdateMonthlyState 일부 실패 | 성공/실패 건수 함께 반환 |

### 테스트

- `DriverConfigActionControllerTest` — 각 액션 401 인증 테스트 + 정상 동작 확인
- `ClientActionControllerTest` — 각 액션 401 인증 테스트 + 정상 동작 확인

### sv-nova-master 처리
완료 후 해당 Actions에 `$displayInNavigation = false` 처리 또는 Nova Resource에서 actions() 반환 배열에서 제거

---

## Phase 6 — Target 액션 + 모니터링 리소스 이관

### 범위

#### Target/TargetItemMap 페이지 액션
| Nova Action | 역할 | SVGW 구현 위치 |
|-------------|------|----------------|
| `ClearTargetItemTitle` | Target 상품명(name) + is_name_checked 초기화 | 매핑 관리 페이지 액션 |
| `GenerateSimilarity` | TargetItemMap 상품명 유사도 계산 후 저장 | 매핑 관리 페이지 액션 |
| `DeleteZzExpressTargets` | Zigzag 직진배송 Target 삭제 + TargetItemMap 삭제 | 매핑 관리 페이지 액션 |
| `SyncZzFulfillmentType` | Zigzag API에서 배송 유형(직진/일반) 조회 → target_option 동기화 | 드라이버 상세 페이지 액션 |
| `InstantRetryReviewUpload` | 자동 이관 날짜 범위 내이면 PeriodicReviewCrawling Job 즉시 실행 | LastCrawlingDate 화면 액션 |
| `ExportToExcel` / `DownloadExcel` | 선택 항목 Excel 내보내기 | 각 관련 페이지 |
| `CollectImageInfoByDriverConfig` | 리뷰 이미지 메타데이터 수집 | 드라이버 상세 페이지 액션 |
| `FetchLastCrawlingDate` | MongoDB에서 마지막 크롤링 날짜 조회/갱신 | LastCrawlingDate 화면 액션 |

#### 신규 모니터링 리소스 페이지
| Nova Resource | 역할 | SVGW 대상 경로 |
|---------------|------|----------------|
| `LastCrawlingDate` | 클라이언트/드라이버별 크롤링 일시 + 업로드 상태 모니터링 | `/review/crawling-status` |
| `ReviewImagesResource` | 리뷰 이미지 URL/크기/타입 메타데이터 조회 | `/admin/review-images` |
| `XlsFile` | 생성된 Excel/Zip 파일 목록 및 다운로드 | `/admin/xls-files` |
| `ClientReportResource` | 클라이언트별 업로드 리포트 상세 | `/review/client-reports` |

### 핵심 컴포넌트

#### `/review/crawling-status` 페이지
- LastCrawlingDate 모델 기반 (sv_nova DB)
- 필터: client, monthly_state, 날짜 범위
- 컬럼: 클라이언트명, 드라이버명, 마지막 크롤링일, 업로드 상태, API 상태
- 액션: FetchLastCrawlingDate (단건 갱신), InstantRetryReviewUpload (즉시 재시도)

#### Excel 내보내기 공통 패턴
- S3에 파일 저장 + XlsFile 레코드 생성 → pre-signed URL 반환
- 프론트엔드에서 URL로 직접 다운로드

---

## Phase 7 — sv-nova-master 제거

**전제 조건:** Phase 5~6 완료 + 운영팀 검증 완료

### 절차

1. **사용 현황 파악** — 그룹웨어 사용자들의 sv-nova-master 실제 접속 로그 확인
2. **접근 차단** — nginx에서 sv-nova-master 도메인(`sv-nova-master.seoul.ventures`) 503 반환으로 전환
3. **모니터링 기간** — 최소 2주, 문의/이슈 없으면 다음 단계 진행
4. **스케줄러 확인** — sv-nova-master의 남은 스케줄 (`report:send-notification`) 중단 확인
5. **서브모듈 제거** — `regle-mono`에서 `sv-nova-master` 서브모듈 제거 또는 아카이브
6. **인프라 정리** — EC2 배포 디렉토리 정리, GitHub Actions 워크플로우 비활성화
7. **라이선스 해지 검토** — Nova 4 + Filament 3 라이선스

### 완료 기준
- sv-nova-master 트래픽 0 확인
- SVGW에서 동등 기능 모두 정상 동작 확인
- 운영팀 최종 승인

---

## 변경 파일 요약

### Phase 5 (SVGW)
| 파일 | 작업 |
|------|------|
| `app/Http/Controllers/Review/DriverConfigActionController.php` | 신규 |
| `app/Http/Controllers/Review/ClientActionController.php` | 신규 |
| `routes/api.php` | 액션 라우트 추가 |
| `frontend/resources/ts/pages/review/download-driver/[id].vue` | 액션 버튼 추가 |
| `frontend/resources/ts/pages/review/client/index.vue` | BulkUpdateMonthlyState 추가 |
| `frontend/resources/ts/pages/review/client/[id].vue` | 클라이언트 액션 버튼 추가 |
| `tests/Feature/Review/DriverConfigActionControllerTest.php` | 신규 |
| `tests/Feature/Review/ClientActionControllerTest.php` | 신규 |

### Phase 6 (SVGW)
| 파일 | 작업 |
|------|------|
| `app/Http/Controllers/Review/CrawlingStatusController.php` | 신규 |
| `app/Http/Controllers/Admin/ReviewImageController.php` | 신규 |
| `app/Http/Controllers/Admin/XlsFileController.php` | 신규 |
| `app/Models/LastCrawlingDate.php` | 신규 |
| `app/Models/ReviewImage.php` | 신규 |
| `app/Models/XlsFile.php` | 신규 |
| `frontend/resources/ts/pages/review/crawling-status/index.vue` | 신규 |
| `frontend/resources/ts/pages/admin/review-images/index.vue` | 신규 |
| `frontend/resources/ts/pages/admin/xls-files/index.vue` | 신규 |

---

## 리스크

| 리스크 | 완화 방안 |
|--------|----------|
| ImWeb Excel 생성 시 이미지 수가 많아 타임아웃 | Queue Job으로 비동기 처리, 완료 시 알림 |
| BulkUpdateMonthlyState 대량 업데이트 시 DB 부하 | chunk() 처리, 500건 단위 |
| LastCrawlingDate 크롤링 모니터링 데이터 량 과다 | 페이지네이션 + 날짜 필터 기본 적용 |
| sv-nova-master 제거 후 누락 기능 발견 | Phase 5~6 완료 후 2주 병행 운영 후 제거 |
| NotificationSetting 스케줄 중단 | 미완성 기능이므로 실제 발송 없음, 중단해도 무방 |

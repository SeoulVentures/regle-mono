# sv-nova-master → SeoulVenturesGroupware 마이그레이션 설계

**작성일:** 2026-02-20
**대상 리포:** regle-mono (서브모듈: sv-nova-master, SeoulVenturesGroupware)
**목표:** sv-nova-master의 모든 기능을 SeoulVenturesGroupware(SVGW)로 점진적 이관 후 sv-nova-master 제거

---

## 배경

sv-nova-master는 Laravel 10 + Nova + Filament 기반의 리뷰 관리 시스템이다.
SeoulVenturesGroupware는 Laravel 12 + Vue 3 + Vuetify 3 기반으로, 이미 대부분의 CRUD 기능이 이관되어 있다.
남은 기능(통계 대시보드, 일일 리포트, 알림톡 설정, 운영 도구)을 순차 이관하여 sv-nova-master의 역할을 제거한다.

---

## 현황 분석

### SVGW에 이미 존재하는 기능
| 기능 | SVGW 위치 |
|------|-----------|
| 고객사(Client) CRUD | `/review/client/*` |
| 드라이버 설정 (Download/Upload) | `/review/download-driver`, `/review/upload-driver` |
| 매핑 관리 (TargetItemMap) | `/review/mapping-manager` |
| 자동 이관 | `/review/auto-migration*` |
| 업로드 리포트 | `/review/upload-summary`, `/review/upload` |
| 스캔 관리 | `/review/scan`, `/review/scanner` |
| 이메일 템플릿 | `/regle/email-templates` |
| 알림 로그 | `/regle/notification-logs` |
| 크레마 브랜드 | `/review/crema-brands` |
| 에러 통계 | `/review/error-stats` |
| 견적 | `/review/estimates` |
| 태스크 | `/review/tasks` |
| 이미지 사이즈 | `/review/image-size` |
| 데이터 관리 | `/review/data` |

### 이관 대상 (SVGW에 없는 기능)
| 기능 | sv-nova-master 위치 | 사용 빈도 |
|------|-------------------|---------|
| 통계 대시보드 | Nova Widgets + ReviewReportDashboard | 높음 |
| 일일 리포트 관리 | DailyReport, DailyClientStatistic, DailyDriverStatistic | 높음 |
| 알림톡(카카오) 설정 | NotificationSetting Nova Resource | 중간 |
| NaverXls 파일 임포트 | NaverXlsFileResource + ImportNaverXlsFile Action | 중간 |
| Job 큐 모니터링 | JobResource | 중간 |
| CfClearance 관리 | Nova Resource | 낮음 |
| ReviewApiUser 관리 | Nova Resource | 낮음 |
| IssueCase 관리 | Nova Resource | 낮음 |
| MongoDB 리뷰 직접 조회 | Filament MongoDBReviews, ReviewManagement | 낮음 |

---

## 마이그레이션 전략: 사용자 가치 순서 기반 점진적 이관

### Phase 1 — 통계 대시보드

**목표:** 운영팀이 가장 자주 참조하는 리뷰 통계 화면을 SVGW로 이관

**이관 대상:**
- ReviewsCollectionChart (수집량 추이)
- ClientsDistributionChart (클라이언트별 분포)
- DriversDistributionChart (드라이버별 분포)
- SuccessRateChart (성공률 추이)
- ReviewTrendChart (리뷰 트렌드)
- Metrics: TodayReviewsCount, WeeklyReviewsCount, MonthlyReviewsCount, ActiveClientsCount, TotalClientsCount

**SVGW 구현:**
- `/dashboard` 페이지를 리뷰 통계 대시보드로 교체
- ApexCharts 기반 차트 컴포넌트 구현
- 날짜 범위 필터 (시작일/종료일)
- 백엔드: `StatisticsController` 확장 또는 신규 `DashboardController` 추가

**완료 기준:**
- SVGW 대시보드에서 sv-nova-master ReviewReportDashboard의 모든 차트 확인 가능
- 날짜 필터 동작 확인

---

### Phase 2 — 일일 리포트 관리

**목표:** 날짜별 수집 통계 리포트 조회 및 관리 기능 이관

**이관 대상:**
- DailyReport Nova Resource (날짜별 리포트 목록)
- DailyClientStatistic Nova Resource (클라이언트별 일일 통계)
- DailyDriverStatistic Nova Resource (드라이버별 일일 통계)
- GenerateDailyReport Action (리포트 수동 생성)
- BulkGenerateReports Action (일괄 생성)

**SVGW 구현:**
- 신규 페이지: `/review/daily-report`
- 날짜 선택 → 클라이언트별/드라이버별 통계 테이블
- 리포트 수동 생성 버튼 (관리자 권한)
- 백엔드: `DailyReportController` 신규 추가

**완료 기준:**
- 날짜별 리포트 조회 가능
- 리포트 수동 생성 트리거 동작 확인

---

### Phase 3 — 알림톡 설정 + NaverXls 임포트

**목표:** 카카오 알림톡 수신자 설정과 NaverXls 파일 처리 기능 이관

**이관 대상 (알림톡):**
- NotificationSetting Nova Resource
  - 수신자 목록 관리 (추가/삭제)
  - 발송 시간 설정
  - 활성화/비활성화 토글

**이관 대상 (NaverXls):**
- NaverXlsFileResource
- ImportNaverXlsFile Action (파일 업로드 → ECS 임포트 트리거)

**SVGW 구현:**
- `/settings/notification` — 알림톡 설정 페이지
- `/review/naver-xls` — NaverXls 파일 임포트 페이지
- 백엔드: `NotificationSettingController`, `NaverXlsController` 신규 추가

**완료 기준:**
- 알림톡 수신자 추가/삭제/설정 동작 확인
- NaverXls 파일 업로드 및 임포트 트리거 확인

---

### Phase 4 — 운영 도구류

**목표:** 드물게 사용하는 관리자 운영 도구 이관

**이관 대상:**
- JobResource (백그라운드 작업 큐 상태 모니터링)
- CfClearance (CF Clearance 관리)
- ReviewApiUser (API 사용자 관리)
- IssueCase (이슈 케이스 관리)
- MongoDB 리뷰 직접 조회 (Filament MongoDBReviews)

**SVGW 구현:**
- `/admin/jobs` — Job 큐 모니터링
- `/admin/cf-clearance` — CfClearance 관리
- `/admin/api-users` — API 사용자 관리
- `/admin/issues` — 이슈 케이스 관리
- 백엔드: `Admin` 네임스페이스 컨트롤러 신규 추가

**완료 기준:**
- 각 관리 페이지에서 데이터 조회/수정 가능
- 기존 Nova/Filament 기능과 동등한 수준

---

### Phase 5 — sv-nova-master 제거

**전제 조건:** Phase 1~4 완료 및 운영 팀 검증 완료

**작업:**
1. sv-nova-master 접근 차단 (nginx/ALB 레벨 차단)
2. 일정 기간(2주~1개월) 모니터링
3. Nova/Filament 라이선스 해지 검토
4. sv-nova-master 서브모듈 제거 또는 아카이브
5. 관련 인프라 정리 (ECS 태스크 정의 중 sv-nova-master 전용 항목)

**완료 기준:**
- SVGW에서 모든 기능 정상 동작 확인
- sv-nova-master 트래픽 0 확인 후 제거

---

## 기술 스택 고려사항

| 항목 | sv-nova-master | SVGW |
|------|----------------|------|
| 백엔드 | Laravel 10 + Nova 4 + Filament 3 | Laravel 12 |
| 프론트엔드 | React + Inertia.js + Tailwind | Vue 3 + Vuetify 3 + TypeScript |
| 차트 | ApexCharts | ApexCharts (동일) |
| 인증 | Session | JWT |
| 패키지 매니저 | pnpm | bun |

---

## 리스크 및 완화 방안

| 리스크 | 완화 방안 |
|--------|---------|
| Nova 전용 UI 기능 재현 어려움 | Vuetify 컴포넌트로 동등 수준 구현, 필요시 단순화 수용 |
| 백엔드 API 미비 | Phase별로 필요한 API 먼저 추가 후 프론트 구현 |
| 운영팀 사용 패턴 파악 부족 | Phase 완료 시마다 운영팀 UAT 진행 |
| sv-nova-master 조기 제거로 인한 공백 | Phase 5는 모든 팀 확인 후에만 진행 |

# sv-nova-master 마이그레이션 Phase 2 설계 — 일일 리포트 생성 이관

**작성일:** 2026-02-20
**대상 리포:** regle-mono (서브모듈: sv-nova-master, SeoulVenturesGroupware)
**목표:** `report:generate-daily` 명령어와 관련 서비스를 SVGW로 이관하고, sv-nova-master의 스케줄러에서 즉시 제거

---

## 범위

### 이관 대상
- `report:generate-daily` Artisan 명령어 (스케줄: 매일 03:00)
- `ReviewDataCollectionService` — MongoDB에서 클라이언트별 업로드 통계 집계
- `ReportGenerationService` — daily_reports / daily_client_statistics / daily_driver_statistics 생성

### 제외 (Phase 3에서 처리)
- `report:send-notification` (카카오 알림톡 발송)
- `NotificationSetting` 관련 기능

---

## 아키텍처

```
Kernel::schedule (03:00)
  → GenerateDailyReportCommand
    → ReportGenerationService
      → ReviewDataCollectionService
          → MongoDBConnection::getConnectionFor(client)       ← 기존 서비스
          → MongoDBCollectionResolver::resolveStandardReview()     ← 확장
          → MongoDBCollectionResolver::resolveUploadStatus()       ← 확장
          → MongoDB aggregate pipeline
      → DailyReport / DailyClientStatistic / DailyDriverStatistic 쓰기
          → sv_nova DB (마스터 연결)
      → 실패 시 Slack::notify()
```

---

## 컴포넌트 설계

### 1. MongoDBCollectionResolver 확장

기존 `resolve(DriverConfig)` 메서드에 리포트용 컬렉션 이름 반환 메서드 추가:

```php
// 리뷰 표준화 데이터 컬렉션
public function resolveStandardReview(): string
{
    return 'standard_review_target';
}

// 업로드 상태 컬렉션
public function resolveUploadStatus(): string
{
    return 'review_upload_target_list';
}
```

### 2. ReviewDataCollectionService (신규)

`app/Services/Report/ReviewDataCollectionService.php`

- `MongoDBConnection` + 확장된 `MongoDBCollectionResolver` 주입
- `collectAllClientsData(Carbon $date): array` — 활성 클라이언트 전체 순회
- `collectClientData(Client $client, Carbon $date): array` — 클라이언트별 집계
- `generateDriverStats(...)` — MongoDB aggregate pipeline 실행
  - `standard_review_target`과 `review_upload_target_list` lookup + unwind + match + group
  - finished / failed / pending / skipped 상태별 카운트

sv-nova-master의 집계 파이프라인 로직을 그대로 이식하되, `MongoDBConnectionManager` 대신 SVGW의 `MongoDBConnection`을 사용.

### 3. ReportGenerationService (신규)

`app/Services/Report/ReportGenerationService.php`

- `ReviewDataCollectionService` 주입
- `generateDailyReport(Carbon $date, bool $forceRebuild = false): ?DailyReport`
  - 기존 리포트 존재 시 skip 또는 forceRebuild
  - DB transaction: DailyReport → DailyClientStatistic → DailyDriverStatistic 순서로 생성
  - `sv_nova` 마스터 연결 사용 (read/write 분리 설정 활용)
- `checkReportExists(Carbon $date): bool`

### 4. GenerateDailyReportCommand (신규)

`app/Console/Commands/GenerateDailyReportCommand.php`

```
php artisan report:generate-daily {date? : Y-m-d} {--force}
```

- 날짜 미지정 시 어제 날짜 사용
- `ReportGenerationService` 위임
- 실패(Exception 또는 null 반환) 시 Slack 알림

**Slack 알림 형식:**
```
❌ 일일 리포트 생성 실패
날짜: 2026-02-20
오류: {message}
서버: groupware.seoulventures.net
```

환경변수: 기존 `SLACK_WEBHOOK` 재활용

### 5. 스케줄러 변경

**SVGW `app/Console/Kernel.php` 추가:**
```php
$schedule->command('report:generate-daily')
    ->dailyAt('03:00')
    ->withoutOverlapping()
    ->appendOutputTo(storage_path('logs/daily-report-generation.log'));
```

**sv-nova-master `app/Console/Kernel.php` 제거:**
```php
// 아래 블록 삭제
$schedule->command('report:generate-daily')
    ->dailyAt('03:00')
    ->withoutOverlapping()
    ->appendOutputTo(storage_path('logs/daily-report-generation.log'));
```

---

## 에러 처리

| 상황 | 처리 방식 |
|------|-----------|
| MongoDB 연결 실패 | 예외 catch → Slack 알림 → Command::FAILURE |
| 특정 클라이언트 집계 실패 | 로그 기록 후 해당 클라이언트 skip, 나머지 계속 진행 |
| DB 트랜잭션 실패 | 롤백 → Slack 알림 → Command::FAILURE |
| 이관 건수 0 (forceRebuild 아닌 경우) | 리포트 생성 skip (정상 처리) |

---

## 테스트

`tests/Feature/GenerateDailyReportCommandTest.php`

- `report:generate-daily` 실행 시 DailyReport 생성 확인 (MongoDB mock)
- `--force` 옵션으로 기존 리포트 재생성 확인
- 날짜 미지정 시 어제 날짜 사용 확인
- 실패 시 Slack 알림 전송 확인 (Http::fake)

---

## 변경 파일 목록

| 파일 | 작업 |
|------|------|
| `app/Services/MongoDB/MongoDBCollectionResolver.php` | `resolveStandardReview()`, `resolveUploadStatus()` 추가 |
| `app/Services/Report/ReviewDataCollectionService.php` | 신규 |
| `app/Services/Report/ReportGenerationService.php` | 신규 |
| `app/Console/Commands/GenerateDailyReportCommand.php` | 신규 |
| `app/Console/Kernel.php` | `report:generate-daily` 03:00 등록 |
| `tests/Feature/GenerateDailyReportCommandTest.php` | 신규 |
| `sv-nova-master/app/Console/Kernel.php` | `report:generate-daily` 스케줄 제거 |

---

## 리스크

| 리스크 | 완화 방안 |
|--------|-----------|
| MongoDB 집계 파이프라인 동작 불일치 | sv-nova-master 파이프라인을 그대로 이식, 결과값 비교 테스트 |
| sv_nova 마스터 연결 권한 부족 | 사전에 INSERT/UPDATE 권한 확인 |
| 스케줄러 중복 실행 (이관 당일) | sv-nova-master 먼저 제거 후 SVGW 배포 순서 준수 |

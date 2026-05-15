# PostgreSQL 데이터베이스 통합 설계

## 1. 개요

retaku_admin, sv-nova-master, SeoulVenturesGroupware(SVGW)의 MySQL 3개 + MongoDB를 단일 PostgreSQL 인스턴스로 통합한다.

**제외 대상**: regle-universe, specto-admin, regle-co-kr (현행 MySQL 유지)

## 2. 핵심 결정사항

| 항목 | 결정 |
|------|------|
| 타겟 DB | PostgreSQL 단일 인스턴스 |
| 스키마 구조 | 단일 스키마 (public), 테이블 네이밍으로 구분 |
| 테이블 충돌 | SVGW 정본, sv-nova-master 중복 테이블 제거 |
| MongoDB | PostgreSQL jsonb로 동시 통합 |
| 마이그레이션 | PostgreSQL용 새로 작성 |
| 전환 방식 | 클린 컷오버 (프로젝트당 짧은 다운타임) |
| 전환 순서 | SVGW → sv-nova-master → retaku_admin |

## 3. 통합 테이블 목록

### 3.1 SVGW 고유 테이블 (17개)

| 테이블명 | 용도 |
|----------|------|
| users | 사용자 (SVGW 정본) |
| failed_jobs | 실패 작업 (Laravel 표준) |
| personal_access_tokens | 개인 액세스 토큰 |
| password_resets | 비밀번호 재설정 |
| oauth_access_tokens | OAuth 액세스 토큰 |
| oauth_authorization_codes | OAuth 인증 코드 |
| oauth_clients | OAuth 클라이언트 |
| oauth_refresh_tokens | OAuth 리프레시 토큰 |
| conferences | 회의실 예약 |
| cdn_campaigns | CDN 캠페인 |
| hyper_speed_clients | HyperSpeed 고객사 |
| estimates | 견적 |
| mcp_api_keys | MCP API 키 |
| regle_email_templates | 이메일 템플릿 |
| regle_email_template_attachments | 이메일 첨부파일 |
| notification_logs | 알림 로그 |
| daily_reports | 일일 리포트 |

### 3.2 SVGW 정본 (sv-nova-master 중복 제거 대상, 7개)

sv-nova-master에도 존재하지만 SVGW 스키마를 정본으로 사용한다.

| 테이블명 | SVGW 스키마 기준 | sv-nova-master 처리 |
|----------|-----------------|-------------------|
| users | SVGW 정본 | 제거, SVGW users 참조 |
| failed_jobs | SVGW 정본 | 제거 |
| personal_access_tokens | SVGW 정본 | 제거 |
| daily_client_statistics | SVGW 정본 (unsignedBigInteger) | 제거 |
| daily_driver_statistics | SVGW 정본 | 제거 |
| review_upload_reports | SVGW 정본 | 제거 |
| xls_files | SVGW 정본 | 제거 |

### 3.3 sv-nova-master 고유 테이블 (16개)

| 테이블명 | 용도 |
|----------|------|
| action_events | Nova 액션 이벤트 로그 |
| cf_clearances | CloudFlare 클리어런스 |
| client_crema_brand | 고객사-CREMA 매핑 |
| client_reports | 고객사별 리포트 |
| crema_brands | CREMA 브랜드 |
| driver_config_reports | 드라이버 설정 리포트 |
| exports | 데이터 내보내기 |
| failed_import_rows | 실패 임포트 행 |
| imports | 데이터 임포트 |
| import_naver_xls_files | 네이버 XLS 임포트 |
| jobs | Laravel 큐 작업 |
| last_crawling_dates | 마지막 크롤링 날짜 |
| naver_xls_files | 네이버 XLS 파일 |
| notification_settings | 알림 설정 |
| nova_field_attachments | Nova 첨부파일 |
| nova_notifications | Nova 알림 |
| nova_pending_field_attachments | Nova 대기 첨부파일 |
| periodic_regle_batch_logs | 주기적 배치 로그 |
| review_images | 리뷰 이미지 |
| issue_cases | 이슈 케이스 |
| password_reset_tokens | 비밀번호 재설정 토큰 |

### 3.4 retaku_admin 테이블 (9개)

| 테이블명 | 용도 |
|----------|------|
| review_clients | 고객사 |
| review_targets | 리뷰 대상 |
| review_drivers | 크롤링 드라이버 |
| review_driver_configs | 드라이버 설정 |
| review_target_item_map | 타겟-아이템 매핑 |
| review_client_items | 고객사 아이템 |
| review_upload_drivers | 업로드 드라이버 |
| review_api_users | 리뷰 API 사용자 |

> 참고: retaku_admin에는 다른 프로젝트(regle-universe 등)도 접근할 수 있으나, 이 통합에서는 sv-nova-master와 SVGW가 참조하는 테이블만 이관한다. regle-universe의 retaku_admin 접근은 별도 검토 필요.

### 3.5 MongoDB → PostgreSQL jsonb 전환 (3개 테이블)

| 기존 컬렉션 | 새 테이블명 | 프로젝트 | 핵심 필드 |
|------------|-----------|---------|----------|
| standard_review_target | standard_review_targets | sv-nova-master | id(bigserial), data(jsonb), hash_key(varchar, indexed), crawling_date(timestamp), created_at, updated_at, deleted_at |
| review_upload_target_list | review_upload_target_lists | SVGW | id(bigserial), data(jsonb), created_at, updated_at |
| unified_error_log | unified_error_logs | SVGW | id(bigserial), metadata(jsonb), created_at |

**jsonb 설계 원칙**:
- 자주 조회/필터하는 필드는 정규 컬럼으로 추출 (hash_key, crawling_date 등)
- 나머지 가변 필드는 `data` jsonb 컬럼에 저장
- GIN 인덱스를 jsonb 컬럼에 적용

## 4. MySQL → PostgreSQL 주요 변환 사항

| MySQL | PostgreSQL | 비고 |
|-------|-----------|------|
| `AUTO_INCREMENT` | `BIGSERIAL` | Laravel에서 `id()` 사용 시 자동 |
| `UNSIGNED BIGINT` | `BIGINT` | PostgreSQL은 UNSIGNED 미지원 |
| `TINYINT(1)` | `BOOLEAN` | Laravel `boolean()` 사용 |
| `DATETIME` | `TIMESTAMP` | Laravel `timestamp()` 사용 |
| `JSON` | `JSONB` | 성능 우수, GIN 인덱스 가능 |
| `ENUM` | `VARCHAR` + CHECK | 또는 별도 enum type 생성 |
| `GROUP_CONCAT` | `STRING_AGG` | Raw 쿼리 수정 필요 |
| `IFNULL` | `COALESCE` | Raw 쿼리 수정 필요 |
| `LIMIT x, y` | `LIMIT y OFFSET x` | Eloquent 사용 시 자동 처리 |

## 5. 전환 단계

### Phase 1: SVGW 전환

**사전 준비 (다운타임 없음)**
1. PostgreSQL 인스턴스 프로비저닝
2. SVGW용 마이그레이션 파일 새로 작성 (17 + 3 MongoDB 테이블)
3. SVGW 코드에서 MySQL/MongoDB 전용 구문 → PostgreSQL 호환으로 수정
4. `config/database.php`에 `pgsql` 연결 추가, 테스트 환경에서 검증
5. 데이터 이관 스크립트 작성 (MySQL → PG, MongoDB → PG jsonb)

**컷오버 (다운타임)**
1. SVGW 서비스 중단
2. MySQL/MongoDB에서 최종 데이터 덤프
3. PostgreSQL로 데이터 이관 실행
4. SVGW `DB_CONNECTION=pgsql`로 전환, MongoDB 연결 제거
5. `sv_nova` 연결 → 기존 sv-nova-master MySQL을 임시 유지 (Phase 2까지)
6. `retaku_admin` 연결 → 기존 retaku_admin MySQL을 임시 유지 (Phase 3까지)
7. 서비스 재개 및 검증

### Phase 2: sv-nova-master 전환

**사전 준비**
1. sv-nova-master용 마이그레이션 파일 새로 작성 (고유 16개 + MongoDB 1개)
2. 중복 7개 테이블은 Phase 1에서 생성된 SVGW 테이블 재사용
3. sv-nova-master 모델의 `$connection` 속성 수정
4. Raw 쿼리의 MySQL 전용 함수 변환
5. SVGW의 `sv_nova` 연결을 PostgreSQL로 변경 (더 이상 MySQL 불필요)

**컷오버 (다운타임)**
1. sv-nova-master 서비스 중단
2. 고유 테이블 + standard_review_target 데이터 이관
3. `DB_CONNECTION=pgsql`로 전환, `retaku_admin` → 기존 MySQL 임시 유지
4. `mongodb` 연결 제거
5. 서비스 재개 및 검증

### Phase 3: retaku_admin 전환

**사전 준비**
1. retaku_admin 테이블 마이그레이션 새로 작성 (8개)
2. sv-nova-master, SVGW 모두 `retaku_admin` 연결을 PostgreSQL로 변경
3. **regle-universe의 retaku_admin 접근 검토** — 별도 MySQL 유지 또는 PG 전환 결정

**컷오버 (다운타임)**
1. sv-nova-master + SVGW 동시 중단 (retaku_admin 공유)
2. retaku_admin 데이터 이관
3. 양쪽 프로젝트의 `retaku_admin` 연결을 PostgreSQL로 변경
4. 서비스 재개 및 검증
5. 기존 MySQL 인스턴스를 읽기 전용 백업으로 일정 기간 유지 후 폐기

## 6. 코드 변경 범위

### 6.1 config/database.php 변경 (각 프로젝트)

```php
// Before: 여러 MySQL + MongoDB 연결
'default' => env('DB_CONNECTION', 'mysql'),
'connections' => [
    'mysql' => [...],
    'retaku_admin' => [...],  // MySQL
    'mongodb' => [...],
]

// After: 단일 PostgreSQL (Phase 3 완료 후)
'default' => env('DB_CONNECTION', 'pgsql'),
'connections' => [
    'pgsql' => [
        'driver' => 'pgsql',
        'url' => env('DATABASE_URL'),
        'host' => env('DB_HOST', '127.0.0.1'),
        'port' => env('DB_PORT', '5432'),
        'database' => env('DB_DATABASE', 'regle'),
        'username' => env('DB_USERNAME', 'regle'),
        'password' => env('DB_PASSWORD', ''),
        'charset' => 'utf8',
        'prefix' => '',
        'prefix_indexes' => true,
        'search_path' => 'public',
        'sslmode' => 'prefer',
    ],
]
```

### 6.2 모델 변경

- `$connection = 'retaku_admin'` → 제거 (단일 DB이므로 기본 연결 사용)
- `$connection = 'mongodb'` → 제거, Eloquent 표준 모델로 전환
- `$connection = 'sv_nova'` (SVGW) → 제거
- MongoDB 모델: `Jenssegers\Mongodb\Eloquent\Model` → `Illuminate\Database\Eloquent\Model`

### 6.3 Raw 쿼리 수정

MySQL 전용 함수를 사용하는 Raw 쿼리를 PostgreSQL 호환으로 수정 필요. 사전에 전체 코드베이스에서 아래 패턴을 검색:
- `DB::raw(`, `DB::select(`, `DB::statement(`
- `->selectRaw(`, `->whereRaw(`, `->orderByRaw(`
- `GROUP_CONCAT`, `IFNULL`, `IF(`, `DATE_FORMAT`, `UNIX_TIMESTAMP`

### 6.4 의존성 변경

```
# 제거
jenssegers/mongodb

# 추가 (이미 Laravel에 포함)
# PostgreSQL PDO 드라이버만 서버에 설치 확인
# php-pgsql extension
```

## 7. 데이터 이관 전략

### 7.1 MySQL → PostgreSQL

```bash
# 1. MySQL 덤프 (스키마 제외, 데이터만)
mysqldump --no-create-info --compatible=postgresql DB_NAME > data.sql

# 2. pgloader 사용 (자동 타입 변환)
pgloader mysql://user:pass@host/db postgresql://user:pass@host/db

# 또는 Laravel Seeder 기반 이관 스크립트 (데이터 정합성 검증 용이)
```

### 7.2 MongoDB → PostgreSQL

```php
// 이관 스크립트 (Artisan Command)
// MongoDB에서 읽어서 PostgreSQL jsonb로 변환 삽입
// chunk 단위 처리 (메모리 관리)
```

### 7.3 데이터 검증

각 Phase 컷오버 후:
- 테이블별 행 수 비교 (MySQL/MongoDB vs PostgreSQL)
- 샘플 데이터 무결성 검증
- FK 관계 정합성 확인

## 8. 리스크 및 대응

| 리스크 | 영향 | 대응 |
|--------|------|------|
| retaku_admin을 regle-universe도 참조 | Phase 3에서 regle-universe 영향 | 별도 MySQL 유지 또는 regle-universe도 PG 전환 검토 |
| Raw 쿼리 호환성 | 런타임 오류 | 사전 코드 검색 + 테스트 커버리지 확보 |
| MongoDB jsonb 쿼리 성능 | standard_review_target 대용량 | GIN 인덱스 + 자주 쿼리하는 필드 정규 컬럼 추출 |
| 데이터 이관 시간 초과 | 다운타임 연장 | 사전 리허설, 대용량 테이블 병렬 이관 |
| UNSIGNED 제거로 인한 음수값 유입 | 데이터 무결성 | CHECK 제약조건 추가 (필요한 컬럼만) |

## 9. 최종 아키텍처

```
전환 전:
┌─────────────┐  ┌──────────────┐  ┌─────────┐  ┌─────────┐
│ MySQL:       │  │ MySQL:        │  │ MySQL:   │  │ MongoDB │
│ sv_nova_     │  │ retaku_admin  │  │ svgw     │  │         │
│ master       │  │ (공유)        │  │          │  │         │
└─────────────┘  └──────────────┘  └─────────┘  └─────────┘

전환 후:
┌──────────────────────────────────────────────────────┐
│ PostgreSQL: regle                                     │
│                                                       │
│ ┌──────────┐ ┌───────────┐ ┌────────┐ ┌───────────┐ │
│ │ sv-nova  │ │ retaku_   │ │ svgw   │ │ jsonb     │ │
│ │ 고유     │ │ admin     │ │ 고유   │ │ (MongoDB  │ │
│ │ 테이블   │ │ 테이블    │ │ 테이블 │ │  이관)    │ │
│ └──────────┘ └───────────┘ └────────┘ └───────────┘ │
│                                                       │
│ ┌──────────────────────────────────────────────────┐ │
│ │ 공유 테이블 (SVGW 정본)                          │ │
│ │ users, failed_jobs, xls_files, daily_* 등        │ │
│ └──────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────┘
```

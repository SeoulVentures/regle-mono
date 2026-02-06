---
name: fix
description: Fix errors using FixHive knowledge base
disable-model-invocation: true
---


FixHive를 활용한 오류 해결 마법입니다.

---

## Usage

```
/cast:fix                          # 현재 에러 해결
/cast:fix --error="error message"  # 특정 에러 해결
/cast:fix --from-analysis          # /cast:analyze 결과 기반 수정
/cast:fix --issue=SEC-001          # 특정 이슈 수정
```

---

## 1. Overview

FixHive는 커뮤니티 기반 오류 해결 지식베이스입니다.
Archmage는 에러 발생 시 FixHive를 우선 검색하여 기존 해결책을 활용합니다.

```
┌─────────────────────────────────────────────────────────────┐
│                    ERROR RESOLUTION                          │
│                                                              │
│   Error Detected                                             │
│     │                                                        │
│     ▼                                                        │
│   ┌───────────────────────────────────────────────────┐     │
│   │               FIXHIVE SEARCH                       │     │
│   │   ┌─────────────────────────────────────────┐     │     │
│   │   │      Community Knowledge Base            │     │     │
│   │   │   ┌─────────┐ ┌─────────┐ ┌─────────┐  │     │     │
│   │   │   │ Error   │ │Solution │ │ Context │  │     │     │
│   │   │   │ Pattern │ │  Code   │ │  Match  │  │     │     │
│   │   │   └─────────┘ └─────────┘ └─────────┘  │     │     │
│   │   └─────────────────────────────────────────┘     │     │
│   └───────────────────────────────────────────────────┘     │
│     │                                                        │
│     ├── Found → Apply Solution                              │
│     │                                                        │
│     └── Not Found → Gemini + Codex                          │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. Workflow

```
에러 발생
    │
    ▼
┌─────────────────────────────────┐
│ Step 1: FixHive 검색             │
│ - 에러 메시지 기반 검색          │
│ - 기술 스택 필터링               │
│ - 유사 케이스 조회               │
└─────────────────────────────────┘
    │
    ├── 해결책 발견 ──────────────────┐
    │                                │
    │                                ▼
    │                    ┌─────────────────────┐
    │                    │ Step 2a: 해결책 적용 │
    │                    │ - 컨텍스트 확인      │
    │                    │ - 적용               │
    │                    │ - 검증               │
    │                    └─────────────────────┘
    │                                │
    │                                ▼
    │                    ┌─────────────────────┐
    │                    │ 성공 → 완료          │
    │                    │ 실패 → Step 2b로     │
    │                    └─────────────────────┘
    │
    └── 해결책 없음
            │
            ▼
    ┌─────────────────────────────────┐
    │ Step 2b: 분석 및 해결           │
    │                                  │
    │ 1. Gemini: 원인 분석             │
    │    - 에러 스택 분석               │
    │    - 근본 원인 식별               │
    │    - 해결 방향 제시               │
    │                                  │
    │ 2. Codex: 수정 구현               │
    │    - Gemini 분석 기반 수정        │
    │    - 테스트 코드 작성             │
    │                                  │
    │ 3. 검증                          │
    │    - 테스트 실행                  │
    │    - 에러 재현 확인               │
    └─────────────────────────────────┘
            │
            ▼
    ┌─────────────────────────────────┐
    │ Step 3: FixHive 등록 (선택)      │
    │ - 등록 가치 평가                 │
    │ - 해결책 문서화                  │
    │ - 커뮤니티 공유                  │
    └─────────────────────────────────┘
```

---

## 3. FixHive Search

### 3.1 Search Query Format

```json
{
  "error_type": "TypeError | SyntaxError | RuntimeError | ...",
  "error_message": "Cannot read property 'x' of undefined",
  "technology": ["TypeScript", "React", "Node.js"],
  "context": "optional additional context"
}
```

### 3.2 Search Result Evaluation

| Score | Action |
|-------|--------|
| High (>80%) | 직접 적용 시도 |
| Medium (50-80%) | 컨텍스트 확인 후 적용 |
| Low (<50%) | 참고만, 직접 분석 진행 |

---

## 4. FixHive Registration

### 4.1 Registration Criteria

등록 가치가 있는 케이스:
- 재발 가능성이 높은 오류
- 해결에 상당한 시간이 소요된 케이스
- 비자명한 해결 방법
- 커뮤니티에 도움이 될 수 있는 케이스

### 4.2 Registration Format

```json
{
  "title": "간결한 문제 설명",
  "error_type": "TypeError",
  "error_message": "정확한 에러 메시지",
  "technology": ["TypeScript", "React"],
  "root_cause": "원인 설명",
  "solution": {
    "description": "해결 방법 설명",
    "code_before": "문제가 있던 코드",
    "code_after": "수정된 코드"
  },
  "prevention": "향후 방지 방법"
}
```

---

## 5. Fix Modes

### 5.1 Auto Fix (Default)

```
> /cast:fix

🔧 Analyzing error...

Error: TypeError: Cannot read property 'map' of undefined
Location: src/components/UserList.tsx:23

🔍 Searching FixHive...
✓ Found solution (87% match)

Applying fix:
- Add null check before map
- Set default empty array

✓ Fix applied
✓ Tests passing

Done!
```

### 5.2 From Analysis (`--from-analysis`)

```
> /cast:fix --from-analysis

🔧 Reading analysis report...

Issues to fix:
1. [SEC-001] SQL Injection (Critical)
2. [PERF-001] N+1 Query (High)
3. [QUAL-001] Missing error handling (Medium)

Fix all? [Y/n/select]
```

### 5.3 Interactive (`--interactive`)

```
> /cast:fix --interactive

🔧 Interactive fix mode

Error detected:
TypeError: Cannot read property 'map' of undefined

Options:
[1] Add null check (recommended)
[2] Set default value in state
[3] Add loading state
[4] Custom fix

Select: 1

Applying fix...
✓ Done
```

---

## 6. Integration with Familiars

### Gemini Role
- 에러 스택 트레이스 분석
- 근본 원인 식별
- 해결 방향 제시 (코드 직접 수정 X)

### Codex Role
- Gemini 분석 기반 코드 수정
- 테스트 코드 작성
- 수정 검증

### Archmage Role
- 전체 워크플로우 조율
- FixHive 검색/등록 결정
- 최종 검증

---

## 7. Examples

### Example 1: Simple Error

```
> /cast:fix --error="TypeError: Cannot read property 'map' of undefined"

🔧 Analyzing error...

1. FixHive Search
   ✓ Found: "Array method on undefined" (92% match)

2. Applying Solution
   File: src/components/UserList.tsx

   Before:
   ```tsx
   return data.map(user => <UserCard user={user} />);
   ```

   After:
   ```tsx
   return (data ?? []).map(user => <UserCard user={user} />);
   ```

3. Verification
   ✓ TypeScript check passing
   ✓ Tests passing

✅ Fixed!
```

### Example 2: Complex Error

```
> /cast:fix --error="ECONNREFUSED 127.0.0.1:5432"

🔧 Analyzing error...

1. FixHive Search
   ⚠ Partial match found (45%)

2. Gemini Analysis
   Root cause: PostgreSQL service not running

   Possible solutions:
   a) Start PostgreSQL service
   b) Check connection string
   c) Verify Docker container status

3. Recommended Action
   This is an infrastructure issue, not a code issue.

   Try:
   ```bash
   # If using Docker
   docker-compose up -d postgres

   # If local installation
   sudo service postgresql start
   ```

No code changes required.
```

### Example 3: Security Fix

```
> /cast:fix --issue=SEC-001

🔧 Fixing SEC-001: SQL Injection

1. Issue Details
   File: src/api/users.ts:45
   Severity: Critical

2. Applying Fix
   Before:
   ```typescript
   const query = `SELECT * FROM users WHERE id = ${userId}`;
   ```

   After:
   ```typescript
   const query = 'SELECT * FROM users WHERE id = $1';
   const result = await db.query(query, [userId]);
   ```

3. Verification
   ✓ SQL injection test passing
   ✓ Unit tests passing
   ✓ /cast:analyze --security (re-scan clean)

4. FixHive Registration
   Register this solution? [Y/n]
   > Y
   ✓ Registered as FH-2026-0125-001

✅ SEC-001 Fixed!
```

---

## 8. Configuration

### 8.1 Fix Config

`runes/config/fix.yaml`:

```yaml
fix:
  auto_fix:
    enabled: true
    max_retries: 3
    require_tests: true

  fixhive:
    search_enabled: true
    min_match_score: 50
    auto_register: false  # Ask before registering

  verification:
    run_tests: true
    run_typecheck: true
    run_lint: true

  rollback:
    enabled: true
    on_test_failure: true
```

---

## 9. Metrics

| Metric | Target |
|--------|--------|
| FixHive Hit Rate | > 50% |
| First-time Resolution | > 70% |
| Registration Quality | > 4.0/5.0 |

---

## 10. Related Spells

| Spell | Description |
|-------|-------------|
| `/cast:analyze` | 사전 분석으로 이슈 발견 |
| `/cast:review` | 코드 리뷰 |
| `/cast:dev` | 전체 개발 워크플로우 |

---

*Version: 0.1.0*
*Last Updated: 2026-01-25*

---
name: review
description: Code review with design principles validation
disable-model-invocation: true
---


코드 변경 시 자동으로 리뷰하고 필요한 경우 수정까지 진행하는 자동화 마법입니다.

---

## Usage

```
/cast:review              # 현재 변경사항 리뷰
/cast:review --file=path  # 특정 파일 리뷰
/cast:review --pr=123     # 특정 PR 리뷰
/cast:review --auto-fix   # 자동 수정 활성화
```

---

## 1. Overview

Auto-Review Loop는 코드 품질을 자동으로 보장하는 피드백 루프입니다.

```
┌─────────────────────────────────────────────────────────────┐
│                    AUTO-REVIEW LOOP                          │
│                                                              │
│   Code Change                                                │
│       │                                                      │
│       ▼                                                      │
│   ┌─────────────────┐                                       │
│   │    Reviewer     │◄────────────────────┐                 │
│   │    Analysis     │                     │                 │
│   └────────┬────────┘                     │                 │
│            │                              │                 │
│      ┌─────┴─────┐                        │                 │
│      ▼           ▼                        │                 │
│  ┌───────┐  ┌─────────────┐              │                 │
│  │ Pass  │  │   Issues    │              │                 │
│  │       │  │   Found     │              │                 │
│  └───┬───┘  └──────┬──────┘              │                 │
│      │             │                      │                 │
│      ▼             ▼                      │                 │
│   Complete    ┌─────────────┐            │                 │
│              │   Severity   │            │                 │
│              │    Check     │            │                 │
│              └──────┬───────┘            │                 │
│                     │                     │                 │
│        ┌────────────┼────────────┐       │                 │
│        ▼            ▼            ▼       │                 │
│    ┌───────┐   ┌────────┐  ┌─────────┐  │                 │
│    │  Low  │   │ Medium │  │High/Crit│  │                 │
│    │ (Log) │   │(Notify)│  │ (Fix)   │  │                 │
│    └───────┘   └────────┘  └────┬────┘  │                 │
│                                  │       │                 │
│                                  ▼       │                 │
│                           ┌──────────┐   │                 │
│                           │  Codex   │   │                 │
│                           │  Fix     │───┘                 │
│                           └──────────┘                      │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. Trigger Conditions

### 2.1 Automatic Triggers

| Trigger | Description |
|---------|-------------|
| File Save | 파일 저장 시 (설정 가능) |
| Git Commit | 커밋 전/후 hook |
| PR Creation | Pull Request 생성 시 |
| PR Update | PR에 새 커밋 추가 시 |

### 2.2 Manual Triggers

```
/cast:review              # 현재 변경사항 리뷰
/cast:review --file=path  # 특정 파일 리뷰
/cast:review --pr=123     # 특정 PR 리뷰
```

---

## 3. Review Pipeline

### 3.1 Stage 1: Pre-Check (Automated)

```yaml
pre_check:
  - lint: true           # ESLint/Prettier
  - typecheck: true      # TypeScript
  - test: true           # Unit tests
  - build: true          # Build verification

  on_failure:
    action: block
    notify: true
```

### 3.2 Stage 2: Reviewer Analysis

```json
{
  "task_id": "auto-review-{timestamp}",
  "familiar": "reviewer",
  "action": "review",
  "context": {
    "changes": {
      "type": "diff",
      "files": ["changed files from git diff"]
    },
    "review_focus": [
      "solid_principles",
      "error_handling",
      "security",
      "naming"
    ],
    "max_issues": 20
  }
}
```

### 3.3 Stage 3: Severity-Based Routing

```
Review Result
     │
     ├── Critical (🔴)
     │   └── Action: BLOCK + AUTO-FIX
     │       ├── Codex: 즉시 수정
     │       ├── Re-review 필수
     │       └── 3회 실패 시 Human escalation
     │
     ├── High (🟠)
     │   └── Action: AUTO-FIX
     │       ├── Codex: 자동 수정
     │       └── Re-review
     │
     ├── Medium (🟡)
     │   └── Action: NOTIFY
     │       ├── 이슈 리포트 생성
     │       └── 수정 권고 (선택적)
     │
     └── Low (🟢)
         └── Action: LOG
             └── 기록만, 진행 허용
```

---

## 4. Auto-Fix Workflow

### 4.1 Fix Request to Codex

```json
{
  "task_id": "auto-fix-{timestamp}",
  "familiar": "codex",
  "action": "fix",
  "context": {
    "files": [
      {
        "path": "src/services/auth.ts",
        "content": "// current content"
      }
    ],
    "issues": [
      {
        "id": "REV-001",
        "severity": "high",
        "principle": "SRP",
        "location": { "line": 45, "function": "authenticate" },
        "description": "함수가 두 가지 책임을 가짐",
        "suggestion": "로깅 로직 분리"
      }
    ],
    "constraints": [
      "기존 public API 유지",
      "테스트 통과 필수"
    ]
  }
}
```

### 4.2 Fix Verification

```
Codex Fix Complete
       │
       ▼
┌─────────────────┐
│  Test Execution │
└────────┬────────┘
         │
    ┌────┴────┐
    ▼         ▼
 Pass       Fail
    │         │
    ▼         ▼
Re-review   Rollback
    │         │
    │         └──→ Human escalation
    │
    ▼
┌─────────────────┐
│ Reviewer Check  │
└────────┬────────┘
         │
    ┌────┴────┐
    ▼         ▼
 Pass       Fail
    │         │
    ▼         │
Complete    ──┘ (retry, max 3)
```

---

## 5. Configuration

### 5.1 Review Config File

`runes/config/auto-review.yaml`:

```yaml
auto_review:
  enabled: true

  triggers:
    on_save: false
    on_commit: true
    on_pr: true

  pre_checks:
    lint: true
    typecheck: true
    test: true
    coverage_threshold: 80

  review:
    focus:
      - solid_principles
      - error_handling
      - security
      - naming
      - complexity

    thresholds:
      cyclomatic_complexity: 10
      file_length: 300
      function_length: 50

  auto_fix:
    enabled: true
    max_retries: 3

    severity_actions:
      critical: auto_fix_and_block
      high: auto_fix
      medium: notify
      low: log

    excluded_patterns:
      - "*.test.ts"
      - "*.spec.ts"
      - "migrations/*"

  notifications:
    slack: false
    email: false
    inline_comments: true

  escalation:
    after_retries: 3
    notify_human: true
```

---

## 6. Related Spells

| Spell | Description |
|-------|-------------|
| `/cast:dev` | 개발 워크플로우 |
| `/cast:analyze` | Gemini 심층 분석 |
| `/cast:fix` | 에러 해결 |

---

## 7. Notification Templates

### 7.1 Issue Found Notification

```markdown
## 🔍 Auto-Review Results

**File**: `src/services/auth.ts`
**Commit**: `abc123`
**Time**: 2026-01-25 10:30:00

### Summary
| Severity | Count |
|----------|-------|
| 🔴 Critical | 0 |
| 🟠 High | 1 |
| 🟡 Medium | 2 |
| 🟢 Low | 1 |

### Issues

#### 🟠 [HIGH] SRP Violation
**Location**: Line 45, `authenticateUser()`
**Issue**: 함수가 인증과 로깅 두 가지 책임 수행
**Action**: Auto-fix initiated

---

**Status**: 🔄 Auto-fix in progress...
```

### 7.2 Fix Complete Notification

```markdown
## ✅ Auto-Fix Complete

**Original Issues**: 1 High, 2 Medium
**Fixed**: 1 High
**Remaining**: 2 Medium (manual review recommended)

### Changes Made
- `src/services/auth.ts`: Extracted logging to middleware
- `src/middleware/logging.ts`: New file created

### Verification
- ✅ Tests passing (45/45)
- ✅ Type check passing
- ✅ Re-review passing

**Status**: Ready for merge
```

---

*Version: 0.1.0*
*Last Updated: 2026-01-25*

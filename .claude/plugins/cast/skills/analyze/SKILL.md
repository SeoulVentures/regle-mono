---
name: analyze
description: Deep code analysis with Gemini (security/performance)
disable-model-invocation: true
---


Gemini Familiar를 호출하여 코드 심층 분석을 수행하는 마법입니다.

---

## Usage

```
/cast:analyze                       # 전체 프로젝트 분석
/cast:analyze --security            # 보안 집중 분석
/cast:analyze --performance         # 성능 집중 분석
/cast:analyze --file=path           # 특정 파일 분석
/cast:analyze --depth=deep          # 심층 분석
```

---

## 1. Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    GEMINI ANALYSIS                           │
│                                                              │
│   Input                                                      │
│     │                                                        │
│     ▼                                                        │
│   ┌───────────────────────────────────────────────────┐     │
│   │               GEMINI FAMILIAR                      │     │
│   │   ┌─────────────────────────────────────────┐     │     │
│   │   │           1M+ Token Context              │     │     │
│   │   │   ┌─────────┐ ┌─────────┐ ┌─────────┐  │     │     │
│   │   │   │Security │ │Perform. │ │Quality  │  │     │     │
│   │   │   │Analysis │ │ Audit   │ │ Check   │  │     │     │
│   │   │   └─────────┘ └─────────┘ └─────────┘  │     │     │
│   │   └─────────────────────────────────────────┘     │     │
│   └───────────────────────────────────────────────────┘     │
│     │                                                        │
│     ▼                                                        │
│   Analysis Report                                            │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. Analysis Types

### 2.1 Security Analysis (`--security`)

```yaml
security_analysis:
  focus_areas:
    - SQL Injection
    - XSS (Cross-Site Scripting)
    - CSRF (Cross-Site Request Forgery)
    - Authentication vulnerabilities
    - Authorization bypasses
    - Sensitive data exposure
    - Dependency vulnerabilities

  output:
    - Vulnerability list with severity
    - OWASP Top 10 mapping
    - Remediation recommendations
    - Code fix suggestions
```

### 2.2 Performance Analysis (`--performance`)

```yaml
performance_analysis:
  focus_areas:
    - Algorithm complexity (Big O)
    - Memory usage patterns
    - Database query optimization
    - Caching opportunities
    - Bundle size impact
    - Render performance (FE)

  output:
    - Performance hotspots
    - Optimization suggestions
    - Benchmark recommendations
    - Estimated improvement
```

### 2.3 Code Quality Analysis (Default)

```yaml
quality_analysis:
  focus_areas:
    - Code complexity
    - Maintainability
    - Test coverage gaps
    - Documentation completeness
    - Naming consistency
    - Architecture alignment

  output:
    - Quality score
    - Technical debt items
    - Refactoring suggestions
    - Best practice violations
```

### 2.4 Architecture Analysis (`--architecture`)

```yaml
architecture_analysis:
  focus_areas:
    - Module dependencies
    - Coupling analysis
    - Layer violations
    - Pattern consistency
    - Scalability concerns

  output:
    - Dependency graph
    - Coupling metrics
    - Architecture violations
    - Improvement roadmap
```

---

## 3. Analysis Depth

### 3.1 Shallow (`--depth=shallow`)

빠른 스캔, 명확한 이슈만 탐지

```yaml
shallow:
  token_budget: 50000
  scan_type: surface
  focus: critical_issues_only
  time: ~30 seconds
```

### 3.2 Medium (`--depth=medium`) [Default]

균형 잡힌 분석

```yaml
medium:
  token_budget: 200000
  scan_type: thorough
  focus: all_significant_issues
  time: ~2 minutes
```

### 3.3 Deep (`--depth=deep`)

전체 코드베이스 심층 분석

```yaml
deep:
  token_budget: 1000000
  scan_type: comprehensive
  focus: all_issues_and_opportunities
  time: ~10 minutes
```

---

## 4. Workflow

```
/cast:analyze 실행
     │
     ▼
┌─────────────────────────────────────┐
│     1. 분석 범위 결정                 │
│     - 파일/디렉토리 선택              │
│     - 분석 타입 결정                  │
│     - 깊이 설정                      │
└─────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────┐
│     2. Gemini 호출                   │
│     - 컨텍스트 구성                   │
│     - 분석 프롬프트 전달              │
│     - 결과 수신                      │
└─────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────┐
│     3. 결과 처리                     │
│     - 이슈 분류                      │
│     - 우선순위 지정                   │
│     - 리포트 생성                    │
└─────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────┐
│     4. 후속 조치                     │
│     - /cast:fix 연계 가능            │
│     - Serena 메모리 저장             │
└─────────────────────────────────────┘
```

---

## 5. Output Format

### 5.1 Analysis Report

```markdown
# 🔍 Gemini Analysis Report

**Project**: my-awesome-app
**Scope**: src/
**Analysis Type**: Security + Performance
**Depth**: Medium
**Date**: 2026-01-25

---

## Summary

| Category | Issues | Critical | High | Medium | Low |
|----------|--------|----------|------|--------|-----|
| Security | 3 | 1 | 1 | 1 | 0 |
| Performance | 2 | 0 | 1 | 1 | 0 |
| Quality | 5 | 0 | 0 | 3 | 2 |

---

## Critical Issues

### 🔴 [SEC-001] SQL Injection Vulnerability
**File**: `src/api/users.ts:45`
**Severity**: Critical
**OWASP**: A03:2021 - Injection

**Description**:
User input is directly concatenated into SQL query without sanitization.

**Code**:
```typescript
// Vulnerable
const query = `SELECT * FROM users WHERE id = ${userId}`;
```

**Recommendation**:
```typescript
// Fixed
const query = `SELECT * FROM users WHERE id = $1`;
const result = await db.query(query, [userId]);
```

---

## High Issues
...

---

## Recommendations

1. **Immediate**: Fix SQL injection vulnerability
2. **Short-term**: Implement rate limiting
3. **Long-term**: Add comprehensive input validation layer
```

---

## 6. Integration with Other Spells

### 6.1 With /cast:fix

```
/cast:analyze --security
     │
     ├── Issues found
     │
     ▼
/cast:fix --from-analysis
     │
     ├── Auto-fix applied
     │
     ▼
/cast:analyze --verify
```

### 6.2 With /cast:review

```
/cast:dev "새 API 엔드포인트"
     │
     ▼
Codex Implementation
     │
     ▼
/cast:analyze --security --performance
     │
     ▼
/cast:review (includes Gemini findings)
```

---

## 7. Configuration

### 7.1 Analysis Config

`runes/config/gemini.yaml`:

```yaml
gemini:
  model: gemini-1.5-pro

  default_analysis:
    depth: medium
    types:
      - security
      - performance
      - quality

  thresholds:
    critical_block: true
    high_warn: true

  exclusions:
    - "**/*.test.ts"
    - "**/*.spec.ts"
    - "**/node_modules/**"
    - "**/dist/**"

  focus_areas:
    - src/api/**
    - src/services/**
    - src/auth/**
```

---

## 8. Examples

### Example 1: Quick Security Scan

```
> /cast:analyze --security --depth=shallow

🔍 Running quick security scan...

✅ Analysis Complete

Found 1 issue:
🔴 Critical: SQL Injection in src/api/users.ts:45

Run `/cast:fix --issue=SEC-001` to auto-fix.
```

### Example 2: Full Analysis

```
> /cast:analyze --depth=deep

🔮 Running deep analysis...
   Scanning 127 files...
   Analyzing dependencies...
   Checking security patterns...
   Auditing performance...

✅ Analysis Complete

Summary:
- Security: 2 issues (1 high, 1 medium)
- Performance: 3 issues (2 medium, 1 low)
- Quality: 8 issues (3 medium, 5 low)

Full report saved to: .grimoires/reports/analysis-2026-01-25.md
```

---

## 9. Related Spells

| Spell | Description |
|-------|-------------|
| `/cast:dev` | 전체 개발 워크플로우 |
| `/cast:review` | 코드 리뷰 |
| `/cast:fix` | 에러 해결 |
| `/cast:design` | UI/UX 디자인 |

---

*Version: 0.1.0*
*Last Updated: 2026-01-25*

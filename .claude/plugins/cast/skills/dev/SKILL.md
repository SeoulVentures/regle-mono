---
name: dev
description: Start development workflow with AI agents
disable-model-invocation: true
---


Archmage와 모든 Familiar가 협업하는 전체 개발 워크플로우 마법입니다.

---

## Usage

```
/cast:dev "사용자 프로필 페이지를 추가해줘"
/cast:dev --quick "버그 수정"
/cast:dev --complex "인증 시스템 리팩토링"
```

---

## 1. Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      GRIMOIRES DEVELOPMENT WORKFLOW                      │
│                                                                          │
│   User Request                                                           │
│        │                                                                 │
│        ▼                                                                 │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │                         ARCHMAGE                                 │   │
│   │   ┌─────────┐   ┌─────────┐   ┌─────────┐   ┌─────────┐        │   │
│   │   │ Serena  │   │FixHive │   │Sequential│   │ Tools   │        │   │
│   │   │ Memory  │   │ Errors  │   │Thinking │   │         │        │   │
│   │   └─────────┘   └─────────┘   └─────────┘   └─────────┘        │   │
│   └─────────────────────────────────────────────────────────────────┘   │
│        │                                                                 │
│        │ orchestrates                                                    │
│        ▼                                                                 │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │                        FAMILIARS                                 │   │
│   │                                                                  │   │
│   │   ┌─────────┐   ┌─────────┐   ┌─────────┐   ┌─────────┐        │   │
│   │   │  Codex  │   │ Gemini  │   │ Stitch  │   │Reviewer │        │   │
│   │   │  Code   │   │ Analyze │   │   UI    │   │ Review  │        │   │
│   │   └─────────┘   └─────────┘   └─────────┘   └─────────┘        │   │
│   │                                                                  │   │
│   └─────────────────────────────────────────────────────────────────┘   │
│        │                                                                 │
│        ▼                                                                 │
│   Deliverables                                                           │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Workflow Stages

### Stage Overview

| Stage | Name | Description | Familiars |
|-------|------|-------------|-----------|
| 1 | Intake | 요청 수신 및 분석 | Archmage |
| 2 | Planning | 설계 및 계획 수립 | Archmage + Sequential Thinking |
| 3 | Design | UI/UX 디자인 | Stitch |
| 4 | Implementation | 코드 구현 | Codex |
| 5 | Analysis | 품질 분석 | Gemini |
| 6 | Review | 코드 리뷰 | Reviewer |
| 7 | Integration | 통합 및 검증 | Archmage |
| 8 | Delivery | 최종 전달 | Archmage |

---

## 3. Stage Details

### Stage 1: Intake

```
User Request
     │
     ▼
┌─────────────────────────────────────┐
│           INTAKE                     │
│                                      │
│  1. Context Loading (Serena)        │
│     └── Previous session state      │
│     └── Project context             │
│     └── Architecture decisions      │
│                                      │
│  2. Request Analysis                 │
│     └── Parse user intent           │
│     └── Identify scope              │
│     └── Detect ambiguities          │
│                                      │
│  3. Clarification (if needed)       │
│     └── Ask clarifying questions    │
│                                      │
│  4. Complexity Assessment           │
│     └── Score calculation           │
│     └── Workflow selection          │
└─────────────────────────────────────┘
     │
     ▼
   Stage 2
```

**Complexity Score Factors**:

| Factor | Weight | Low (1-3) | Medium (4-6) | High (7-10) |
|--------|--------|-----------|--------------|-------------|
| Files | 20% | 1-2 files | 3-5 files | 6+ files |
| Dependencies | 20% | None | Internal | External |
| Unknowns | 20% | Clear | Some | Many |
| Risk | 20% | Reversible | Moderate | Critical |
| Decision Points | 20% | None | Few | Many |

---

### Stage 2: Planning

```
Complexity Score
     │
     ├── Score < 3: Direct Implementation
     │   └── Skip to Stage 4
     │
     ├── Score 3-6: Standard Planning
     │   └── Basic decomposition
     │
     └── Score > 6: Deep Planning
         └── Sequential Thinking
```

---

### Stage 3: Design (Optional)

UI/UX 관련 작업 시에만 실행

```
┌─────────────────────────────────────┐
│           DESIGN (Stitch)            │
│                                      │
│  Input:                              │
│  └── Design requirements            │
│  └── Brand guidelines               │
│  └── Technical constraints          │
│                                      │
│  Process:                            │
│  └── Layout design                  │
│  └── Component design               │
│  └── Design token generation        │
│                                      │
│  Output:                             │
│  └── UI components                  │
│  └── Style files                    │
│  └── Design tokens                  │
│  └── Preview                        │
└─────────────────────────────────────┘
```

---

### Stage 4: Implementation

```
┌─────────────────────────────────────┐
│       IMPLEMENTATION (Codex)         │
│                                      │
│  Input:                              │
│  └── Design spec (from Archmage)    │
│  └── UI components (from Stitch)    │
│  └── Requirements                   │
│                                      │
│  Process:                            │
│  └── Code generation                │
│  └── Test generation                │
│  └── Documentation                  │
│                                      │
│  Output:                             │
│  └── Source files                   │
│  └── Test files                     │
│  └── Type definitions               │
│                                      │
│  Verification:                       │
│  └── Lint check                     │
│  └── Type check                     │
│  └── Unit tests                     │
└─────────────────────────────────────┘
```

---

### Stage 5: Analysis

```
┌─────────────────────────────────────┐
│         ANALYSIS (Gemini)            │
│                                      │
│  Input:                              │
│  └── Generated code                 │
│  └── Analysis focus areas           │
│                                      │
│  Analysis Types:                     │
│  └── Security review                │
│  └── Performance audit              │
│  └── Code quality check             │
│  └── Architecture alignment         │
│                                      │
│  Output:                             │
│  └── Analysis report                │
│  └── Issues found                   │
│  └── Recommendations                │
└─────────────────────────────────────┘
```

---

### Stage 6: Review

```
┌─────────────────────────────────────┐
│          REVIEW (Reviewer)           │
│                                      │
│  Input:                              │
│  └── Code changes                   │
│  └── Gemini analysis (if any)       │
│  └── Design principles rules        │
│                                      │
│  Review Checklist:                   │
│  └── SOLID principles               │
│  └── DRY/KISS/YAGNI                 │
│  └── Error handling                 │
│  └── Naming conventions             │
│  └── Complexity limits              │
│                                      │
│  Output:                             │
│  └── Review status                  │
│  └── Issues with severity           │
│  └── Fix suggestions                │
└─────────────────────────────────────┘
```

---

## 4. Workflow Variants

### 4.1 Quick Fix Workflow (`--quick`)

단순 버그 수정 (Complexity < 3)

```
User Request → Archmage → Codex → Quick Review → Delivery
```

### 4.2 Feature Workflow (Default)

새 기능 개발 (Complexity 3-6)

```
User Request → Archmage → [Stitch] → Codex → Gemini → Reviewer → Delivery
```

### 4.3 Complex Feature Workflow (`--complex`)

복잡한 기능 (Complexity > 6)

```
User Request
     │
     ▼
Archmage (Sequential Thinking)
     │
     ├── Stitch (UI Design)
     │        │
     └────────┼──────────────┐
              ▼              ▼
         Codex (FE)     Codex (BE)
              │              │
              └──────┬───────┘
                     ▼
               Gemini (Analysis)
                     │
                     ▼
               Reviewer
                     │
                     ▼
               Archmage (Integration)
                     │
                     ▼
               Delivery
```

---

## 5. Related Spells

| Spell | Description |
|-------|-------------|
| `/cast:review` | 코드 리뷰만 실행 |
| `/cast:analyze` | Gemini 분석만 실행 |
| `/cast:design` | UI 디자인만 실행 |
| `/cast:fix` | 에러 해결 |

---

## 6. Example Scenarios

### 6.1 Simple Bug Fix

```
User: /cast:dev --quick "로그인 버튼이 작동하지 않아요"

Workflow:
1. Intake: 버그 확인, 복잡도 2
2. Planning: Skip (simple)
3. Design: Skip
4. Implementation: Codex 수정
5. Analysis: Skip (simple fix)
6. Review: Quick review
7. Integration: Test verification
8. Delivery: Complete
```

### 6.2 New Feature

```
User: /cast:dev "사용자 프로필 페이지를 추가해주세요"

Workflow:
1. Intake: 요구사항 분석, 복잡도 5
2. Planning: Standard planning
3. Design: Stitch - UI 컴포넌트
4. Implementation: Codex - 페이지 구현
5. Analysis: Gemini - 보안/품질
6. Review: Reviewer - 원칙 검증
7. Integration: 통합 테스트
8. Delivery: Complete
```

### 6.3 Architecture Change

```
User: /cast:dev --complex "인증을 JWT에서 OAuth로 변경해주세요"

Workflow:
1. Intake: 요구사항 분석, 복잡도 8
2. Planning: Sequential Thinking
   - Define: 마이그레이션 범위
   - Decompose: 하위 작업 분해
   - Analyze: 영향 분석
   - Evaluate: 접근법 비교
   - Decide: 전략 선택
   - Plan: 실행 계획
3. Design: Skip (no UI changes)
4. Implementation: Codex - 단계별 구현
5. Analysis: Gemini - 보안 리뷰
6. Review: Reviewer - 전체 검증
7. Integration: 마이그레이션 테스트
8. Delivery: Complete
```

---

*Version: 0.1.0*
*Last Updated: 2026-01-25*

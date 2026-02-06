---
name: parallel
description: Execute tasks in parallel
disable-model-invocation: true
---


Familiar들을 병렬로 실행하여 워크플로우 성능을 최적화하는 마법입니다.

---

## Usage

```
/cast:parallel "복잡한 기능 구현"
/cast:parallel --tasks="FE,BE,Test"
/cast:parallel --max=4
```

---

## 1. Overview

### 1.1 Why Parallel Execution?

```
Sequential Execution (Slow)
─────────────────────────────────────────────────────►
│ Codex FE │ Codex BE │ Gemini │ Reviewer │
    30s        30s       20s       15s     = 95s total


Parallel Execution (Fast)
─────────────────────────────────────────────────────►
│ Codex FE ├──────────┤
│ Codex BE ├──────────┤
               │ Gemini │ Reviewer │
    30s           20s       15s     = 65s total
                                      (32% faster)
```

### 1.2 Parallelization Rules

| Rule | Description |
|------|-------------|
| **P1** | 의존성 없는 작업은 병렬 실행 |
| **P2** | 동일 파일 수정 작업은 순차 실행 |
| **P3** | 분석 작업은 구현 완료 후 실행 |
| **P4** | 리뷰는 모든 구현 완료 후 실행 |

---

## 2. Dependency Analysis

### 2.1 Task Dependency Graph

```
┌─────────────────────────────────────────────────────────────┐
│                    DEPENDENCY GRAPH                          │
│                                                              │
│                    ┌─────────┐                              │
│                    │ Planning │                              │
│                    └────┬────┘                              │
│                         │                                    │
│            ┌────────────┼────────────┐                      │
│            ▼            ▼            ▼                      │
│      ┌──────────┐ ┌──────────┐ ┌──────────┐                │
│      │ Stitch   │ │ Codex FE │ │ Codex BE │                │
│      │   UI     │ │(depends  │ │          │                │
│      │          │ │on Stitch)│ │          │                │
│      └────┬─────┘ └────┬─────┘ └────┬─────┘                │
│           │            │            │                        │
│           └──────┬─────┴────────────┘                       │
│                  │                                           │
│                  ▼                                           │
│            ┌──────────┐                                     │
│            │  Gemini  │                                     │
│            │ Analysis │                                     │
│            └────┬─────┘                                     │
│                 │                                            │
│                 ▼                                            │
│            ┌──────────┐                                     │
│            │ Reviewer │                                     │
│            └──────────┘                                     │
│                                                              │
│  Legend:                                                     │
│  ───► Sequential dependency                                 │
│  Parallel: Tasks at same level with no arrows between       │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 Dependency Types

| Type | Description | Example |
|------|-------------|---------|
| **Hard** | 반드시 순차 실행 | Stitch → Codex FE (UI 필요) |
| **Soft** | 권장 순차, 병렬 가능 | Codex FE, Codex BE |
| **None** | 완전 독립 | 서로 다른 모듈 |

---

## 3. Execution Patterns

### 3.1 Pattern A: Independent Tasks

모든 작업이 독립적인 경우

```
         Archmage
             │
    ┌────────┼────────┐
    ▼        ▼        ▼
┌───────┐┌───────┐┌───────┐
│Task A ││Task B ││Task C │
│Codex  ││Codex  ││Codex  │
└───┬───┘└───┬───┘└───┬───┘
    │        │        │
    └────────┼────────┘
             ▼
         Archmage
         (Merge)
```

### 3.2 Pattern B: Staged Parallel

단계별 병렬 실행

```
Stage 1 (Design + Backend)
    ┌────────────────┐
    │    Archmage    │
    └───────┬────────┘
            │
    ┌───────┴───────┐
    ▼               ▼
┌───────┐       ┌───────┐
│Stitch │       │Codex  │
│  UI   │       │Backend│
└───┬───┘       └───┬───┘
    │               │
    └───────┬───────┘
            ▼

Stage 2 (Frontend needs UI)
    ┌───────────────┐
    │    Codex      │
    │   Frontend    │
    └───────┬───────┘
            │
            ▼

Stage 3 (Analysis + Review)
    ┌───────┴───────┐
    ▼               ▼
┌───────┐       ┌───────┐
│Gemini │       │Review │
│       │       │(light)│
└───┬───┘       └───┬───┘
    │               │
    └───────┬───────┘
            ▼
        Complete
```

### 3.3 Pattern C: Fan-Out/Fan-In

하나의 작업을 분할하여 병렬 처리 후 병합

```
        Large Task
             │
             ▼
      ┌──────────────┐
      │   Split      │
      └──────┬───────┘
             │
    ┌────────┼────────┐
    ▼        ▼        ▼
┌───────┐┌───────┐┌───────┐
│Part 1 ││Part 2 ││Part 3 │
│Codex  ││Codex  ││Codex  │
└───┬───┘└───┬───┘└───┬───┘
    │        │        │
    └────────┼────────┘
             ▼
      ┌──────────────┐
      │    Merge     │
      └──────────────┘
```

---

## 4. Conflict Resolution

### 4.1 File Conflict Detection

```
┌─────────────────────────────────────────────────────────────┐
│                 CONFLICT DETECTION                           │
│                                                              │
│  Task A (Codex)        Task B (Codex)                       │
│  ├── modify auth.ts    ├── modify auth.ts  ← CONFLICT       │
│  └── create util.ts    └── modify user.ts  ← OK             │
│                                                              │
│  Detection:                                                  │
│  1. Before parallel execution, check output files           │
│  2. If overlap detected:                                    │
│     - Option A: Serialize conflicting tasks                 │
│     - Option B: Merge results carefully                     │
│     - Option C: Assign to single Familiar                   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 4.2 Conflict Resolution Strategies

| Strategy | When to Use | Pros | Cons |
|----------|-------------|------|------|
| **Serialize** | High conflict risk | Safe | Slower |
| **Merge** | Low conflict, additive changes | Fast | Risk |
| **Consolidate** | Same file, different parts | Balanced | Complex |

---

## 5. Resource Management

### 5.1 Concurrency Limits

```yaml
concurrency:
  # 전역 제한
  global:
    max_parallel_familiars: 4
    max_parallel_tasks: 8

  # Familiar별 제한
  per_familiar:
    codex:
      max_instances: 3
      rate_limit: 10/minute

    gemini:
      max_instances: 2
      rate_limit: 5/minute

    stitch:
      max_instances: 2
      rate_limit: 5/minute

    reviewer:
      max_instances: 2
      rate_limit: 20/minute

  # 리소스 기반 제한
  resource_based:
    max_total_tokens_per_minute: 100000
    max_api_calls_per_minute: 30
```

---

## 6. Error Handling in Parallel

### 6.1 Failure Modes

| Mode | Description | Handling |
|------|-------------|----------|
| **Single Failure** | 하나의 태스크만 실패 | 해당 태스크만 재시도 |
| **Cascade Failure** | 의존 태스크들도 실패 | 의존 체인 롤백 |
| **Partial Success** | 일부만 성공 | 성공 결과 유지, 실패 재시도 |

### 6.2 Recovery Strategies

```
Task Failure Detected
         │
         ▼
┌─────────────────────┐
│ Check Failure Type  │
└──────────┬──────────┘
           │
    ┌──────┴──────┐
    ▼             ▼
Isolated      Has Dependents
    │             │
    ▼             ▼
┌─────────┐ ┌─────────────────┐
│ Retry   │ │ Pause Dependents│
│ Task    │ │ + Retry Task    │
└────┬────┘ └────────┬────────┘
     │               │
     ├───────────────┤
     │               │
     ▼               ▼
  Success         Fail Again
     │               │
     ▼               ▼
  Continue      ┌─────────────┐
  Others        │ Rollback or │
                │ Escalate    │
                └─────────────┘
```

---

## 7. Examples

### Example 1: Simple Parallel

```
> /cast:parallel --tasks="utils/format,utils/validate,utils/transform"

🔮 Analyzing dependencies...
✓ No conflicts detected
✓ All tasks independent

Executing in parallel:
├── [1/3] Codex: utils/format.ts
├── [2/3] Codex: utils/validate.ts
└── [3/3] Codex: utils/transform.ts

Progress: ████████████████████ 100%

All tasks complete!
- Total time: 35s
- Sequential time: 90s
- Speedup: 61%
```

### Example 2: Staged Execution

```
> /cast:parallel "Fullstack feature: User Dashboard"

🔮 Analyzing task...

Execution Plan:
Stage 1 (Parallel):
  ├── Stitch: Dashboard UI components
  └── Codex: Backend API endpoints

Stage 2 (Sequential):
  └── Codex: Frontend integration (needs UI)

Stage 3 (Parallel):
  ├── Gemini: Security analysis
  └── Reviewer: Code review

Execute? [Y/n]
> Y

Stage 1: ██████████ Complete (45s)
Stage 2: ██████████ Complete (30s)
Stage 3: ██████████ Complete (25s)

Total: 100s (Sequential estimate: 160s, 38% faster)
```

---

## 8. Configuration

### 8.1 Parallel Execution Config

`runes/config/parallel.yaml`:

```yaml
parallel_execution:
  enabled: true

  scheduler:
    algorithm: priority_with_dependencies
    check_interval: 1000  # ms

  concurrency:
    max_parallel: 4
    per_familiar_limit:
      codex: 3
      gemini: 2
      stitch: 2
      reviewer: 2

  dependencies:
    auto_detect: true
    file_conflict_check: true

  error_handling:
    retry_failed: true
    max_retries: 2
    rollback_on_cascade: true

  optimization:
    batch_small_tasks: true
    min_batch_size: 3
    max_batch_size: 10
```

---

## 9. Best Practices

### 9.1 When to Parallelize

✅ **Good candidates**:
- 서로 다른 모듈/파일 수정
- 독립적인 기능 구현
- 다중 분석 (보안 + 성능)
- 테스트 실행

❌ **Avoid parallelizing**:
- 같은 파일 수정
- 순차적 의존성 있는 작업
- 상태 공유가 필요한 작업

### 9.2 Optimization Tips

1. **Early dependency detection**: 실행 전 의존성 분석
2. **Smart batching**: 작은 태스크들 묶어서 실행
3. **Resource awareness**: API 제한 고려
4. **Checkpoint often**: 병렬 실행 전 체크포인트

---

## 10. Related Spells

| Spell | Description |
|-------|-------------|
| `/cast:dev` | 기본 개발 워크플로우 |
| `/cast:analyze` | 분석 (병렬 가능) |
| `/cast:review` | 리뷰 |

---

*Version: 0.1.0*
*Last Updated: 2026-01-25*

---
name: checkpoint
description: Save/restore work checkpoint
disable-model-invocation: true
---


작업 상태를 저장하고 복원하는 마법입니다. 안전한 실험과 롤백을 지원합니다.

---

## Usage

```
/cast:checkpoint save "설명"           # 체크포인트 저장
/cast:checkpoint list                   # 체크포인트 목록
/cast:checkpoint restore <id>           # 복원
/cast:checkpoint diff <id>              # 현재와 비교
/cast:checkpoint delete <id>            # 삭제
```

---

## 1. Overview

체크포인트는 작업 중 안전하게 실험하고 필요시 이전 상태로 돌아갈 수 있게 합니다.

```
┌─────────────────────────────────────────────────────────────────┐
│                   CHECKPOINT WORKFLOW                            │
│                                                                  │
│   작업 시작                                                       │
│        │                                                         │
│        ▼                                                         │
│   ┌───────────────────────────────────────────────────────┐     │
│   │            /cast:checkpoint save                       │     │
│   │            "구현 전 상태"                              │     │
│   └───────────────────────────────────────────────────────┘     │
│        │                                                         │
│        ▼                                                         │
│   ┌───────────────────────────────────────────────────────┐     │
│   │            실험적 구현                                 │     │
│   │            (리스크 있는 변경)                          │     │
│   └───────────────────────────────────────────────────────┘     │
│        │                                                         │
│        ├── 성공 ──► 계속 진행                                    │
│        │                                                         │
│        └── 실패 ──► /cast:checkpoint restore                     │
│                     (이전 상태로 복원)                            │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. Commands

### 2.1 Save Checkpoint

```
> /cast:checkpoint save "OAuth 구현 전"

💾 Creating checkpoint...

Checkpoint Created:
┌─────────────────────────────────────────────────────────────────┐
│ ID:          cp-20240126-143052                                  │
│ Description: OAuth 구현 전                                        │
│ Time:        2024-01-26 14:30:52                                 │
│ Branch:      feature/oauth-integration                          │
│ Commit:      a1b2c3d (HEAD)                                      │
│                                                                  │
│ Captured:                                                        │
│   ├── Git state (uncommitted changes)                           │
│   ├── Stash created: stash@{0}                                  │
│   ├── Working directory snapshot                                │
│   └── Serena context                                            │
│                                                                  │
│ Size: 2.3 MB                                                     │
└─────────────────────────────────────────────────────────────────┘

✅ Checkpoint saved. You can now safely experiment.

Restore with: /cast:checkpoint restore cp-20240126-143052
```

### 2.2 List Checkpoints

```
> /cast:checkpoint list

📋 Checkpoints

ID                    Description              Time                 Size
─────────────────────────────────────────────────────────────────────────
cp-20240126-143052    OAuth 구현 전             2024-01-26 14:30    2.3 MB
cp-20240126-120015    DB 마이그레이션 전        2024-01-26 12:00    1.8 MB
cp-20240125-180030    리팩토링 시작점           2024-01-25 18:00    2.1 MB
cp-20240125-093045    초기 상태                2024-01-25 09:30    1.5 MB

Total: 4 checkpoints (7.7 MB)

Actions:
  restore <id>  - Restore to checkpoint
  diff <id>     - Compare with current
  delete <id>   - Delete checkpoint
```

### 2.3 Restore Checkpoint

```
> /cast:checkpoint restore cp-20240126-143052

⚠️ Restoring checkpoint will:
  - Discard current uncommitted changes
  - Reset to commit a1b2c3d
  - Restore stashed changes
  - Restore Serena context

Current changes that will be lost:
  M src/auth/oauth.ts (+145 lines)
  M src/auth/login.ts (+23 lines)
  A src/auth/providers/google.ts (new file)

Save current state as checkpoint before restoring? [Y/n/cancel]
> Y

💾 Saving current state as cp-20240126-153012...
✅ Current state saved

🔄 Restoring cp-20240126-143052...

Steps:
  ✅ Stashing current changes
  ✅ Checking out commit a1b2c3d
  ✅ Applying stash@{0}
  ✅ Restoring Serena context

✅ Restored to: OAuth 구현 전

You can return to the previous state with:
  /cast:checkpoint restore cp-20240126-153012
```

### 2.4 Diff with Checkpoint

```
> /cast:checkpoint diff cp-20240126-143052

📊 Diff: Current vs cp-20240126-143052 (OAuth 구현 전)

Files Changed: 5 (+312 lines, -45 lines)

Modified:
  src/auth/login.ts
    +23 lines (OAuth redirect logic)

  src/auth/user.service.ts
    +15 lines, -8 lines (user linking)

Added:
  src/auth/oauth.ts (+145 lines)
  src/auth/providers/google.ts (+78 lines)
  src/auth/providers/github.ts (+81 lines)

Deleted:
  src/auth/legacy-session.ts (-37 lines)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

View detailed diff? [Y/n]
> Y

[Shows git diff output]
```

### 2.5 Delete Checkpoint

```
> /cast:checkpoint delete cp-20240125-093045

🗑️ Delete checkpoint?

ID:          cp-20240125-093045
Description: 초기 상태
Created:     2024-01-25 09:30:45
Size:        1.5 MB

This action cannot be undone.
Confirm delete? [y/N]
> y

✅ Checkpoint deleted. Freed 1.5 MB.
```

---

## 3. What Gets Saved

### 3.1 Git State

```
Checkpoint includes:
├── Current commit hash
├── Uncommitted changes (staged + unstaged)
├── Untracked files (optional)
├── Branch information
└── Stash reference
```

### 3.2 Context State

```
Serena memories:
├── current-task.md
├── architecture-decisions.md
└── learned-patterns.md

Grimoires state:
├── .grimoires/cache/
└── .grimoires/sessions/
```

### 3.3 Configuration

```
Config files:
├── .env.local (encrypted)
├── grimoire.yaml
└── .claude/settings.local.json
```

---

## 4. Advanced Usage

### 4.1 Auto-checkpoint Before Risky Operations

```
> /cast:refactor --safe --path=src/services

🔒 Safe Mode Active

Auto-creating checkpoint before refactoring...
💾 Checkpoint: cp-auto-refactor-20240126-160000

Proceeding with refactoring...
```

### 4.2 Checkpoint with Tags

```
> /cast:checkpoint save "v1.0 릴리즈 전" --tag=release

Checkpoint saved with tag: release

List by tag:
> /cast:checkpoint list --tag=release
```

### 4.3 Export/Import

```
# Export checkpoint to file
> /cast:checkpoint export cp-20240126-143052 --output=backup.tar.gz

📦 Exporting checkpoint...
✅ Saved to: backup.tar.gz (2.1 MB)

# Import from file
> /cast:checkpoint import backup.tar.gz

📦 Importing checkpoint...
✅ Imported as: cp-imported-20240126-170000
```

---

## 5. Storage Management

### 5.1 Check Storage

```
> /cast:checkpoint storage

💾 Checkpoint Storage

Location: .grimoires/checkpoints/
Used:     7.7 MB
Limit:    100 MB (configurable)

Checkpoints by age:
  < 1 day:   2 checkpoints (4.1 MB)
  1-7 days:  1 checkpoint  (2.1 MB)
  > 7 days:  1 checkpoint  (1.5 MB)

Suggestions:
  - Consider deleting old checkpoints (> 7 days)
  - Auto-cleanup can be enabled in settings
```

### 5.2 Auto-cleanup

```yaml
# grimoire.yaml
checkpoints:
  max_count: 10
  max_age_days: 30
  auto_cleanup: true
  keep_tagged: true
```

---

## 6. Integration with Other Spells

### 6.1 With /cast:refactor

```
/cast:checkpoint save "Before refactoring"
/cast:refactor --path=src/services
# If something goes wrong:
/cast:checkpoint restore <id>
```

### 6.2 With /cast:dev

```
/cast:checkpoint save "Feature start"
/cast:dev "New feature"
# On failure:
/cast:checkpoint restore <id>
```

---

## 7. Options

| Option | Description | Default |
|--------|-------------|---------|
| `save <desc>` | 체크포인트 저장 | - |
| `list` | 체크포인트 목록 | - |
| `restore <id>` | 복원 | - |
| `diff <id>` | 현재와 비교 | - |
| `delete <id>` | 삭제 | - |
| `--tag` | 태그 지정 | - |
| `--include-untracked` | 미추적 파일 포함 | false |
| `--force` | 확인 없이 실행 | false |

---

## 8. Best Practices

### 8.1 When to Checkpoint

- ✅ 큰 리팩토링 시작 전
- ✅ 실험적 구현 전
- ✅ DB 마이그레이션 전
- ✅ 의존성 업그레이드 전
- ✅ 브랜치 병합 전

### 8.2 Naming Convention

```
# Good checkpoint descriptions
"OAuth 구현 전"
"DB 스키마 v2 마이그레이션 전"
"React 18 업그레이드 전"

# Avoid
"checkpoint 1"
"before changes"
"test"
```

### 8.3 Regular Cleanup

```
# Weekly cleanup routine
/cast:checkpoint list
/cast:checkpoint delete <old-ids>
```

---

## 9. Example Session

```
> /cast:checkpoint save "인증 리팩토링 시작"

💾 Checkpoint saved: cp-20240126-100000

> /cast:refactor --path=src/auth

[Refactoring in progress...]

Error: Tests failing after change

> /cast:checkpoint restore cp-20240126-100000

🔄 Restoring...
✅ Restored to: 인증 리팩토링 시작

> /cast:checkpoint save "두 번째 시도 전"

💾 Checkpoint saved: cp-20240126-101500

> /cast:refactor --path=src/auth --safe

[Safe refactoring with incremental commits...]

✅ Refactoring complete, all tests passing

> /cast:checkpoint delete cp-20240126-100000

🗑️ Deleted old checkpoint
```

---

## 10. Related Spells

| Spell | Description |
|-------|-------------|
| `/cast:refactor` | 리팩토링 |
| `/cast:dev` | 개발 워크플로우 |
| `/cast:plan` | 계획 수립 |

---

*Version: 0.3.0*
*Last Updated: 2026-01-26*

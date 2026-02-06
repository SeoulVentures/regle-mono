---
name: summon
description: Initialize Grimoires for a project
disable-model-invocation: true
---


프로젝트를 분석하여 적절한 Grimoires 구성을 자동으로 생성하는 초기화 마법입니다.

---

## Usage

```
/cast:summon
/cast:summon --template=backend
/cast:summon --minimal
```

---

## Auto-Initialization

Grimoires 0.2.0부터, 다른 `/cast:*` 명령어 실행 시 `grimoire.yaml`이 없으면 자동으로 초기화 프롬프트가 표시됩니다.

### Auto-Init Flow

```
User: /cast:dev "새 기능"
          │
          ▼
    ┌───────────────┐
    │ Check for     │
    │ grimoire.yaml │
    └───────┬───────┘
            │
      ┌─────┴─────┐
      ▼           ▼
   Exists      Missing
      │           │
      │           ▼
      │     ┌───────────────────────────────┐
      │     │ "🔮 Grimoires 초기화가 필요합니다" │
      │     │ "이 프로젝트에서 Grimoires를    │
      │     │  사용하시겠습니까?"              │
      │     │                               │
      │     │ [1] 예, 자동 설정 (권장)        │
      │     │ [2] 예, 직접 설정              │
      │     │ [3] 아니오, 취소               │
      │     └───────────────┬───────────────┘
      │                     │
      │               ┌─────┴─────┐
      │               ▼           ▼
      │         [1] or [2]       [3]
      │               │           │
      │               ▼           ▼
      │     ┌───────────────┐   Cancel
      │     │ /cast:summon  │
      │     │ (프로젝트 감지) │
      │     └───────┬───────┘
      │             │
      └──────┬──────┘
             ▼
    ┌───────────────┐
    │ Execute       │
    │ original cmd  │
    └───────────────┘
```

### Disabling Auto-Init

글로벌 설정에서 비활성화 가능:

```yaml
# ~/.grimoires/config.yaml
defaults:
  auto_init: false
```

---

## How It Works

```
/cast:summon 실행
     │
     ▼
┌─────────────────────────────────────┐
│     1. 프로젝트 분석                  │
│     - package.json / pyproject.toml │
│     - 디렉토리 구조                   │
│     - 기존 설정 파일                  │
└─────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────┐
│     2. 프로젝트 타입 감지             │
│     - Frontend / Backend / Fullstack│
│     - Framework 식별                 │
│     - Language 식별                  │
└─────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────┐
│     3. 컴포넌트 자동 선택             │
│     - Familiars                      │
│     - Rules                          │
│     - Spells                         │
└─────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────┐
│     4. 설정 파일 생성                 │
│     - grimoire.yaml                  │
│     - .claude/settings.local.json   │
└─────────────────────────────────────┘
```

---

## Project Detection Rules

### By package.json

```javascript
// Frontend Detection
{
  "dependencies": {
    "react": "*",      // → Stitch 활성화
    "vue": "*",        // → Stitch 활성화
    "next": "*",       // → Stitch + Codex
    "@angular/core": "*"
  }
}

// Backend Detection
{
  "dependencies": {
    "express": "*",    // → Codex + Gemini (보안)
    "fastify": "*",
    "nestjs": "*"
  }
}
```

### By pyproject.toml / requirements.txt

```
fastapi      → Backend API, Codex + Gemini
django       → Fullstack, All Familiars
flask        → Backend, Codex + Gemini
```

### By Directory Structure

```
src/components/  → Frontend, Stitch 활성화
src/api/         → Backend, Gemini 보안분석 활성화
src/services/    → Backend, Codex 중심
tests/           → Reviewer 활성화
```

---

## Auto-Selected Components

### Frontend Project

```yaml
familiars:
  - codex      # 컴포넌트 구현
  - stitch     # UI 디자인
  - reviewer   # 코드 리뷰

rules:
  - solid
  - dry
  - component-design    # UI 컴포넌트 규칙

spells:
  - cast-dev
  - cast-review
```

### Backend API Project

```yaml
familiars:
  - codex      # API 구현
  - gemini     # 보안/성능 분석
  - reviewer   # 코드 리뷰

rules:
  - solid
  - security           # 보안 규칙 강화
  - api-design         # API 설계 규칙
  - error-handling

spells:
  - cast-dev
  - cast-review
  - cast-fix
```

### Fullstack Project

```yaml
familiars:
  - codex
  - gemini
  - stitch
  - reviewer

rules:
  - all

spells:
  - all
```

### Minimal (--minimal)

```yaml
familiars:
  - codex
  - reviewer

rules:
  - solid
  - dry

spells:
  - cast-dev
```

---

## Generated Files

### grimoire.yaml

```yaml
# Auto-generated by /cast:summon
# Project: my-awesome-app
# Type: fullstack (Next.js)
# Generated: 2026-01-25

version: "0.1"

project:
  name: my-awesome-app
  type: fullstack
  framework: nextjs
  language: typescript

familiars:
  enabled:
    - codex
    - gemini
    - stitch
    - reviewer

  config:
    codex:
      model: gpt-4
      focus: [components, api-routes]

    gemini:
      focus: [security, performance]
      depth: medium

    stitch:
      framework: react
      styling: tailwind

rules:
  enabled:
    - solid
    - dry
    - security
    - react-best-practices

  custom: []  # Add project-specific rules here

spells:
  enabled:
    - cast-dev
    - cast-review
    - cast-analyze

context:
  # Auto-detected project context
  styling: tailwind
  state: zustand
  testing: jest

  # Add project-specific context
  conventions: |
    - Use functional components
    - Prefer server components where possible
```

### .claude/settings.local.json

```json
{
  "mcpServers": {
    "serena": {
      "command": "npx",
      "args": ["-y", "serena-mcp"]
    },
    "sequential-thinking": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-sequential-thinking"]
    },
    "codex": {
      "command": "codex",
      "args": ["--mcp-server"],
      "env": {
        "OPENAI_API_KEY": "${OPENAI_API_KEY}"
      }
    },
    "gemini": {
      "command": "npx",
      "args": ["-y", "gemini-mcp"],
      "env": {
        "GOOGLE_API_KEY": "${GOOGLE_API_KEY}"
      }
    },
    "stitch": {
      "command": "npx",
      "args": ["-y", "stitch-mcp"]
    }
  }
}
```

---

## Interactive Mode

`/cast:summon` 실행 시 확인 프롬프트:

```
🔮 Grimoires Initialization

Detected Project:
  Type: Fullstack (Next.js + TypeScript)
  Framework: Next.js 14
  Styling: Tailwind CSS

Recommended Configuration:
  Familiars: Codex, Gemini, Stitch, Reviewer
  Rules: SOLID, DRY, Security, React Best Practices
  Spells: cast-dev, cast-review, cast-analyze

Proceed with this configuration?
  [1] Yes, create configuration
  [2] Customize selection
  [3] Minimal setup
  [4] Cancel
```

---

## Related Spells

| Spell | Description |
|-------|-------------|
| `/cast:dev` | 개발 워크플로우 |
| `/cast:review` | 코드 리뷰 |
| `/cast:analyze` | Gemini 분석 |
| `/cast:design` | UI/UX 디자인 |
| `/cast:fix` | 에러 해결 |

---

## Examples

### Example 1: New React Project

```bash
npx create-next-app my-app
cd my-app
claude
> /cast:summon
```

Output:
```
✓ Detected: Next.js 14 + TypeScript
✓ Created: grimoire.yaml
✓ Created: .claude/settings.local.json
✓ Familiars: Codex, Stitch, Reviewer
✓ Rules: SOLID, React Best Practices

Grimoires initialized! Start with:
> /cast:dev "새로운 기능을 구현해줘"
```

### Example 2: Python Backend

```bash
cd my-fastapi-project
claude
> /cast:summon
```

Output:
```
✓ Detected: FastAPI + Python 3.11
✓ Created: grimoire.yaml
✓ Familiars: Codex, Gemini (security focus)
✓ Rules: SOLID, Security, API Design

Grimoires initialized! Start with:
> /cast:dev "API 엔드포인트를 추가해줘"
```

---

## File Templates

### grimoire.yaml Template

Location: `registry/templates/grimoire.yaml.template`

### MCP Config Template

Location: `registry/templates/mcp-config.json.template`

---

*Version: 0.1.0*

---
name: design
description: UI/UX design workflow with Stitch
disable-model-invocation: true
---


Stitch Familiar를 호출하여 UI/UX 디자인 작업을 수행하는 마법입니다.

---

## Usage

```
/cast:design "로그인 페이지 디자인"
/cast:design --component="Button"
/cast:design --page="Dashboard"
/cast:design --from-figma="url"
```

---

## 1. Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    STITCH DESIGN                             │
│                                                              │
│   Design Request                                             │
│     │                                                        │
│     ▼                                                        │
│   ┌───────────────────────────────────────────────────┐     │
│   │               STITCH FAMILIAR                      │     │
│   │   ┌─────────────────────────────────────────┐     │     │
│   │   │         UI/UX Specialist                 │     │     │
│   │   │   ┌─────────┐ ┌─────────┐ ┌─────────┐  │     │     │
│   │   │   │Component│ │  Page   │ │  Style  │  │     │     │
│   │   │   │ Design  │ │ Layout  │ │ Tokens  │  │     │     │
│   │   │   └─────────┘ └─────────┘ └─────────┘  │     │     │
│   │   └─────────────────────────────────────────┘     │     │
│   └───────────────────────────────────────────────────┘     │
│     │                                                        │
│     ▼                                                        │
│   UI Components + Styles                                     │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. Design Capabilities

### 2.1 Component Design

```yaml
component_design:
  types:
    - Buttons
    - Forms
    - Cards
    - Modals
    - Navigation
    - Tables
    - Lists

  output:
    - React/Vue/Svelte components
    - TypeScript interfaces
    - Styling (Tailwind/CSS)
    - Storybook stories (optional)
```

### 2.2 Page Layout

```yaml
page_layout:
  types:
    - Landing pages
    - Dashboard layouts
    - Form pages
    - List/Detail views
    - Authentication screens

  output:
    - Page components
    - Responsive layouts
    - Navigation structure
```

### 2.3 Design Tokens

```yaml
design_tokens:
  categories:
    - Colors (primary, secondary, semantic)
    - Typography (fonts, sizes, weights)
    - Spacing (margins, paddings, gaps)
    - Borders (radius, widths)
    - Shadows
    - Breakpoints

  output:
    - CSS variables
    - Tailwind config
    - Theme object
```

---

## 3. Workflow

```
/cast:design 실행
     │
     ▼
┌─────────────────────────────────────┐
│     1. 요구사항 분석                  │
│     - 디자인 목적                     │
│     - 타겟 사용자                     │
│     - 기술적 제약                     │
└─────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────┐
│     2. 컨텍스트 수집                  │
│     - 기존 디자인 시스템              │
│     - 브랜드 가이드라인               │
│     - 프로젝트 스타일링 설정          │
└─────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────┐
│     3. Stitch 호출                   │
│     - 디자인 생성                    │
│     - 컴포넌트 코드화                │
│     - 스타일 적용                    │
└─────────────────────────────────────┘
     │
     ▼
┌─────────────────────────────────────┐
│     4. 결과물 통합                   │
│     - 파일 생성                      │
│     - 프리뷰 제공                    │
│     - /cast:dev 연계                │
└─────────────────────────────────────┘
```

---

## 4. Design Modes

### 4.1 Quick Component (`--component`)

단일 컴포넌트 빠른 생성

```
> /cast:design --component="PrimaryButton"

🎨 Designing component...

Created:
- src/components/ui/PrimaryButton.tsx
- src/components/ui/PrimaryButton.stories.tsx

Preview available at: http://localhost:6006
```

### 4.2 Page Design (`--page`)

전체 페이지 레이아웃 디자인

```
> /cast:design --page="UserProfile"

🎨 Designing page layout...

Created:
- src/pages/UserProfile.tsx
- src/components/profile/ProfileHeader.tsx
- src/components/profile/ProfileInfo.tsx
- src/components/profile/ProfileActions.tsx
```

### 4.3 Design System (`--system`)

디자인 시스템 초기화/확장

```
> /cast:design --system

🎨 Setting up design system...

Created:
- src/styles/tokens.css
- src/styles/theme.ts
- tailwind.config.js (updated)
- src/components/ui/index.ts
```

### 4.4 Figma Import (`--from-figma`)

Figma 디자인에서 컴포넌트 추출

```
> /cast:design --from-figma="https://figma.com/file/..."

🎨 Importing from Figma...

Detected components:
- Button (3 variants)
- Card
- Input
- Modal

Import all? [Y/n]
```

---

## 5. Configuration

### 5.1 Stitch Config

`grimoire.yaml`:

```yaml
familiars:
  config:
    stitch:
      framework: react          # react | vue | svelte | html
      styling: tailwind         # tailwind | styled-components | css | scss
      component_library: null   # shadcn | radix | chakra | null

      design_tokens:
        source: tailwind        # tailwind | figma | custom

      output:
        typescript: true
        stories: true           # Storybook stories
        tests: false            # Component tests

      conventions:
        file_naming: PascalCase
        style_location: inline  # inline | separate | css-modules
```

---

## 6. Output Examples

### 6.1 React + Tailwind Component

```tsx
// src/components/ui/Button.tsx
import { forwardRef } from 'react';
import { cn } from '@/lib/utils';

export interface ButtonProps
  extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: 'primary' | 'secondary' | 'ghost';
  size?: 'sm' | 'md' | 'lg';
}

export const Button = forwardRef<HTMLButtonElement, ButtonProps>(
  ({ className, variant = 'primary', size = 'md', ...props }, ref) => {
    return (
      <button
        ref={ref}
        className={cn(
          'inline-flex items-center justify-center rounded-md font-medium transition-colors',
          'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-offset-2',
          'disabled:pointer-events-none disabled:opacity-50',
          {
            'bg-primary text-primary-foreground hover:bg-primary/90': variant === 'primary',
            'bg-secondary text-secondary-foreground hover:bg-secondary/80': variant === 'secondary',
            'hover:bg-accent hover:text-accent-foreground': variant === 'ghost',
          },
          {
            'h-8 px-3 text-sm': size === 'sm',
            'h-10 px-4 text-base': size === 'md',
            'h-12 px-6 text-lg': size === 'lg',
          },
          className
        )}
        {...props}
      />
    );
  }
);
Button.displayName = 'Button';
```

### 6.2 Design Tokens

```css
/* src/styles/tokens.css */
:root {
  /* Colors */
  --color-primary: 220 90% 56%;
  --color-primary-foreground: 0 0% 100%;
  --color-secondary: 220 14% 96%;
  --color-secondary-foreground: 220 9% 46%;

  /* Typography */
  --font-sans: 'Inter', system-ui, sans-serif;
  --font-mono: 'JetBrains Mono', monospace;

  /* Spacing */
  --spacing-xs: 0.25rem;
  --spacing-sm: 0.5rem;
  --spacing-md: 1rem;
  --spacing-lg: 1.5rem;
  --spacing-xl: 2rem;

  /* Borders */
  --radius-sm: 0.25rem;
  --radius-md: 0.5rem;
  --radius-lg: 0.75rem;
  --radius-full: 9999px;
}
```

---

## 7. Integration with Other Spells

### 7.1 Design → Dev Flow

```
/cast:design "Dashboard 페이지"
     │
     ├── Stitch: UI 컴포넌트 생성
     │
     ▼
/cast:dev "Dashboard 로직 구현"
     │
     ├── Codex: 비즈니스 로직 추가
     ├── Gemini: 분석
     ├── Reviewer: 리뷰
     │
     ▼
   Complete
```

### 7.2 With /cast:review

```
/cast:design --component="DataTable"
     │
     ▼
/cast:review --accessibility
     │
     ├── a11y issues found
     │
     ▼
/cast:design --fix-a11y
```

---

## 8. Examples

### Example 1: Quick Button

```
> /cast:design --component="IconButton"

🎨 Stitch is designing...

Requirements analysis:
- Icon button with hover state
- Multiple sizes
- Primary/secondary variants

Created files:
✓ src/components/ui/IconButton.tsx
✓ src/components/ui/IconButton.stories.tsx

Preview: http://localhost:6006/?path=/story/ui-iconbutton
```

### Example 2: Dashboard Page

```
> /cast:design --page="Analytics Dashboard"

🎨 Stitch is designing...

Page structure:
├── Header (with navigation)
├── Sidebar (metrics navigation)
├── Main Content
│   ├── MetricsCards (4 cards)
│   ├── ChartSection (2 charts)
│   └── DataTable
└── Footer

Created files:
✓ src/pages/AnalyticsDashboard.tsx
✓ src/components/analytics/MetricsCard.tsx
✓ src/components/analytics/ChartSection.tsx
✓ src/components/analytics/AnalyticsTable.tsx

Total: 4 new components
```

### Example 3: Design System Setup

```
> /cast:design --system --preset=modern

🎨 Setting up design system...

Configuration:
- Framework: React
- Styling: Tailwind CSS
- Colors: Modern palette
- Typography: Inter + JetBrains Mono

Created:
✓ tailwind.config.js (updated)
✓ src/styles/globals.css
✓ src/styles/tokens.ts
✓ src/components/ui/index.ts (barrel export)

Design system ready!
Start creating components with `/cast:design --component="Name"`
```

---

## 9. Related Spells

| Spell | Description |
|-------|-------------|
| `/cast:dev` | 전체 개발 워크플로우 |
| `/cast:review` | 코드 리뷰 (접근성 포함) |
| `/cast:analyze` | 품질 분석 |
| `/cast:summon` | 프로젝트 초기화 |

---

*Version: 0.1.0*
*Last Updated: 2026-01-25*

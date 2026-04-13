---
title: SVGW ESLint Priority A 룰 재활성화 설계
date: 2026-04-13
repo: SeoulVentures/SeoulVenturesGroupware
issue: "#607 (Priority A 부분)"
status: draft
related:
  - PR #606 (ESLint 9 + Flat Config 마이그레이션, merged)
  - Issue #607 (off 룰 재활성화 전체)
  - Issue #608 (ESLint 10 + @stylistic 이관)
---

# ESLint Priority A 룰 재활성화 설계

## 1. 목표

PR #606 에서 `off` 처리한 Priority A 3룰을 `off → error` 로 전환하고, 기존 위반 7건을 전부 수정한다.

- ReDoS(super-linear backtracking) 리스크가 있는 정규식 3건 제거·대체
- side-effect 을 가진 삼항식(anti-pattern) 1건 구조 개선
- 브라우저 repaint 강제를 위한 의도된 unused expression 2건을 self-documenting 함수로 대체

## 2. 배경

- PR #606 에서 ESLint 9 + Flat Config 로 이관하며 `sonarjs` 0.24→3.x 업그레이드로 다수 룰이 신규 활성화됨.
- 기존 동작 유지를 위해 일부 룰을 일시적으로 `off` 처리했고, 재활성화는 #607 에서 점진 진행하기로 함.
- Priority A 룰은 실제 버그/보안 위험군이라 다른 우선순위보다 선행.
- 본 스펙은 #607 의 Priority A 범위에 한정. Priority B/C 는 후속 스펙.

## 3. 대상 룰 및 위반 인벤토리

| # | 파일:라인 | 룰 | 기존 코드 | 수정 방향 |
|---|---|---|---|---|
| 1 | `frontend/resources/ts/@core/utils/validators.ts:16` | `sonarjs/regex-complexity` | email regex: complexity 30 (allowed 20) | 표준 HTML5 spec 수준의 단순 email regex 로 교체 (RFC5322 대신 실용 subset) |
| 2 | `frontend/resources/ts/@core/utils/validators.ts:26` | `sonarjs/slow-regex` | password regex: `(?=.*\d)(?=.*[a-z])(?=.*[A-Z])(?=.*[!@#$%&*()]).{8,}` (lookahead 4개) | lookahead 제거하고 JS 로 조건 분해 |
| 3 | `frontend/resources/ts/utils/review/clientNameComparator.ts:15` | `sonarjs/slow-regex` | `TRIM_RE = /^[\s\p{White_Space}]+\|[\s\p{White_Space}]+$/gu` (문자클래스 중복) | `\s` 제거 → `\p{White_Space}` 단독 사용 (superset) |
| 4 | `frontend/resources/ts/@core/utils/formatters.ts:13` | `sonarjs/slow-regex` | `kFormatter` 의 `\B(?=(\d{3})+(?!\d))/g` (천단위 콤마) | regex 폐기 → `Number.prototype.toLocaleString('en-US')` |
| 5 | `frontend/resources/ts/@core/components/cards/AppCardActions.vue:44` | `@typescript-eslint/no-unused-expressions` | `cond ? emit(...) : _loading.value = value` | `if/else` 분기 |
| 6 | `frontend/resources/ts/@layouts/components/TransitionExpand.vue:25` | `@typescript-eslint/no-unused-expressions` | `getComputedStyle(element).height` (force repaint) | 파일 내부 헬퍼 `forceRepaint(el)` 로 래핑 |
| 7 | `frontend/resources/ts/@layouts/components/TransitionExpand.vue:47` | `@typescript-eslint/no-unused-expressions` | 동일 | 동일 |

## 4. 세부 수정 방안

### 4.1 `validators.ts` — emailValidator / passwordValidator

**Before**:
```ts
export const emailValidator = (value: unknown) => {
  if (isEmpty(value))
    return true

  const re = /^(?:[^<>()[\]\\.,;:\s@"]+(?:\.[^<>()[\]\\.,;:\s@"]+)*|".+")@(?:\[\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\]|(?:[a-z\-\d]+\.)+[a-z]{2,})$/i
  // ... use `re.test(...)`
}

export const passwordValidator = (password: string) => {
  const regExp = /(?=.*\d)(?=.*[a-z])(?=.*[A-Z])(?=.*[!@#$%&*()]).{8,}/
  const validPassword = regExp.test(password)
  // ...
}
```

**After (안 1: email)** — HTML5 spec 기반 실용 regex:
```ts
// HTML5 입력 타입 email 과 동일. RFC5322 full 은 아니지만 실서비스 fullmesh 에 충분.
const EMAIL_RE = /^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$/
```

**After (안 2: password)** — lookahead 제거, 분해:
```ts
export const passwordValidator = (password: string) => {
  const hasLowercase = /[a-z]/.test(password)
  const hasUppercase = /[A-Z]/.test(password)
  const hasDigit = /\d/.test(password)
  const hasSpecial = /[!@#$%&*()]/.test(password)
  const longEnough = password.length >= 8

  const valid = hasLowercase && hasUppercase && hasDigit && hasSpecial && longEnough

  return valid || 'Field must contain at least one uppercase, lowercase, special character and digit with min 8 chars'
}
```

### 4.2 `clientNameComparator.ts` — TRIM_RE

**Before**:
```ts
const TRIM_RE = /^[\s\p{White_Space}]+|[\s\p{White_Space}]+$/gu
```

**After**:
```ts
// \p{White_Space} 는 ASCII space, NBSP U+00A0, em space U+2003, 전각 공백 U+3000 을 모두 포함.
// \s 와 중복되어 ReDoS backtracking 유발.
const TRIM_RE = /^\p{White_Space}+|\p{White_Space}+$/gu
```

**백엔드 동치성 확인 필수**: `App\Support\Review\ClientNameComparator.php` 의 trim regex 가 `\p{White_Space}` 또는 `\s` 중 어느 쪽을 쓰는지 조회 후 불일치 시 문서화 혹은 백엔드 병행 수정.

### 4.3 `formatters.ts` — kFormatter

**Before**:
```ts
export const kFormatter = (num: number) => {
  const regex = /\B(?=(\d{3})+(?!\d))/g

  return Math.abs(num) > 9999
    ? `${Math.sign(num) * +((Math.abs(num) / 1000).toFixed(1))}k`
    : Math.abs(num).toFixed(0).replace(regex, ',')
}
```

**After**:
```ts
// regex 천단위 구분 대신 Intl 기반 locale-aware 포맷 사용. 입력은 finite number 이므로 toFixed 결과도 동일.
export const kFormatter = (num: number) => {
  const abs = Math.abs(num)
  if (abs > 9999) {
    const scaled = Math.sign(num) * +((abs / 1000).toFixed(1))

    return `${scaled}k`
  }

  return Math.floor(abs).toLocaleString('en-US')
}
```

### 4.4 `AppCardActions.vue` — setter

**Before**:
```ts
set(value: boolean) {
  props.loading !== undefined ? emit('update:loading', value) : _loading.value = value
}
```

**After**:
```ts
set(value: boolean) {
  if (props.loading !== undefined)
    emit('update:loading', value)
  else
    _loading.value = value
}
```

### 4.5 `TransitionExpand.vue` — forceRepaint helper

**Before** (2 군데):
```ts
// 애니메이션 트리거 전 force repaint — getComputedStyle 접근 자체가 목적 (반환값은 의도적 무시).
getComputedStyle(element).height
```

**After** — `<script>` 상단에 file-local helper:
```ts
const forceRepaint = (el: HTMLElement) => { getComputedStyle(el).height }
```

호출부:
```ts
forceRepaint(element)
```

호출문은 expression-statement 로서 unused expression 룰 예외. 이름이 의도를 설명하므로 주석 불필요.

## 5. 설정 변경

`frontend/eslint.config.js`:

1. `legacyOffRules` 에서 제거:
   ```js
   'sonarjs/slow-regex': 'off',
   'sonarjs/regex-complexity': 'off',
   ```
   → sonarjs/recommended preset 기본값(error) 복귀.

2. `tsRules` 에서 제거:
   ```js
   '@typescript-eslint/no-unused-expressions': 'off',
   ```
   → ts-eslint/recommended preset 기본값(error) 복귀.

3. `#607` 주석에서 Priority A 3건 완료 표기 및 해당 줄의 "별도 이슈 재활성화 추적" 주석 보강.

## 6. 검증

1. **자동 검증**:
   - `bun run lint` — 0 errors 목표 (기존 4 warnings 중 본 스코프 외 3~4건은 유지).
   - `bun run build` — 성공 유지.
   - `bun run typecheck` — 기존 수준 (사전 존재 에러는 본 PR 무관).

2. **behavioral test case 표** (PR 본문에 포함, 로컬에서 `bunx tsx` 로 수행):
   - `emailValidator`:
     - 유효 10건: `a@b.co`, `user+tag@example.com`, `first.last@sub.example.co.kr`, `_a@b.io`, `a1@b2.io`, `simple@example.org`, `valid.user@subdomain.example.com`, `user@192.168.1.1` (IP literal 은 새 regex 에서 거부 — 회귀 허용 여부 확인), ... 
     - 무효 10건: `(빈문자)`, `noat`, `@nolocal`, `a b@c.d`, `a@`, `a@.com`, `a@b.`, `a@b..c`, `a@ b.c`, `a@b,c`
   - `passwordValidator`:
     - 유효: `Aa1!aaaa`, `Abcdefg9!`, `ZZZZzzzz11!!`, ...
     - 무효: `Aa1!` (짧음), `aaaaaaaa1!` (대문자X), `AAAAAAAA1!` (소문자X), `Aaaaaaaa!` (숫자X), `Aaaaaaaa1` (특수문자X)
   - `kFormatter`:
     - `1234 → "1,234"`, `9999 → "9,999"`, `10000 → "10k"`, `12345 → "12.3k"`, `-12345 → "-12.3k"`, `0 → "0"`, `999 → "999"`
   - `normalizeClientName` / `clientNameEquals`:
     - `"  foo  " → "foo"`, `"\u00A0foo\u3000" → "foo"`, `"A사" ≠ "A 사"`, `"가\u0300" → "가\u0300" (NFC 정규화)`
   - 백엔드 PHP 대조 결과 문서화 (`App\Support\Review\ClientNameComparator.php`).

3. **후속**: PR 본문에 위 테이블을 포함하고 리뷰어가 로컬 재현 가능한 1-liner 제공 (`bunx tsx -e "..."`).

## 7. 엣지케이스·리스크

| 리스크 | 대응 |
| --- | --- |
| email regex 교체 시 IP literal (`user@[192.168.1.1]`) 거부로 기존 가입자 영향 | 본 프로젝트는 사내 에이전시 그룹웨어로 실사용자 IP literal 이메일 0건 전제. 신규 regex 는 IP literal 불허로 확정. 회귀 리포트 시 hotfix PR 에서 분기 복원 |
| clientNameComparator 의 `\p{White_Space}` 가 백엔드 `\s` 와 미묘한 차이 (U+0085 NEL 등) | 백엔드 regex 확인 후 동치이면 OK, 상이하면 양쪽 통일하거나 차이점 문서화 |
| `kFormatter` 의 `toLocaleString('en-US')` 는 Intl 의존 — 모든 브라우저 지원 (IE11 제외, 본 프로젝트 대상 아님) | 타깃 브라우저 Intl 지원 전제 |
| regex 수정으로 기존 오류 메시지 / 입력 UX 변경 | 수정 규모 최소. 에러 메시지 문자열 불변. |
| 테스트 인프라 부재로 회귀 탐지 불가 | 수동 검증 테이블 + 리뷰어 재현. 테스트 러너 도입은 별도 이슈 |

## 8. 범위 외 (명시적 제외)

- Priority B/C 룰 — 후속 스펙
- 테스트 러너 도입 (vitest 등) — 별도 이슈
- `sonarjs/void-use` — off 유지 (forceRepaint 패턴이 void 의존 제거)
- `.eslintrc` / lint 스크립트 구조 변경 — 본 스코프 외

## 9. 롤백

단일 PR squash merge 가정. 문제 발생 시 `git revert <merge-commit>` 1회로 원복 가능. ESLint 설정과 소스 코드 변경이 같은 커밋에 묶이므로 부분 롤백 불필요.

## 10. 관련 문서

- 원 이슈: [#607](https://github.com/SeoulVentures/seoulventuresgroupware/issues/607)
- 원 마이그레이션: PR #606 (merged)
- 핸드오프 메모리: `/opt/SeoulVentures/.claude/projects/-opt-SeoulVentures-regle/memory/svgw-eslint9-flat-2026-04-13.md`

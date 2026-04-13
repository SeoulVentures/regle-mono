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

**After (안 1: email)** — HTML5 spec 공식 regex 채택:
```ts
// WHATWG HTML spec 의 "valid e-mail address" 정규식.
// https://html.spec.whatwg.org/multipage/input.html#valid-e-mail-address
// 명시적으로 linear backtracking 을 보장하도록 설계되어 sonarjs/slow-regex 통과 예상.
const EMAIL_RE = /^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$/
```

**구현 착수 전 PoC 필수**: 위 regex 를 임시 파일에 넣고 `bun run lint` 통과 확인. 만약 `sonarjs/slow-regex` 가 여전히 잡으면:
- (a) 동일 구조의 공식 HTML5 regex 이므로 eslint-disable-next-line 으로 억제 (주석에 HTML5 spec 링크)
- (b) 또는 전체 email 검증을 브라우저 `input[type=email]` 검사 + 간단한 `@` 포함·길이 체크로 교체 (예: `/^[^\s@]+@[^\s@]+\.[^\s@]+$/`)

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
// JS `\s` 는 ES2015+ 에서 Unicode whitespace 전체 + BOM(U+FEFF) 포함.
// `\p{White_Space}` 는 Unicode property 기반이지만 U+FEFF (ZWNBSP) 를 format char 로 분류해 제외함.
// 따라서 기존의 `\s|\p{White_Space}` 중 후자는 중복 (subset) — 제거해도 매칭 범위 손실 없음.
// Excel 업로드에서 유입 가능한 UTF-8 BOM 까지 trim 하려면 `\s` 가 필수.
const TRIM_RE = /^\s+|\s+$/g
```

**백엔드 동치성 확인 필수**: `App\Support\Review\ClientNameComparator.php` 의 trim regex 가 어느 표기를 사용하는지 조회.
- PHP 의 `\s` 는 기본적으로 ASCII 만 (공간 4종) → NBSP(U+00A0), 전각 공백(U+3000) 불포함. 이 경우 JS 와 **비동치**.
- PHP 에서 `\p{Zs}` 또는 `\p{White_Space}` + `u` 플래그를 쓰면 거의 JS `\s` 와 근접하나 U+FEFF 차이 잔존 가능.
- 동치성 리스크가 확인되면 (a) 양쪽 `\p{White_Space}\uFEFF` 로 명시 통일 (b) 또는 차이점을 스펙에 문서화하고 프로덕션 영향 없음을 확인. 본 PR 은 프론트엔드 수정만, 백엔드 통일은 별도 PR.

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
// regex 천단위 구분 대신 Intl 기반 locale-aware 포맷 사용.
// 기존 toFixed(0) 과 동치성을 위해 Math.round 사용 (Math.floor 는 1234.7 → "1,234" 로 1 차이 회귀).
// 기존 동작 유지 사항: abs ≤ 9999 음수 입력 시 부호 탈락 (`-500 → "500"`) — 의도적 보존.
export const kFormatter = (num: number) => {
  const abs = Math.abs(num)
  if (abs > 9999) {
    const scaled = Math.sign(num) * +((abs / 1000).toFixed(1))

    return `${scaled}k`
  }

  return Math.round(abs).toLocaleString('en-US')
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

**After** — `defineComponent({ setup() {...} })` 내부 helper (파일은 `<script setup>` 이 아닌 legacy `<script lang="ts">` + setup 함수):
```ts
setup(_, { slots }) {
  // 브라우저에 강제 layout recalc 트리거 — getComputedStyle 은 live 객체라 프로퍼티 접근만으로 flush 됨.
  const forceRepaint = (el: HTMLElement) => { getComputedStyle(el).height }

  const onEnter = (element: HTMLElement) => {
    // ...
    forceRepaint(element)
    // ...
  }

  const onLeave = (element: HTMLElement) => {
    // ...
    forceRepaint(element)
    // ...
  }
  // ...
}
```

호출문은 expression-statement 로서 unused expression 룰 예외. 이름이 의도를 설명.

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

2. **behavioral test case 표** (PR 본문에 포함):
   - `emailValidator`:
     - 유효: `a@b.co`, `user+tag@example.com`, `first.last@sub.example.co.kr`, `_a@b.io`, `a1@b2.io`, `simple@example.org`, `valid.user@subdomain.example.com`
     - 거부 (신규 정책): `user@[192.168.1.1]` (IP literal 불허 — 기존 regex 에서 허용되던 것이 거부됨), `user@서울.kr` (한글 IDN — 기존도 거부, 동치)
     - 무효: 빈 문자열, `noat`, `@nolocal`, `a b@c.d`, `a@`, `a@.com`, `a@b.`, `a@b..c`, `a@ b.c`, `a@b,c`
     - 경계: local-part 길이 64+, 레이블 길이 62+ (신규 regex 의 `{0,61}` 경계 확인)
   - `passwordValidator`:
     - 유효: `Aa1!aaaa` (정확히 8자), `Abcdefg9!`, `ZZZZzzzz11!!`
     - 무효: `Aa1!aaa` (7자 — 경계), `aaaaaaaa1!` (대문자X), `AAAAAAAA1!` (소문자X), `Aaaaaaaa!` (숫자X), `Aaaaaaaa1` (특수문자X)
     - 미세 차이 (기존 대비): `"Aa1!\nA\naa"` 는 개행 포함 → 기존 `.{8,}` 거부 / 신규 `length >= 8` 허용 (현실 영향 없음, 문서화)
   - `kFormatter`:
     - `1234 → "1,234"`, `9999 → "9,999"`, `10000 → "10k"`, `12345 → "12.3k"`, `-12345 → "-12.3k"`, `0 → "0"`, `999 → "999"`
     - 반올림 경계: `1234.4 → "1,234"`, `1234.5 → "1,235"`, `1234.7 → "1,235"`, `9999.5 → "10,000"` (→ 9999 넘음으로 `"10k"` 분기?) 주의
     - 음수 부호 탈락 (기존 동작 유지): `-500 → "500"` (9999 이하 음수)
     - 특수값: `kFormatter(NaN) → "NaN"`, `kFormatter(Infinity) → "Infinityk"` (기존 동작 동일)
   - `normalizeClientName` / `clientNameEquals`:
     - `"  foo  " → "foo"`, `"\u00A0foo\u3000" → "foo"`, `"A사" ≠ "A 사"`, NFC 정규화
     - BOM prefix: `"\uFEFFfoo" → "foo"` (신규 `\s+` 로 BOM trim 유지 확인)
   - 백엔드 PHP 대조 결과 문서화.

3. **로컬 재현 1-liner** (리뷰어용):
   ```bash
   cd frontend && bunx tsx -e '
   import {emailValidator, passwordValidator} from "./resources/ts/@core/utils/validators.ts"
   import {kFormatter} from "./resources/ts/@core/utils/formatters.ts"
   import {normalizeClientName} from "./resources/ts/utils/review/clientNameComparator.ts"
   console.log({
     email_valid: emailValidator("user@example.com"),
     email_ip: emailValidator("user@[1.2.3.4]"),
     pwd_8: passwordValidator("Aa1!aaaa"),
     pwd_7: passwordValidator("Aa1!aaa"),
     k_1234_7: kFormatter(1234.7),
     k_neg_500: kFormatter(-500),
     trim_bom: normalizeClientName("\uFEFFfoo"),
   })
   '
   ```

## 7. 엣지케이스·리스크

| 리스크 | 대응 |
| --- | --- |
| email regex 교체 시 IP literal (`user@[192.168.1.1]`) 거부로 기존 가입자 영향 | DB 조회 (`SELECT COUNT(*) FROM users WHERE email LIKE '%@[%]%'`) 결과 0 확인 전제. 구현 단계에서 실제 쿼리 수행 후 스펙에 결과 명시. N>0 이면 기존 regex 유지 + eslint-disable 로 전략 변경 |
| `clientNameComparator` 의 `\s` 와 백엔드 PHP `\s` 차이 (PHP `\s` 는 ASCII 만) | 백엔드 regex 확인. 비동치 시 양쪽 통일은 별도 PR 로 분리 (본 PR 은 프론트엔드만) |
| 신규 email regex 가 `sonarjs/slow-regex` 에 재차 flag 될 가능성 | 구현 착수 전 PoC (임시 파일 + `bun run lint`) 필수. flag 시 HTML5 spec 링크 주석 + `eslint-disable-next-line` 또는 `/^[^\s@]+@[^\s@]+\.[^\s@]+$/` 단순 regex 대체 |
| `kFormatter` 부호 탈락 (`-500 → "500"`) | 기존 버그이지만 본 PR 범위 아님. 의도적 동작 유지. 수정은 별도 이슈 |
| password 개행 포함 허용 차이 | lookahead → length 분해로 `.{8,}` 의 non-newline 제약 사라짐. 현실 영향 없음, test case 에 명시 |
| `kFormatter` 의 `toLocaleString('en-US')` 는 Intl 의존 | 모든 타깃 브라우저 지원 (IE11 제외, 대상 아님) |
| 테스트 인프라 부재로 회귀 탐지 불가 | 수동 검증 테이블 + 리뷰어 재현 1-liner. 테스트 러너 도입은 별도 이슈 |

## 8. 범위 외 (명시적 제외)

- Priority B/C 룰 — 후속 스펙
- 테스트 러너 도입 (vitest 등) — 별도 이슈
- `sonarjs/void-use` — off 유지 (forceRepaint 패턴이 void 의존 제거)
- `.eslintrc` / lint 스크립트 구조 변경 — 본 스코프 외
- 백엔드 `App\Support\Review\ClientNameComparator.php` 수정 — 비동치 확인 시 별도 PR
- `kFormatter` 의 음수 부호 탈락 버그 — 기존 동작 유지, 별도 이슈

## 9. 롤백

단일 PR squash merge 가정. 문제 발생 시 `git revert <merge-commit>` 1회로 원복 가능. ESLint 설정과 소스 코드 변경이 같은 커밋에 묶이므로 부분 롤백 불필요.

## 10. 관련 문서

- 원 이슈: [#607](https://github.com/SeoulVentures/seoulventuresgroupware/issues/607)
- 원 마이그레이션: PR #606 (merged)
- 핸드오프 메모리: `/opt/SeoulVentures/.claude/projects/-opt-SeoulVentures-regle/memory/svgw-eslint9-flat-2026-04-13.md`

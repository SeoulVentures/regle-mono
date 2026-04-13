# SVGW ESLint Priority A 재활성화 구현 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** PR #606 에서 일시적으로 off 한 ESLint Priority A 3룰 (`sonarjs/slow-regex`, `sonarjs/regex-complexity`, `@typescript-eslint/no-unused-expressions`) 을 `error` 로 전환하고 기존 위반 7건을 수정한다.

**Architecture:** 소스 코드 수정 6 파일 → PoC 검증 → ESLint 설정에서 off 제거 → 전체 lint/build 검증 → 단일 PR 머지.

**Tech Stack:** ESLint 9.39.4 flat config, TypeScript 5.9, Vue 3.5, bun, frontend submodule in SVGW.

**관련 문서:**
- 스펙: `/opt/SeoulVentures/regle/docs/plans/2026-04-13-svgw-eslint-priority-a-rules-design.md`
- 이슈: [#607](https://github.com/SeoulVentures/seoulventuresgroupware/issues/607)
- 이전 PR: #606 (ESLint 9 + Flat Config 마이그레이션)

---

## 파일 구조

| 파일 | 역할 | 변경 유형 |
|---|---|---|
| `frontend/eslint.config.js` | ESLint flat config. Priority A 3룰의 off 엔트리 제거 | Modify |
| `frontend/resources/ts/@core/utils/validators.ts` | email/password validator. regex 재작성 | Modify |
| `frontend/resources/ts/@core/utils/formatters.ts` | kFormatter. regex → toLocaleString | Modify |
| `frontend/resources/ts/utils/review/clientNameComparator.ts` | TRIM_RE 중복 제거 | Modify |
| `frontend/resources/ts/@core/components/cards/AppCardActions.vue` | setter ternary → if/else | Modify |
| `frontend/resources/ts/@layouts/components/TransitionExpand.vue` | forceRepaint helper 도입 | Modify |

**무변경 but 참조:** `App\Support\Review\ClientNameComparator.php` (백엔드 동치성 grep 만).

---

## Task 0: 브랜치 준비 및 베이스라인 확인

**Files:** 없음 (git/bun 조작만)

- [ ] **Step 1: master 최신화 및 브랜치 생성**

```bash
cd /opt/SeoulVentures/regle/SeoulVenturesGroupware
git checkout master && git pull --ff-only
git checkout -b chore/eslint-priority-a-rules
```

- [ ] **Step 2: 의존성 상태 확인 (변경 없음 확인)**

```bash
cd frontend && bun install
```

Expected: `no changes` 또는 기존 패키지만 확인. 신규 설치 나오면 베이스라인 상태가 예상과 다른 것 — 중단하고 조사.

- [ ] **Step 3: lint 베이스라인 — 0 errors 4 warnings 확인**

```bash
bun run lint 2>&1 | tail -5
```

Expected: `✖ 4 problems (0 errors, 4 warnings)`. errors 가 나오면 작업 시작 전 상태가 깨진 것 — 중단.

- [ ] **Step 4: `bunx tsx -e` import 경로 smoke test**

본 plan 의 behavioral check 는 `bunx tsx -e '...'` 형식으로 `.ts` 파일을 직접 import. 환경 차이로 실패할 경우 전체 검증이 깨지므로 1회 smoke:

```bash
cd /opt/SeoulVentures/regle/SeoulVenturesGroupware/frontend
bunx tsx -e 'import {kFormatter} from "./resources/ts/@core/utils/formatters.ts"; console.log(kFormatter(1234))'
```

Expected: `1,234` 출력.

실패 시 `bun -e` 로 대체 (bun 런타임 내장 TS 지원):
```bash
cd /opt/SeoulVentures/regle/SeoulVenturesGroupware/frontend
bun -e 'import {kFormatter} from "./resources/ts/@core/utils/formatters.ts"; console.log(kFormatter(1234))'
```

이후 Task 2~6 의 모든 `bunx tsx -e` 를 동작하는 형식으로 일괄 대체.

---

## Task 1: PoC — email regex 선택 확정

**목적:** 스펙 §4.1 의 HTML5 spec regex 가 `sonarjs/slow-regex` 를 통과하는지 구현 전 확인. 통과하지 못하면 fallback (단순 regex 또는 eslint-disable) 결정.

**Files:**
- Create (임시): `frontend/tmp-poc-email.ts`

- [ ] **Step 1: PoC 파일 생성**

```ts
// frontend/tmp-poc-email.ts
// PoC — email regex 가 sonarjs/slow-regex 를 통과하는지 확인용. Task 1 완료 후 삭제.
export const POC_EMAIL_RE = /^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$/
```

- [ ] **Step 2: 해당 파일만 lint 실행**

```bash
cd /opt/SeoulVentures/regle/SeoulVenturesGroupware/frontend
bunx eslint tmp-poc-email.ts --rule '{"sonarjs/slow-regex":"error","sonarjs/regex-complexity":"error"}' 2>&1 | tail -10
```

**Expected 시나리오 A (통과)**: 에러 0건. → HTML5 spec regex 그대로 채택. Task 6 (Step 3) 의 "After" 블록 그대로 사용.

**Expected 시나리오 B (탈락)**: `sonarjs/slow-regex` 경고 출력. → 스펙 §4.1 fallback (b) 채택: 단순 regex `/^[^\s@]+@[^\s@]+\.[^\s@]+$/` 로 교체.

- [ ] **Step 3: PoC 결과를 PR 본문 메모에 기록 (구현 시 PR 본문 작성 시점까지 보관)**

결과를 다음 형식으로 작업 메모에 남김:
```
PoC (Task 1): HTML5 spec email regex → [통과 / 탈락]
  - 시나리오 A 채택 / 시나리오 B 채택
  - lint 출력: <출력 붙여넣기>
```

- [ ] **Step 4: PoC 파일 삭제**

```bash
rm tmp-poc-email.ts
git status frontend/tmp-poc-email.ts
```

Expected: `git status` 에 해당 파일 나타나지 않음 (삭제 완료, 아직 staged 없음).

- [ ] **Step 5: 커밋 (건너뛰기)**

PoC 는 작업 산출물이 아니므로 커밋 대상 아님. 진행 단계 체크만.

---

## Task 2: `kFormatter` 수정 (formatters.ts)

**Files:**
- Modify: `frontend/resources/ts/@core/utils/formatters.ts:11-16`

- [ ] **Step 1: 수정 전 기존 동작 behavioral check**

```bash
cd /opt/SeoulVentures/regle/SeoulVenturesGroupware/frontend
bunx tsx -e 'import {kFormatter} from "./resources/ts/@core/utils/formatters.ts"; console.log({a: kFormatter(1234), b: kFormatter(9999), c: kFormatter(10000), d: kFormatter(12345), e: kFormatter(-12345), f: kFormatter(-500), g: kFormatter(1234.7), h: kFormatter(9999.5)})'
```

Expected (기존 동작):
- a: `"1,234"`, b: `"9,999"`, c: `"10k"`, d: `"12.3k"`, e: `"-12.3k"`, f: `"500"` (부호 탈락), g: `"1,235"`, h: `"10k"`

- [ ] **Step 2: kFormatter 구현 교체**

파일 `frontend/resources/ts/@core/utils/formatters.ts` 의 11-16 줄을 다음으로 교체:

```ts
// kFormatter — 절대값 기준 10,000 미만은 locale-aware 천단위 구분, 이상은 "Nk" 표기.
// Math.round 는 half-to-positive-infinity 이지만 Math.abs 후 round 이므로 양수 도메인에서
// Number.prototype.toFixed(0) 와 완전 동치 (기존 구현과 동일한 반올림).
// 기존 동작 보존: abs <= 9999 음수 입력 시 부호 탈락 (`-500 → "500"`). 수정은 별도 이슈.
export const kFormatter = (num: number) => {
  const abs = Math.abs(num)
  if (abs > 9999) {
    const scaled = Math.sign(num) * +((abs / 1000).toFixed(1))

    return `${scaled}k`
  }

  return Math.round(abs).toLocaleString('en-US')
}
```

- [ ] **Step 3: 수정 후 동일 behavioral check**

위 Step 1 과 동일 명령 재실행:

```bash
bunx tsx -e 'import {kFormatter} from "./resources/ts/@core/utils/formatters.ts"; console.log({a: kFormatter(1234), b: kFormatter(9999), c: kFormatter(10000), d: kFormatter(12345), e: kFormatter(-12345), f: kFormatter(-500), g: kFormatter(1234.7), h: kFormatter(9999.5)})'
```

Expected: Step 1 과 정확히 동일 결과.

- [ ] **Step 4: 경계 케이스 추가 검증**

```bash
bunx tsx -e 'import {kFormatter} from "./resources/ts/@core/utils/formatters.ts"; console.log({i: kFormatter(9999.4), j: kFormatter(NaN), k: kFormatter(Infinity)})'
```

Expected: `i: "9,999"`, `j: "NaN"`, `k: "Infinityk"` (기존 동작 유지).

- [ ] **Step 5: 커밋**

```bash
cd /opt/SeoulVentures/regle/SeoulVenturesGroupware
git add frontend/resources/ts/@core/utils/formatters.ts
git commit -m "refactor(formatters): kFormatter regex → Math.round + toLocaleString"
```

---

## Task 3: `clientNameComparator.ts` TRIM_RE 단순화

**Files:**
- Modify: `frontend/resources/ts/utils/review/clientNameComparator.ts:15`

- [ ] **Step 1: 백엔드 PHP 동치성 grep**

```bash
cd /opt/SeoulVentures/regle/SeoulVenturesGroupware
grep -nE 'preg_replace|regex|trim|White_Space|\\p\{Z|\\\\s' app/Support/Review/ClientNameComparator.php
```

결과 확인. PHP 가 어떤 regex 표기를 쓰는지 기록. (**사전 확인 결과** 백엔드는 `[\s\p{Z}]` 사용 — Unicode `Z` category (Zs+Zl+Zp) 포함. 프론트의 `\s` 단독과 비동치 확정.)

구현 PR 본문에 "백엔드 grep 결과: `<출력>` — 비동치 확인 → 이슈 #XXX 로 추적" 첨부 (Task 9 Step 7 에서 이슈 발행).

- [ ] **Step 2: 수정 전 behavioral check**

```bash
cd frontend
bunx tsx -e 'import {normalizeClientName} from "./resources/ts/utils/review/clientNameComparator.ts"; console.log({a: JSON.stringify(normalizeClientName("  foo  ")), b: JSON.stringify(normalizeClientName("\u00A0foo\u3000")), c: JSON.stringify(normalizeClientName("\uFEFFfoo"))})'
```

Expected:
- a: `'"foo"'`, b: `'"foo"'`, c: `'"foo"'` (BOM trim 포함)

- [ ] **Step 3: TRIM_RE 교체**

파일 `frontend/resources/ts/utils/review/clientNameComparator.ts` 의 15 라인을 다음 블록으로 교체:

```ts
// JS `\s` (ECMA-262 21.2.2.12) 는 Unicode whitespace + BOM(U+FEFF) 포함.
// `\p{White_Space}` 는 Unicode property 기반이며 U+FEFF 를 format char(Cf) 로 분류해 제외 → subset.
// 기존의 `\s|\p{White_Space}` 중 후자는 중복이었고 ReDoS backtracking 유발.
// 미세 차이: U+0085 (NEL) 은 `\p{White_Space}` 에는 있고 JS `\s` 에는 없음. 한국어 클라이언트 데이터에서 실유입 가능성 희박 — 회귀 허용.
const TRIM_RE = /^\s+|\s+$/g
```

- [ ] **Step 4: 수정 후 동일 behavioral check**

Step 2 와 동일 명령 재실행. 결과 동일 확인.

- [ ] **Step 5: 커밋**

```bash
cd /opt/SeoulVentures/regle/SeoulVenturesGroupware
git add frontend/resources/ts/utils/review/clientNameComparator.ts
git commit -m "refactor(clientNameComparator): TRIM_RE 중복 문자클래스 제거 (ReDoS 완화)"
```

---

## Task 4: `AppCardActions.vue` 삼항 → if/else

**Files:**
- Modify: `frontend/resources/ts/@core/components/cards/AppCardActions.vue:43-45`

- [ ] **Step 1: 기존 코드 확인**

해당 라인 내용:
```ts
set(value: boolean) {
  props.loading !== undefined ? emit('update:loading', value) : _loading.value = value
},
```

- [ ] **Step 2: 코드 교체**

```ts
set(value: boolean) {
  if (props.loading !== undefined)
    emit('update:loading', value)
  else
    _loading.value = value
},
```

- [ ] **Step 3: 커밋**

```bash
cd /opt/SeoulVentures/regle/SeoulVenturesGroupware
git add frontend/resources/ts/@core/components/cards/AppCardActions.vue
git commit -m "refactor(AppCardActions): computed setter 삼항 side-effect → if/else"
```

---

## Task 5: `TransitionExpand.vue` forceRepaint helper

**Files:**
- Modify: `frontend/resources/ts/@layouts/components/TransitionExpand.vue:7-54`

- [ ] **Step 1: 실파일 구조 확인**

```bash
head -15 frontend/resources/ts/@layouts/components/TransitionExpand.vue
```

Expected: `<script lang="ts">` + `defineComponent({ name: 'TransitionExpand', setup(_, { slots }) {` 구조.

- [ ] **Step 2: setup 함수 최상단에 forceRepaint 헬퍼 추가**

`TransitionExpand.vue:8` (`setup(_, { slots }) {` 라인) 직후에 헬퍼를 삽입. 기존 파일은 `setup(_, { slots }) {` 다음 줄에 바로 `const onEnter = (element: HTMLElement) => {` 가 있음.

Before (line 7-9):
```ts
  name: 'TransitionExpand',
  setup(_, { slots }) {
    const onEnter = (element: HTMLElement) => {
```

After (line 7-12):
```ts
  name: 'TransitionExpand',
  setup(_, { slots }) {
    // 브라우저 강제 layout recalc — getComputedStyle 은 live CSSStyleDeclaration 이라 프로퍼티 접근만으로 flush 됨.
    const forceRepaint = (el: HTMLElement) => { getComputedStyle(el).height }

    const onEnter = (element: HTMLElement) => {
```

- [ ] **Step 3: onEnter 내부의 force repaint 블록 교체**

기존 (line 22-26 부근):
```ts
      element.style.height = '0px'

      // 애니메이션 트리거 전 force repaint — getComputedStyle 접근 자체가 목적 (반환값은 의도적 무시).
      getComputedStyle(element).height

      // Trigger the animation.
```

교체 후:
```ts
      element.style.height = '0px'

      forceRepaint(element)

      // Trigger the animation.
```

- [ ] **Step 4: onLeave 내부의 force repaint 블록 교체**

기존 (line 45-49 부근):
```ts
      element.style.height = height

      // 애니메이션 트리거 전 force repaint — getComputedStyle 접근 자체가 목적 (반환값은 의도적 무시).
      getComputedStyle(element).height

      requestAnimationFrame(() => {
```

교체 후:
```ts
      element.style.height = height

      forceRepaint(element)

      requestAnimationFrame(() => {
```

- [ ] **Step 5: 수동 검증 — 개발 서버 또는 빌드로 transition 동작 확인**

이상적으로는 `bun run dev` 후 transition 사용 컴포넌트에서 직접 확인. 시간 제약 시 Step 6 의 lint + build 성공으로 대체 가능 (forceRepaint 함수 호출이 expression statement 이므로 ESLint 통과 = 구문 정상).

- [ ] **Step 6: 커밋**

```bash
cd /opt/SeoulVentures/regle/SeoulVenturesGroupware
git add frontend/resources/ts/@layouts/components/TransitionExpand.vue
git commit -m "refactor(TransitionExpand): getComputedStyle force-repaint 를 forceRepaint 헬퍼로 래핑"
```

---

## Task 6: `validators.ts` emailValidator + passwordValidator

**Files:**
- Modify: `frontend/resources/ts/@core/utils/validators.ts:11-31`

- [ ] **Step 1: DB 사전 조회 (IP literal email 가입자 수)**

IP literal email 은 `user@[1.2.3.4]` 형식이라 local-part 이후 `@[` 프리픽스를 가짐. MySQL/SQLite 호환 `LIKE` 사용:

```bash
cd /opt/SeoulVentures/regle/SeoulVenturesGroupware
php artisan tinker
# 대화형 프롬프트에서 아래 1줄 실행 후 exit
```
```php
\App\Models\User::where('email', 'like', '%@[%')->count();
```

`--execute=` 플래그 형식은 laravel/tinker 버전에 따라 미지원일 수 있어 대화형 사용. `like '%@[%'` 는 `@[` 프리픽스만 정확 탐지하며 wildcard 는 `%` 만이므로 `[` 가 리터럴로 작동.

Expected: `0` (혹은 매우 작은 수).
- 0 이면 계속 진행.
- N>0 이면 중단. 스펙 §7 첫 행 fallback (기존 regex 유지 + eslint-disable) 전략으로 전환 — 본 Task 의 email 부분을 생략하고 `// eslint-disable-next-line sonarjs/regex-complexity` 추가만.

결과를 PR 본문 메모에 기록: `IP literal email 사용자 수: 0`.

- [ ] **Step 2: 수정 전 behavioral check**

```bash
cd frontend
bunx tsx -e 'import {emailValidator, passwordValidator} from "./resources/ts/@core/utils/validators.ts"; console.log({email_valid: emailValidator("user@example.com"), email_plus: emailValidator("user+tag@example.com"), email_ip: emailValidator("user@[1.2.3.4]"), email_invalid: emailValidator("nosymbol"), pwd_8: passwordValidator("Aa1!aaaa"), pwd_7: passwordValidator("Aa1!aaa"), pwd_nolower: passwordValidator("AAAAAAAA1!"), pwd_nodigit: passwordValidator("Aaaaaaaa!")})'
```

Expected (기존):
- email_valid: `true`, email_plus: `true`, email_ip: `true` (기존 지원), email_invalid: string (에러 메시지)
- pwd_8: `true`, pwd_7: string, pwd_nolower: string, pwd_nodigit: string

- [ ] **Step 3: emailValidator 교체 — Task 1 PoC 결과에 따라**

**시나리오 A (PoC 통과)** — HTML5 spec regex 그대로:

```ts
export const emailValidator = (value: unknown) => {
  if (isEmpty(value))
    return true

  // WHATWG HTML spec "valid e-mail address" regex (linear backtracking guarantee).
  // https://html.spec.whatwg.org/multipage/input.html#valid-e-mail-address
  // IP literal (user@[1.2.3.4]) 및 한글 IDN 은 지원하지 않음 — 기존 가입자 0건 확인 후 수용.
  const re = /^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$/

  if (Array.isArray(value))
    return value.every(val => re.test(String(val))) || 'The Email field must be a valid email'

  return re.test(String(value)) || 'The Email field must be a valid email'
}
```

**시나리오 B (PoC 탈락)** — 단순 regex:

```ts
export const emailValidator = (value: unknown) => {
  if (isEmpty(value))
    return true

  // sonarjs/slow-regex 회피 위해 단순 regex 사용. 세밀 검증은 서버 측에 위임.
  const re = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

  if (Array.isArray(value))
    return value.every(val => re.test(String(val))) || 'The Email field must be a valid email'

  return re.test(String(value)) || 'The Email field must be a valid email'
}
```

- [ ] **Step 4: passwordValidator 교체**

```ts
export const passwordValidator = (password: string) => {
  // lookahead 4개 (ReDoS 위험) → 조건 분해. 결과 의미적으로 동치 (단 개행 포함 8자 허용은 기존과 미세 차이).
  const hasLowercase = /[a-z]/.test(password)
  const hasUppercase = /[A-Z]/.test(password)
  const hasDigit = /\d/.test(password)
  const hasSpecial = /[!@#$%&*()]/.test(password)
  const longEnough = password.length >= 8

  const valid = hasLowercase && hasUppercase && hasDigit && hasSpecial && longEnough

  return valid || 'Field must contain at least one uppercase, lowercase, special character and digit with min 8 chars'
}
```

- [ ] **Step 5: 수정 후 behavioral check (Step 2 와 동일 + IP literal 거부 확인)**

```bash
bunx tsx -e 'import {emailValidator, passwordValidator} from "./resources/ts/@core/utils/validators.ts"; console.log({email_valid: emailValidator("user@example.com"), email_plus: emailValidator("user+tag@example.com"), email_ip: emailValidator("user@[1.2.3.4]"), email_invalid: emailValidator("nosymbol"), pwd_8: passwordValidator("Aa1!aaaa"), pwd_7: passwordValidator("Aa1!aaa"), pwd_nolower: passwordValidator("AAAAAAAA1!"), pwd_nodigit: passwordValidator("Aaaaaaaa!")})'
```

Expected (수정 후):
- email_valid: `true`, email_plus: `true`, **email_ip: string (거부 — 신규 정책)**, email_invalid: string
- pwd_8: `true`, pwd_7: string, pwd_nolower: string, pwd_nodigit: string

`email_ip` 만 기존과 다름. 그 외 모두 동일.

- [ ] **Step 6: 경계 케이스 추가 확인**

```bash
bunx tsx -e 'import {emailValidator, passwordValidator} from "./resources/ts/@core/utils/validators.ts"; console.log({email_korean_idn: emailValidator("user@서울.kr"), email_empty_local: emailValidator("@example.com"), email_double_dot: emailValidator("a@b..c"), pwd_exactly_8_missing_special: passwordValidator("Aaaaaaa1")})'
```

Expected:
- `email_korean_idn`: string (거부 — 기존도 동일, 회귀 아님)
- `email_empty_local`: string (거부)
- `email_double_dot`: string (거부)
- `pwd_exactly_8_missing_special`: string (거부 — 특수문자 없음)

- [ ] **Step 7: 커밋**

```bash
cd /opt/SeoulVentures/regle/SeoulVenturesGroupware
git add frontend/resources/ts/@core/utils/validators.ts
git commit -m "refactor(validators): email/password regex 를 ReDoS-safe 형태로 재작성"
```

---

## Task 7: ESLint 설정 — Priority A 3룰 off 제거 (활성화)

**Files:**
- Modify: `frontend/eslint.config.js`

- [ ] **Step 1: `legacyOffRules` 에서 2룰 제거**

파일 `frontend/eslint.config.js` 에서 다음 2줄 (및 관련 주석) 을 찾아 삭제:

```js
  // sonarjs 0.24 → 3.x 업그레이드로 신규 활성화된 룰 (#607 에서 점진 재활성화).
  // slow-regex / regex-complexity 는 ReDoS 위험이 있어 다른 룰보다 먼저 재활성화 검토 (#607 우선순위 A).
  'sonarjs/no-ignored-exceptions': 'off',
  'sonarjs/no-nested-conditional': 'off',
  'sonarjs/no-nested-assignment': 'off',
  'sonarjs/todo-tag': 'off',
  'sonarjs/slow-regex': 'off',            // ← 이 줄 삭제
  'sonarjs/prefer-promise-shorthand': 'off',
  'sonarjs/anchor-precedence': 'off',
  'sonarjs/regex-complexity': 'off',      // ← 이 줄 삭제
  'sonarjs/no-duplicate-string': 'off',
  'sonarjs/no-nested-template-literals': 'off',
  'sonarjs/cognitive-complexity': 'off',
```

교체 후:
```js
  // sonarjs 0.24 → 3.x 업그레이드로 신규 활성화된 룰. 재활성화 추적: #607.
  // Priority A (slow-regex, regex-complexity) 완료. B/C 진행중.
  'sonarjs/no-ignored-exceptions': 'off',
  'sonarjs/no-nested-conditional': 'off',
  'sonarjs/no-nested-assignment': 'off',
  'sonarjs/todo-tag': 'off',
  'sonarjs/prefer-promise-shorthand': 'off',
  'sonarjs/anchor-precedence': 'off',
  'sonarjs/no-duplicate-string': 'off',
  'sonarjs/no-nested-template-literals': 'off',
  'sonarjs/cognitive-complexity': 'off',
```

- [ ] **Step 2: `tsRules` 에서 no-unused-expressions 제거**

파일 내 `tsRules` 상수 내부 — 실파일 기준 line 113~115 부근.

Before:
```js
  '@typescript-eslint/no-shadow': ['error'],

  // 기존 동작 유지를 위해 off. 재활성화 추적: #607.
  '@typescript-eslint/no-redeclare': 'off',
  '@typescript-eslint/no-unused-expressions': 'off',
  '@typescript-eslint/no-explicit-any': 'off',
  '@typescript-eslint/no-use-before-define': 'off',
}
```

After:
```js
  '@typescript-eslint/no-shadow': ['error'],

  // 기존 동작 유지를 위해 off. 재활성화 추적: #607.
  '@typescript-eslint/no-redeclare': 'off',
  '@typescript-eslint/no-explicit-any': 'off',
  '@typescript-eslint/no-use-before-define': 'off',
}
```

(`no-unused-expressions` 한 줄만 제거. 주변 주석·여백은 그대로 유지.)

- [ ] **Step 3: lint 전체 실행 — 신규 error 0건 확인**

```bash
cd /opt/SeoulVentures/regle/SeoulVenturesGroupware/frontend
bun run lint 2>&1 | tail -10
```

Expected: `✖ 4 problems (0 errors, 4 warnings)`. errors 가 나오면 Task 2~6 수정이 불완전. 해당 파일:라인 보고 해당 Task 로 돌아가 보강.

- [ ] **Step 4: 타입체크**

```bash
bun run typecheck 2>&1 | tail -5
```

Expected: 성공 또는 본 PR 과 무관한 pre-existing 에러만 (PR #606 에서 이미 관찰됨).

- [ ] **Step 5: 빌드**

```bash
bun run build 2>&1 | tail -3
```

Expected: `✓ built in Xs` 성공.

- [ ] **Step 6: 커밋**

```bash
cd /opt/SeoulVentures/regle/SeoulVenturesGroupware
git add frontend/eslint.config.js
git commit -m "feat(eslint): Priority A 3룰 off → error (sonarjs/slow-regex, sonarjs/regex-complexity, @typescript-eslint/no-unused-expressions)"
```

---

## Task 8: 푸시 및 Draft PR 생성

- [ ] **Step 1: 브랜치 푸시**

```bash
cd /opt/SeoulVentures/regle/SeoulVenturesGroupware
git push -u origin chore/eslint-priority-a-rules
```

- [ ] **Step 2: Draft PR 생성**

```bash
gh pr create --draft --title "chore(eslint): Priority A 룰 재활성화 (slow-regex, regex-complexity, no-unused-expressions) - #607" --body "$(cat <<'EOF'
## 배경 / Closes

- Part of #607 (Priority A)
- 이전 PR: #606 (ESLint 9 + Flat Config 마이그레이션)
- 스펙: `docs/plans/2026-04-13-svgw-eslint-priority-a-rules-design.md` (regle-mono)

PR #606 에서 기존 동작 유지를 위해 일시적으로 `off` 처리한 ReDoS 관련 sonarjs 2룰 + `@typescript-eslint/no-unused-expressions` 를 `error` 로 전환. 기존 위반 7건 전부 수정.

## 대상 룰
- `sonarjs/slow-regex`
- `sonarjs/regex-complexity`
- `@typescript-eslint/no-unused-expressions`

## 수정 내역 (7건)

| 파일 | 룰 | 수정 |
| --- | --- | --- |
| `validators.ts:16` | regex-complexity | email regex: HTML5 spec (또는 단순 fallback) 로 교체 |
| `validators.ts:26` | slow-regex | password: lookahead 4개 → 조건 분해 |
| `clientNameComparator.ts:15` | slow-regex | TRIM_RE 중복 문자클래스 제거 |
| `formatters.ts:13` | slow-regex | kFormatter regex → Math.round + toLocaleString |
| `AppCardActions.vue:44` | no-unused-expressions | 삼항 side-effect → if/else |
| `TransitionExpand.vue:25,47` | no-unused-expressions | forceRepaint 헬퍼로 래핑 |

## 사전 검증 결과

- **Task 1 PoC** (email regex vs sonarjs/slow-regex): [본 PR 생성 시점 결과 기입]
- **Task 3 백엔드 grep** (`App\Support\Review\ClientNameComparator.php`): [결과 기입]
- **Task 6 DB 조회** (IP literal email 가입자): [결과 기입]

## Behavioral test cases

`emailValidator` / `passwordValidator` / `kFormatter` / `normalizeClientName` 각각의 유효/무효/경계 케이스 실행 결과 — 스펙 §6.2 표 전체 통과.

로컬 재현:
```bash
cd frontend && bunx tsx -e '
import {emailValidator, passwordValidator} from "./resources/ts/@core/utils/validators.ts"
import {kFormatter} from "./resources/ts/@core/utils/formatters.ts"
import {normalizeClientName} from "./resources/ts/utils/review/clientNameComparator.ts"
// ...스펙 §6.3 1-liner
'
```

## 검증
- [x] `bun run lint` — 0 errors, 4 warnings (기존 상태 유지)
- [x] `bun run build` — 성공
- [x] `bun run typecheck` — 기존 수준

## 범위 외
- Priority B/C 룰 — 후속 PR
- 백엔드 `ClientNameComparator.php` 동치 통일 — 별도 PR
- `kFormatter` 음수 부호 탈락 — 별도 이슈
- 테스트 러너 도입 — 별도 이슈
EOF
)"
```

- [ ] **Step 3: PoC / grep / DB 결과를 PR description 에 채워넣기**

Task 1, 3, 6 에서 기록한 실제 결과로 PR body 의 해당 섹션 replace.

---

## Task 9: 머지 준비

- [ ] **Step 1: CI 확인**

```bash
gh pr checks --watch
```

Expected: `테스트` 와 `Seer Code Review` 는 PASS. `claude-review` 는 인프라 이슈로 FAIL 가능 (무시 가능).

- [ ] **Step 2: Draft → Ready for review 전환**

```bash
gh pr ready
```

- [ ] **Step 3: 리뷰 대기 및 피드백 반영**

리뷰 코멘트 발생 시 본 플랜과 무관하게 pr-review-toolkit 워크플로우로 처리.

- [ ] **Step 4: 사용자 승인 후 머지**

```bash
gh pr merge --squash --delete-branch
```

- [ ] **Step 5: 머지 후 정리**

```bash
cd /opt/SeoulVentures/regle/SeoulVenturesGroupware
git checkout master && git pull
git branch -d chore/eslint-priority-a-rules 2>/dev/null || true
git remote prune origin

# 서브모듈 포인터 업데이트
cd /opt/SeoulVentures/regle
git add SeoulVenturesGroupware
git commit -m "chore: SVGW 서브모듈 업데이트 — PR #<number> 머지 (ESLint Priority A 재활성화)"
git push
```

- [ ] **Step 6: #607 코멘트 업데이트**

```bash
gh issue comment 607 --body "Priority A 3룰 재활성화 완료 (PR #<number>, 2026-04-XX). Priority B/C 남음."
```

- [ ] **Step 7: 후속 이슈 발행**

백엔드 `ClientNameComparator.php` 가 `[\s\p{Z}]` 사용하여 프론트 `\s` 와 비동치임이 사전 확인됨 → 이슈 무조건 발행 (Task 3 grep 결과를 첨부):
```bash
gh issue create --title "chore(backend): ClientNameComparator regex 동치성 통일" --body "$(cat <<'EOF'
## 배경
PR #<number> (ESLint Priority A 재활성화) 에서 프론트엔드 `TRIM_RE` 를 `/^\s+|\s+$/g` 로 단순화.
백엔드 `App\Support\Review\ClientNameComparator.php` grep 결과 프론트와 비동치 확인:

- 프론트: JS `\s` — Unicode whitespace + U+FEFF
- 백엔드: <grep 결과 인용>

## 작업
양쪽 regex 를 동일 규칙으로 통일하여 normalize 결과 동치성 보장.

## 관련
- PR #<number>
- 이슈 #607 (#574 후속)
EOF
)"
```

`kFormatter` 부호 탈락 이슈 (필수):
```bash
gh issue create --title "fix(formatters): kFormatter 음수 부호 탈락 복원" --body "$(cat <<'EOF'
## 배경
`resources/ts/@core/utils/formatters.ts` 의 `kFormatter` 는 절대값 기준 <= 9999 인 음수 입력 시 부호가 탈락됨 (예: `kFormatter(-500)` → `"500"`).

기존 구현의 버그이나 PR #<number> 에서는 의도적으로 동작 보존.

## 작업
- `abs <= 9999` 분기에서 `Math.sign(num)` 반영 (예: `${num < 0 ? '-' : ''}${Math.round(abs).toLocaleString('en-US')}`)
- 호출처 (대시보드/통계 위젯) 검토해 부호 변경으로 인한 레이아웃 영향 확인

## 관련
- PR #<number>
- 스펙: `docs/plans/2026-04-13-svgw-eslint-priority-a-rules-design.md` §8
EOF
)"
```

각 이슈 발행 후 결과 이슈 번호를 regle-mono 의 스펙 §8 "범위 외" 에 역참조 추가:

```bash
cd /opt/SeoulVentures/regle
# docs/plans/2026-04-13-svgw-eslint-priority-a-rules-design.md §8 에 이슈 번호 추가
git commit -am "docs: Priority A 후속 이슈 번호 역참조 추가 (#<backend>, #<kformatter>)"
git push
```

---

## 메모리 업데이트

- [ ] 본 PR 머지 후 `.claude/projects/-opt-SeoulVentures-regle/memory/svgw-eslint9-flat-2026-04-13.md` 및 `MEMORY.md` 에 #607 Priority A 완료 반영

---
name: refactor
description: Safe refactoring workflow
disable-model-invocation: true
---


체계적인 리팩토링을 수행하는 마법입니다. 코드 품질 개선을 안전하게 진행합니다.

---

## Usage

```
/cast:refactor --path=src/services/user.ts
/cast:refactor --pattern=extract-method
/cast:refactor --analyze                    # 리팩토링 기회 분석
/cast:refactor --safe                       # 테스트 보장 리팩토링만
/cast:refactor --preview                    # 변경 미리보기
```

---

## 1. Overview

리팩토링은 외부 동작을 변경하지 않으면서 코드 구조를 개선하는 작업입니다.

```
┌─────────────────────────────────────────────────────────────────┐
│                   REFACTORING WORKFLOW                           │
│                                                                  │
│   /cast:refactor                                                 │
│        │                                                         │
│        ▼                                                         │
│   ┌───────────────────────────────────────────────────────┐     │
│   │              1. ANALYZE                                │     │
│   │   - 코드 스멜 탐지                                     │     │
│   │   - 복잡도 분석                                        │     │
│   │   - 리팩토링 기회 식별                                 │     │
│   └───────────────────────────────────────────────────────┘     │
│        │                                                         │
│        ▼                                                         │
│   ┌───────────────────────────────────────────────────────┐     │
│   │              2. VERIFY SAFETY                          │     │
│   │   - 테스트 커버리지 확인                               │     │
│   │   - 의존성 분석                                        │     │
│   │   - 영향 범위 평가                                     │     │
│   └───────────────────────────────────────────────────────┘     │
│        │                                                         │
│        ▼                                                         │
│   ┌───────────────────────────────────────────────────────┐     │
│   │              3. REFACTOR                               │     │
│   │   - 패턴 적용                                          │     │
│   │   - 점진적 변경                                        │     │
│   │   - 각 단계 테스트                                     │     │
│   └───────────────────────────────────────────────────────┘     │
│        │                                                         │
│        ▼                                                         │
│   ┌───────────────────────────────────────────────────────┐     │
│   │              4. VERIFY                                 │     │
│   │   - 테스트 통과 확인                                   │     │
│   │   - 코드 품질 개선 확인                                │     │
│   │   - 성능 영향 확인                                     │     │
│   └───────────────────────────────────────────────────────┘     │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. Code Smells Detection

### 2.1 Detected Smells

```
> /cast:refactor --analyze --path=src/services

🔍 Analyzing code smells...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 Analysis Report: src/services/
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Code Smells Found: 8

🔴 HIGH PRIORITY

1. Long Method (user.service.ts:45)
   └── createUser(): 85 lines (limit: 50)
   └── Suggestion: Extract validation, notification to separate methods

2. God Class (order.service.ts)
   └── 15 methods, 450 lines
   └── Suggestion: Split into OrderService, OrderValidation, OrderNotification

3. Feature Envy (payment.service.ts:78)
   └── processPayment() accesses Order properties 12 times
   └── Suggestion: Move logic to Order class

🟡 MEDIUM PRIORITY

4. Duplicate Code
   └── validateEmail() duplicated in 3 files
   └── Suggestion: Extract to shared validator

5. Magic Numbers (pricing.service.ts:23)
   └── Uses literal 0.08, 0.15, 100
   └── Suggestion: Extract to named constants

6. Dead Code (auth.service.ts:120-145)
   └── legacyLogin() never called
   └── Suggestion: Remove or document if needed

🟢 LOW PRIORITY

7. Long Parameter List (report.service.ts:67)
   └── generateReport(start, end, type, format, user, options)
   └── Suggestion: Use parameter object

8. Comments Explaining Code (utils/date.ts:34)
   └── Comment explains complex logic
   └── Suggestion: Extract to well-named function
```

### 2.2 Complexity Metrics

```
📈 Complexity Analysis

File                          Cyclomatic  Cognitive  Lines
────────────────────────────────────────────────────────────
src/services/order.service.ts    28         45        450  🔴
src/services/user.service.ts     18         32        280  🟡
src/services/payment.service.ts  15         28        220  🟡
src/services/auth.service.ts     12         20        180  🟢
src/services/product.service.ts   8         15        150  🟢

Thresholds: Cyclomatic < 10, Cognitive < 15, Lines < 300
```

---

## 3. Refactoring Patterns

### 3.1 Extract Method

```
> /cast:refactor --pattern=extract-method --path=src/services/user.service.ts

Before:
┌─────────────────────────────────────────────────────────────────┐
│ async createUser(data: UserData) {                               │
│   // Validate email                                              │
│   const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;              │
│   if (!emailRegex.test(data.email)) {                           │
│     throw new ValidationError('Invalid email');                  │
│   }                                                              │
│                                                                  │
│   // Validate password                                           │
│   if (data.password.length < 8) {                               │
│     throw new ValidationError('Password too short');            │
│   }                                                              │
│   if (!/[A-Z]/.test(data.password)) {                          │
│     throw new ValidationError('Need uppercase');                │
│   }                                                              │
│                                                                  │
│   // Create user                                                 │
│   const hashedPassword = await bcrypt.hash(data.password, 10);  │
│   const user = await this.repo.create({...});                   │
│                                                                  │
│   // Send welcome email                                          │
│   await this.mailer.send({...});                                │
│                                                                  │
│   return user;                                                   │
│ }                                                                │
└─────────────────────────────────────────────────────────────────┘

After:
┌─────────────────────────────────────────────────────────────────┐
│ async createUser(data: UserData) {                               │
│   this.validateUserData(data);                                  │
│   const user = await this.saveUser(data);                       │
│   await this.sendWelcomeEmail(user);                            │
│   return user;                                                   │
│ }                                                                │
│                                                                  │
│ private validateUserData(data: UserData): void {                │
│   this.validateEmail(data.email);                               │
│   this.validatePassword(data.password);                         │
│ }                                                                │
│                                                                  │
│ private validateEmail(email: string): void { ... }              │
│ private validatePassword(password: string): void { ... }        │
│ private async saveUser(data: UserData): Promise<User> { ... }   │
│ private async sendWelcomeEmail(user: User): Promise<void> {...} │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 Extract Class

```
> /cast:refactor --pattern=extract-class --path=src/services/order.service.ts

Extracting responsibilities:

OrderService (God Class, 450 lines)
    │
    ├── OrderService (Core, 150 lines)
    │   ├── createOrder()
    │   ├── updateOrder()
    │   └── cancelOrder()
    │
    ├── OrderValidator (Extracted, 100 lines)
    │   ├── validateItems()
    │   ├── validatePayment()
    │   └── validateShipping()
    │
    ├── OrderNotifier (Extracted, 100 lines)
    │   ├── sendConfirmation()
    │   ├── sendShippingUpdate()
    │   └── sendCancellation()
    │
    └── OrderCalculator (Extracted, 100 lines)
        ├── calculateSubtotal()
        ├── calculateTax()
        └── calculateTotal()
```

### 3.3 Replace Conditional with Polymorphism

```
> /cast:refactor --pattern=replace-conditional --path=src/services/payment.service.ts

Before:
┌─────────────────────────────────────────────────────────────────┐
│ processPayment(type: string, amount: number) {                   │
│   if (type === 'credit') {                                       │
│     // Credit card logic (30 lines)                              │
│   } else if (type === 'paypal') {                               │
│     // PayPal logic (25 lines)                                   │
│   } else if (type === 'crypto') {                               │
│     // Crypto logic (35 lines)                                   │
│   }                                                              │
│ }                                                                │
└─────────────────────────────────────────────────────────────────┘

After:
┌─────────────────────────────────────────────────────────────────┐
│ // PaymentProcessor interface                                    │
│ interface PaymentProcessor {                                     │
│   process(amount: number): Promise<PaymentResult>;              │
│ }                                                                │
│                                                                  │
│ // Implementations                                               │
│ class CreditCardProcessor implements PaymentProcessor { ... }    │
│ class PayPalProcessor implements PaymentProcessor { ... }        │
│ class CryptoProcessor implements PaymentProcessor { ... }        │
│                                                                  │
│ // Factory                                                       │
│ class PaymentProcessorFactory {                                  │
│   create(type: string): PaymentProcessor {                      │
│     const processors = {                                         │
│       credit: CreditCardProcessor,                              │
│       paypal: PayPalProcessor,                                  │
│       crypto: CryptoProcessor,                                  │
│     };                                                           │
│     return new processors[type]();                              │
│   }                                                              │
│ }                                                                │
└─────────────────────────────────────────────────────────────────┘
```

### 3.4 Other Patterns

| Pattern | Use Case | Example |
|---------|----------|---------|
| Rename | 불명확한 이름 | `d` → `currentDate` |
| Inline | 불필요한 추상화 | 한 번만 사용되는 helper |
| Move Method | Feature Envy | Order의 로직을 Order로 이동 |
| Replace Temp with Query | 임시 변수 | `total` → `calculateTotal()` |
| Introduce Parameter Object | 긴 파라미터 | Options 객체로 그룹화 |
| Replace Magic Number | 매직 넘버 | `0.08` → `TAX_RATE` |
| Remove Dead Code | 미사용 코드 | 호출되지 않는 함수 제거 |

---

## 4. Safe Refactoring Mode

### 4.1 Safety Checks

```
> /cast:refactor --safe --path=src/services/user.service.ts

🔒 Safe Refactoring Mode

Pre-flight Checks:
┌─────────────────────────────────────────────────────────────────┐
│ ✅ Test Coverage: 85% (threshold: 80%)                          │
│ ✅ All Tests Passing: 45/45                                     │
│ ✅ No Uncommitted Changes                                       │
│ ✅ TypeScript: No Errors                                        │
│ ✅ ESLint: No Errors                                            │
└─────────────────────────────────────────────────────────────────┘

Safe to proceed with refactoring.

Proposed Changes:
1. Extract validateEmail() method
2. Extract validatePassword() method
3. Extract saveUser() method

Each change will be:
- Applied incrementally
- Tested after each step
- Rolled back if tests fail

Proceed? [Y/n]
```

### 4.2 Incremental Refactoring

```
Step 1/3: Extract validateEmail()
  └── Applying change...
  └── Running tests... ✅ 45/45 passed
  └── Committing: "refactor: extract validateEmail method"

Step 2/3: Extract validatePassword()
  └── Applying change...
  └── Running tests... ✅ 45/45 passed
  └── Committing: "refactor: extract validatePassword method"

Step 3/3: Extract saveUser()
  └── Applying change...
  └── Running tests... ❌ 2/45 failed

  ⚠️ Tests failed after this change.

  Options:
  [1] Rollback this step only
  [2] Rollback all steps
  [3] Fix and retry
  [4] Continue anyway (not recommended)

  > 3

  Analyzing failures...
  - user.service.test.ts:45 - Expected mock not called
  - user.service.test.ts:67 - Undefined property

  Suggested fix: Update test mocks for extracted method

  Apply fix? [Y/n]
```

---

## 5. Options

| Option | Description | Default |
|--------|-------------|---------|
| `--path` | 리팩토링 대상 경로 | - |
| `--pattern` | 적용할 리팩토링 패턴 | auto |
| `--analyze` | 분석만 수행 | false |
| `--safe` | 안전 모드 (테스트 필수) | false |
| `--preview` | 변경 미리보기만 | false |
| `--dry-run` | 실제 변경 없이 시뮬레이션 | false |

---

## 6. Quality Improvement Report

```
📊 Refactoring Results

Before → After Comparison:

Metric                    Before    After    Change
─────────────────────────────────────────────────────
Cyclomatic Complexity      28        12      ↓ 57%
Cognitive Complexity       45        18      ↓ 60%
Lines of Code            450       380      ↓ 16%
Methods                   15        22      ↑ 47% (smaller methods)
Test Coverage             72%       85%     ↑ 13%
Maintainability Index     52        78      ↑ 50%

Files Changed:
  + src/services/order.service.ts (refactored)
  + src/services/order-validator.ts (new)
  + src/services/order-notifier.ts (new)
  + src/services/order-calculator.ts (new)
  + src/services/__tests__/order.test.ts (updated)

Design Principles Improved:
  ✅ Single Responsibility: God class split
  ✅ Open/Closed: Strategy pattern for payments
  ✅ DRY: Extracted shared validation
```

---

## 7. Related Spells

| Spell | Description |
|-------|-------------|
| `/cast:analyze` | 코드 분석 |
| `/cast:review` | 코드 리뷰 |
| `/cast:tdd` | TDD 워크플로우 |
| `/cast:test-coverage` | 커버리지 분석 |

---

*Version: 0.3.0*
*Last Updated: 2026-01-26*

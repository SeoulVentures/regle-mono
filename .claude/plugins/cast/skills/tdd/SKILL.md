---
name: tdd
description: TDD workflow (RED-GREEN-REFACTOR)
disable-model-invocation: true
---


TDD 워크플로우를 실행하는 마법입니다. RED-GREEN-REFACTOR 사이클을 체계적으로 관리합니다.

---

## Usage

```
/cast:tdd "기능 설명"
/cast:tdd --feature="사용자 로그인"
/cast:tdd --from-issue=PROJ-123
/cast:tdd --cycle=red     # RED 단계만
/cast:tdd --cycle=green   # GREEN 단계만
/cast:tdd --cycle=refactor
```

---

## 1. Overview

TDD(Test-Driven Development)는 테스트를 먼저 작성하고, 그 테스트를 통과하는 코드를 구현하는 개발 방법론입니다.

```
┌─────────────────────────────────────────────────────────────────┐
│                    TDD WORKFLOW                                   │
│                                                                   │
│   /cast:tdd "기능 설명"                                           │
│        │                                                          │
│        ▼                                                          │
│   ┌─────────────────────────────────────────────────────────┐    │
│   │                   1. ANALYZE                             │    │
│   │   - 요구사항 분석                                        │    │
│   │   - 테스트 케이스 도출                                   │    │
│   │   - TDD Guide Familiar 활용                              │    │
│   └─────────────────────────────────────────────────────────┘    │
│        │                                                          │
│        ▼                                                          │
│   ┌─────────────────────────────────────────────────────────┐    │
│   │                   2. RED PHASE                           │    │
│   │   - 실패하는 테스트 작성                                  │    │
│   │   - 테스트 실행 및 실패 확인                              │    │
│   │   - 테스트가 정확히 실패하는지 확인                       │    │
│   └─────────────────────────────────────────────────────────┘    │
│        │                                                          │
│        ▼                                                          │
│   ┌─────────────────────────────────────────────────────────┐    │
│   │                  3. GREEN PHASE                          │    │
│   │   - 최소한의 구현                                        │    │
│   │   - 테스트 통과 확인                                     │    │
│   │   - Codex Familiar 활용                                  │    │
│   └─────────────────────────────────────────────────────────┘    │
│        │                                                          │
│        ▼                                                          │
│   ┌─────────────────────────────────────────────────────────┐    │
│   │                4. REFACTOR PHASE                         │    │
│   │   - 코드 품질 개선                                       │    │
│   │   - SOLID/DRY 적용                                       │    │
│   │   - 테스트 여전히 통과 확인                              │    │
│   └─────────────────────────────────────────────────────────┘    │
│        │                                                          │
│        ▼                                                          │
│   ┌─────────────────────────────────────────────────────────┐    │
│   │                 5. VERIFY & NEXT                         │    │
│   │   - 커버리지 확인                                        │    │
│   │   - 다음 테스트 케이스로                                 │    │
│   └─────────────────────────────────────────────────────────┘    │
│                                                                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. Workflow Details

### Phase 1: ANALYZE

```
요구사항
    │
    ▼
┌─────────────────────────────────┐
│ TDD Guide Familiar              │
│                                  │
│ 1. 요구사항 분석                 │
│    - 핵심 기능 식별              │
│    - 경계 조건 파악              │
│    - 에러 케이스 도출            │
│                                  │
│ 2. 테스트 케이스 설계            │
│    - Happy path                  │
│    - Edge cases                  │
│    - Error cases                 │
│    - Security cases              │
│                                  │
│ 3. 우선순위 결정                 │
│    - Critical → Optional        │
└─────────────────────────────────┘
```

**Output**: 테스트 케이스 목록

```markdown
## Test Cases for: 사용자 로그인

### Happy Path (High Priority)
1. ✅ should return JWT token for valid credentials
2. ✅ should set httpOnly cookie with refresh token

### Edge Cases (Medium Priority)
3. ⚪ should handle case-insensitive email
4. ⚪ should trim whitespace from inputs

### Error Cases (High Priority)
5. ⚪ should throw AuthError for invalid password
6. ⚪ should throw NotFoundError for unknown email
7. ⚪ should lock account after 5 failed attempts

### Security Cases (High Priority)
8. ⚪ should not reveal if email exists (timing attack)
9. ⚪ should rate limit login attempts
```

---

### Phase 2: RED

```
테스트 케이스
    │
    ▼
┌─────────────────────────────────┐
│ 1. 테스트 파일 생성/수정         │
│                                  │
│ 2. 테스트 코드 작성              │
│    - describe 블록              │
│    - it 블록                     │
│    - expect 어설션               │
│                                  │
│ 3. 테스트 실행                   │
│    $ npm test -- --watch         │
│                                  │
│ 4. 실패 확인 ✗                   │
│    - 올바른 이유로 실패하는지    │
│    - 에러 메시지 확인            │
└─────────────────────────────────┘
```

**Example**:

```typescript
// src/auth/login.test.ts
describe('LoginService', () => {
  describe('login', () => {
    it('should return JWT token for valid credentials', async () => {
      // Arrange
      const user = await createTestUser({
        email: 'test@example.com',
        password: 'password123'
      });

      // Act
      const result = await loginService.login('test@example.com', 'password123');

      // Assert
      expect(result.token).toBeDefined();
      expect(result.token).toMatch(/^eyJ/); // JWT format
    });
  });
});
```

**Run Test**:
```bash
$ npm test -- login.test.ts

 FAIL  src/auth/login.test.ts
  ● LoginService › login › should return JWT token for valid credentials

    ReferenceError: loginService is not defined
```

---

### Phase 3: GREEN

```
실패하는 테스트
    │
    ▼
┌─────────────────────────────────┐
│ Codex Familiar                   │
│                                  │
│ 1. 최소 구현                     │
│    - 테스트 통과만을 목표        │
│    - 완벽하지 않아도 됨          │
│    - 하드코딩도 일시적으로 OK    │
│                                  │
│ 2. 테스트 실행                   │
│    $ npm test -- --watch         │
│                                  │
│ 3. 통과 확인 ✓                   │
└─────────────────────────────────┘
```

**Example**:

```typescript
// src/auth/login.ts
export class LoginService {
  async login(email: string, password: string): Promise<LoginResult> {
    const user = await this.userRepository.findByEmail(email);

    if (!user) {
      throw new NotFoundError('User');
    }

    const isValid = await bcrypt.compare(password, user.passwordHash);

    if (!isValid) {
      throw new AuthError('Invalid credentials');
    }

    const token = jwt.sign({ userId: user.id }, process.env.JWT_SECRET);

    return { token };
  }
}
```

**Run Test**:
```bash
$ npm test -- login.test.ts

 PASS  src/auth/login.test.ts
  LoginService
    login
      ✓ should return JWT token for valid credentials (45 ms)
```

---

### Phase 4: REFACTOR

```
통과하는 테스트
    │
    ▼
┌─────────────────────────────────┐
│ 1. 코드 품질 분석                │
│    - Reviewer 원칙 검증          │
│    - SOLID 원칙 확인             │
│    - DRY 확인                    │
│                                  │
│ 2. 리팩토링                      │
│    - 중복 제거                   │
│    - 명확한 네이밍               │
│    - 추상화 도입                 │
│                                  │
│ 3. 테스트 재실행                 │
│    - 여전히 통과 확인 ✓          │
│                                  │
│ 4. 테스트 코드도 리팩토링        │
│    - 테스트 헬퍼 추출            │
│    - 픽스처 정리                 │
└─────────────────────────────────┘
```

**Example Refactoring**:

```typescript
// Before: 모든 로직이 한 메서드에
async login(email: string, password: string) {
  const user = await this.userRepository.findByEmail(email);
  if (!user) throw new NotFoundError('User');
  const isValid = await bcrypt.compare(password, user.passwordHash);
  if (!isValid) throw new AuthError('Invalid credentials');
  const token = jwt.sign({ userId: user.id }, process.env.JWT_SECRET);
  return { token };
}

// After: 책임 분리
async login(email: string, password: string): Promise<LoginResult> {
  const user = await this.findUserOrThrow(email);
  await this.verifyPassword(password, user.passwordHash);
  return this.generateAuthResult(user);
}

private async findUserOrThrow(email: string): Promise<User> {
  const user = await this.userRepository.findByEmail(email);
  if (!user) {
    throw new NotFoundError('User');
  }
  return user;
}

private async verifyPassword(plain: string, hash: string): Promise<void> {
  const isValid = await bcrypt.compare(plain, hash);
  if (!isValid) {
    throw new AuthError('Invalid credentials');
  }
}

private generateAuthResult(user: User): LoginResult {
  const token = this.jwtService.sign({ userId: user.id });
  return { token };
}
```

---

## 3. Options

| Option | Description | Default |
|--------|-------------|---------|
| `--cycle` | 특정 사이클만 실행 (red/green/refactor) | all |
| `--watch` | 파일 변경 감시 모드 | false |
| `--coverage` | 커버리지 리포트 생성 | true |
| `--threshold` | 커버리지 임계값 | 80 |
| `--from-issue` | 이슈에서 요구사항 추출 | - |
| `--interactive` | 대화형 모드 | false |

---

## 4. Interactive Mode

```
> /cast:tdd --interactive "사용자 인증"

🧪 TDD Mode Started

Step 1: Analyzing requirements...

Found 6 test cases:
1. [HIGH] should authenticate with valid credentials
2. [HIGH] should reject invalid password
3. [HIGH] should lock after 5 failures
4. [MEDIUM] should handle case-insensitive email
5. [LOW] should log authentication attempts
6. [LOW] should support remember me option

Start with test case 1? [Y/n]
> Y

📝 RED Phase - Writing test...

describe('AuthService', () => {
  it('should authenticate with valid credentials', async () => {
    // Test code here...
  });
});

Run test? [Y/n]
> Y

❌ Test failed (expected)
   ReferenceError: AuthService is not defined

🔨 GREEN Phase - Implement minimum code? [Y/n]
> Y

// Codex implementing...

✅ Test passed!

♻️ REFACTOR Phase - Any improvements needed? [Y/n/skip]
> Y

Refactoring suggestions:
1. Extract token generation to separate method
2. Add input validation

Apply? [1/2/all/skip]
> all

✅ Refactored, tests still passing

Continue to next test case? [Y/n]
```

---

## 5. Integration with CI/CD

### 5.1 Pre-commit Hook

```bash
#!/bin/bash
# .husky/pre-commit

# Run tests for changed files
npm test -- --changedSince=HEAD --coverage

# Check coverage thresholds
npm test -- --coverage --coverageThreshold='{"global":{"lines":80}}'
```

### 5.2 GitHub Actions

```yaml
name: TDD Workflow

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'

      - run: npm ci
      - run: npm test -- --coverage

      - name: Check Coverage
        run: |
          npm test -- --coverage --coverageThreshold='{"global":{"lines":80,"branches":70}}'
```

---

## 6. Related Spells

| Spell | Description |
|-------|-------------|
| `/cast:test-coverage` | 커버리지 상세 분석 |
| `/cast:e2e` | E2E 테스트 실행 |
| `/cast:dev` | 전체 개발 워크플로우 |
| `/cast:review` | 코드 리뷰 |

---

## 7. Best Practices

### 7.1 One Test at a Time
- 한 번에 하나의 테스트만 작성
- 작은 단계로 진행

### 7.2 Test Should Fail First
- RED 단계에서 테스트가 실패하지 않으면 문제
- 테스트가 실제로 무언가를 검증하는지 확인

### 7.3 Minimal Implementation
- GREEN 단계에서 과도한 구현 금지
- 테스트 통과에 필요한 최소한만

### 7.4 Refactor with Confidence
- 테스트가 있으므로 자신 있게 리팩토링
- 매 변경 후 테스트 실행

---

## 8. Example Session

```
> /cast:tdd "장바구니에 상품 추가"

📋 Analyzing requirement: "장바구니에 상품 추가"

Test Cases Identified:
1. [HIGH] should add item to empty cart
2. [HIGH] should increase quantity for existing item
3. [MEDIUM] should calculate total correctly
4. [MEDIUM] should limit quantity to available stock
5. [LOW] should persist cart to storage

Starting TDD Cycle...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔴 RED PHASE - Test 1: should add item to empty cart
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Writing test to: src/cart/cart.test.ts

```typescript
describe('Cart', () => {
  describe('addItem', () => {
    it('should add item to empty cart', () => {
      const cart = new Cart();
      const item = { id: '1', name: 'Product', price: 100 };

      cart.addItem(item);

      expect(cart.items).toHaveLength(1);
      expect(cart.items[0]).toEqual({ ...item, quantity: 1 });
    });
  });
});
```

Running tests...
❌ FAIL: Cart is not defined

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🟢 GREEN PHASE - Implementing minimum code
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Creating: src/cart/cart.ts

```typescript
export class Cart {
  items: CartItem[] = [];

  addItem(item: Item) {
    this.items.push({ ...item, quantity: 1 });
  }
}
```

Running tests...
✅ PASS

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
♻️ REFACTOR PHASE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

No refactoring needed for initial implementation.

Proceeding to Test 2...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 Progress: 1/5 tests complete
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

*Version: 0.3.0*
*Last Updated: 2026-01-26*

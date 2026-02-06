---
name: e2e
description: E2E testing workflow
disable-model-invocation: true
---


End-to-End 테스트를 실행하고 관리하는 마법입니다.

---

## Usage

```
/cast:e2e                         # 전체 E2E 테스트 실행
/cast:e2e --spec=auth             # 특정 스펙만
/cast:e2e --headed                # 브라우저 표시
/cast:e2e --record                # 테스트 녹화
/cast:e2e --generate="로그인 시나리오"  # 테스트 생성
```

---

## 1. Overview

E2E(End-to-End) 테스트는 실제 사용자 관점에서 애플리케이션의 전체 흐름을 검증합니다.

```
┌─────────────────────────────────────────────────────────────────┐
│                    E2E TEST WORKFLOW                             │
│                                                                  │
│   /cast:e2e                                                      │
│        │                                                         │
│        ▼                                                         │
│   ┌───────────────────────────────────────────────────────┐     │
│   │              1. ENVIRONMENT SETUP                      │     │
│   │   - 테스트 서버 시작                                   │     │
│   │   - 테스트 DB 초기화                                   │     │
│   │   - 브라우저 인스턴스 준비                             │     │
│   └───────────────────────────────────────────────────────┘     │
│        │                                                         │
│        ▼                                                         │
│   ┌───────────────────────────────────────────────────────┐     │
│   │               2. TEST EXECUTION                        │     │
│   │   - 시나리오별 테스트 실행                             │     │
│   │   - 스크린샷/비디오 캡처                               │     │
│   │   - 네트워크 요청 모니터링                             │     │
│   └───────────────────────────────────────────────────────┘     │
│        │                                                         │
│        ▼                                                         │
│   ┌───────────────────────────────────────────────────────┐     │
│   │               3. RESULT ANALYSIS                       │     │
│   │   - 성공/실패 분석                                     │     │
│   │   - 성능 메트릭                                        │     │
│   │   - 시각적 회귀 감지                                   │     │
│   └───────────────────────────────────────────────────────┘     │
│        │                                                         │
│        ▼                                                         │
│   ┌───────────────────────────────────────────────────────┐     │
│   │                  4. REPORTING                          │     │
│   │   - 테스트 리포트 생성                                 │     │
│   │   - 실패 디버깅 정보                                   │     │
│   │   - CI/CD 통합                                         │     │
│   └───────────────────────────────────────────────────────┘     │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. Supported Frameworks

| Framework | Features | Best For |
|-----------|----------|----------|
| **Playwright** | Multi-browser, Auto-wait | 모던 웹 앱 |
| **Cypress** | Real-time reload, Time travel | 빠른 개발 |
| **Puppeteer** | Chrome DevTools Protocol | Chrome 특화 |

### 2.1 Auto-detection

```bash
# 프로젝트 설정 자동 감지
/cast:e2e

Detected: Playwright (playwright.config.ts found)
Running: npx playwright test
```

---

## 3. Test Scenarios

### 3.1 Critical User Flows

```typescript
// e2e/auth.spec.ts
import { test, expect } from '@playwright/test';

test.describe('Authentication Flow', () => {
  test('complete signup and login flow', async ({ page }) => {
    // 1. Visit signup page
    await page.goto('/signup');
    await expect(page).toHaveTitle(/Sign Up/);

    // 2. Fill signup form
    await page.fill('[name="email"]', 'newuser@example.com');
    await page.fill('[name="password"]', 'SecurePass123!');
    await page.fill('[name="confirmPassword"]', 'SecurePass123!');

    // 3. Submit and verify redirect
    await page.click('button[type="submit"]');
    await expect(page).toHaveURL('/welcome');

    // 4. Logout
    await page.click('[data-testid="logout-button"]');
    await expect(page).toHaveURL('/login');

    // 5. Login with new account
    await page.fill('[name="email"]', 'newuser@example.com');
    await page.fill('[name="password"]', 'SecurePass123!');
    await page.click('button[type="submit"]');

    // 6. Verify logged in state
    await expect(page).toHaveURL('/dashboard');
    await expect(page.locator('[data-testid="user-menu"]')).toBeVisible();
  });
});
```

### 3.2 E-commerce Flow

```typescript
// e2e/checkout.spec.ts
test.describe('Checkout Flow', () => {
  test.beforeEach(async ({ page }) => {
    // Login as test user
    await page.goto('/login');
    await page.fill('[name="email"]', 'test@example.com');
    await page.fill('[name="password"]', 'password');
    await page.click('button[type="submit"]');
  });

  test('complete purchase flow', async ({ page }) => {
    // 1. Browse products
    await page.goto('/products');

    // 2. Add to cart
    await page.click('[data-testid="product-1"] button');
    await expect(page.locator('[data-testid="cart-count"]')).toHaveText('1');

    // 3. Go to cart
    await page.click('[data-testid="cart-icon"]');
    await expect(page).toHaveURL('/cart');

    // 4. Proceed to checkout
    await page.click('text=Checkout');
    await expect(page).toHaveURL('/checkout');

    // 5. Fill shipping info
    await page.fill('[name="address"]', '123 Test St');
    await page.fill('[name="city"]', 'Test City');
    await page.fill('[name="zip"]', '12345');

    // 6. Fill payment info
    await page.fill('[name="cardNumber"]', '4242424242424242');
    await page.fill('[name="expiry"]', '12/25');
    await page.fill('[name="cvc"]', '123');

    // 7. Complete purchase
    await page.click('text=Place Order');

    // 8. Verify confirmation
    await expect(page).toHaveURL(/\/order\/[a-z0-9-]+/);
    await expect(page.locator('h1')).toContainText('Order Confirmed');
  });
});
```

---

## 4. Test Generation

### 4.1 Generate from Description

```
> /cast:e2e --generate="사용자가 비밀번호를 잊어버리고 재설정하는 시나리오"

📝 Generating E2E test...

Generated: e2e/password-reset.spec.ts

```typescript
import { test, expect } from '@playwright/test';

test.describe('Password Reset Flow', () => {
  const testEmail = 'user@example.com';

  test('user can reset forgotten password', async ({ page }) => {
    // 1. Go to login and click forgot password
    await page.goto('/login');
    await page.click('text=Forgot password?');
    await expect(page).toHaveURL('/forgot-password');

    // 2. Request password reset
    await page.fill('[name="email"]', testEmail);
    await page.click('button[type="submit"]');

    // 3. Verify confirmation message
    await expect(page.locator('[data-testid="success-message"]'))
      .toContainText('Check your email');

    // 4. Simulate clicking reset link (from email)
    const resetToken = await getResetTokenFromTestEmail(testEmail);
    await page.goto(`/reset-password?token=${resetToken}`);

    // 5. Set new password
    await page.fill('[name="password"]', 'NewSecurePass123!');
    await page.fill('[name="confirmPassword"]', 'NewSecurePass123!');
    await page.click('button[type="submit"]');

    // 6. Verify redirect to login
    await expect(page).toHaveURL('/login');
    await expect(page.locator('[data-testid="success-message"]'))
      .toContainText('Password updated');

    // 7. Login with new password
    await page.fill('[name="email"]', testEmail);
    await page.fill('[name="password"]', 'NewSecurePass123!');
    await page.click('button[type="submit"]');

    // 8. Verify successful login
    await expect(page).toHaveURL('/dashboard');
  });
});
```

Test created! Run with: npx playwright test password-reset.spec.ts
```

### 4.2 Record and Generate

```
> /cast:e2e --record

🎬 Recording mode enabled

1. Open browser at: http://localhost:3000
2. Perform the actions you want to test
3. Press Ctrl+C when done

Recording...

[User performs actions in browser]

Recording complete!

Generated test from recording:

```typescript
test('recorded test', async ({ page }) => {
  await page.goto('http://localhost:3000/');
  await page.click('text=Products');
  await page.click('[data-testid="product-card-1"]');
  await page.click('button:has-text("Add to Cart")');
  await page.click('[data-testid="cart-icon"]');
  // ... more actions
});
```

Save as? [e2e/recorded-test.spec.ts]
```

---

## 5. Options

| Option | Description | Default |
|--------|-------------|---------|
| `--spec` | 특정 스펙 파일/패턴 | all |
| `--headed` | 브라우저 UI 표시 | false |
| `--record` | 테스트 녹화 모드 | false |
| `--generate` | 설명에서 테스트 생성 | - |
| `--workers` | 병렬 실행 워커 수 | auto |
| `--retries` | 실패 시 재시도 횟수 | 2 |
| `--trace` | 트레이스 수집 | on-failure |
| `--screenshot` | 스크린샷 캡처 | on-failure |
| `--video` | 비디오 녹화 | off |

---

## 6. Debugging

### 6.1 Interactive Debug Mode

```
> /cast:e2e --spec=auth --debug

🐛 Debug mode enabled

Running: npx playwright test auth.spec.ts --debug

Opening Playwright Inspector...

[Inspector UI opens with step-by-step execution]
```

### 6.2 Trace Viewer

```
> /cast:e2e --trace

Test completed with failures.

View trace:
  npx playwright show-trace trace/auth-spec-1.zip

Or open: http://localhost:3001/trace/auth-spec-1
```

### 6.3 Screenshot on Failure

```
Test: Authentication Flow > should login with valid credentials

❌ FAILED

Screenshot saved: e2e/screenshots/auth-login-failed.png

Error:
  Locator: getByTestId('submit-button')
  Expected: to be visible
  Received: element not found

Trace: e2e/traces/auth-login.zip
```

---

## 7. Best Practices

### 7.1 Test Data Management

```typescript
// e2e/fixtures/users.ts
export const testUsers = {
  standard: {
    email: 'standard@test.com',
    password: 'TestPass123!',
  },
  admin: {
    email: 'admin@test.com',
    password: 'AdminPass123!',
  },
};

// e2e/fixtures/database.ts
export async function seedTestData() {
  await db.user.createMany({ data: Object.values(testUsers) });
}

export async function cleanupTestData() {
  await db.user.deleteMany({
    where: { email: { contains: '@test.com' } }
  });
}
```

### 7.2 Page Object Pattern

```typescript
// e2e/pages/LoginPage.ts
export class LoginPage {
  constructor(private page: Page) {}

  async goto() {
    await this.page.goto('/login');
  }

  async login(email: string, password: string) {
    await this.page.fill('[name="email"]', email);
    await this.page.fill('[name="password"]', password);
    await this.page.click('button[type="submit"]');
  }

  async getErrorMessage() {
    return this.page.locator('[data-testid="error-message"]').textContent();
  }
}

// Usage in test
test('login with invalid credentials shows error', async ({ page }) => {
  const loginPage = new LoginPage(page);
  await loginPage.goto();
  await loginPage.login('wrong@email.com', 'wrongpassword');

  expect(await loginPage.getErrorMessage()).toContain('Invalid credentials');
});
```

### 7.3 API Mocking

```typescript
test('handles API error gracefully', async ({ page }) => {
  // Mock API to return error
  await page.route('/api/products', async (route) => {
    await route.fulfill({
      status: 500,
      body: JSON.stringify({ error: 'Internal Server Error' }),
    });
  });

  await page.goto('/products');

  // Verify error UI is shown
  await expect(page.locator('[data-testid="error-state"]')).toBeVisible();
  await expect(page.locator('text=Something went wrong')).toBeVisible();
});
```

---

## 8. CI/CD Integration

### 8.1 GitHub Actions

```yaml
# .github/workflows/e2e.yml
name: E2E Tests

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  e2e:
    timeout-minutes: 30
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: '20'

      - name: Install dependencies
        run: npm ci

      - name: Install Playwright browsers
        run: npx playwright install --with-deps

      - name: Start server
        run: npm run dev &
        env:
          DATABASE_URL: postgresql://test:test@localhost:5432/test

      - name: Wait for server
        run: npx wait-on http://localhost:3000

      - name: Run E2E tests
        run: npx playwright test

      - uses: actions/upload-artifact@v4
        if: failure()
        with:
          name: playwright-report
          path: playwright-report/
          retention-days: 7
```

### 8.2 Parallel Execution

```typescript
// playwright.config.ts
export default defineConfig({
  workers: process.env.CI ? 4 : undefined,
  fullyParallel: true,
  retries: process.env.CI ? 2 : 0,

  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
    { name: 'firefox', use: { ...devices['Desktop Firefox'] } },
    { name: 'webkit', use: { ...devices['Desktop Safari'] } },
  ],
});
```

---

## 9. Related Spells

| Spell | Description |
|-------|-------------|
| `/cast:tdd` | TDD 워크플로우 |
| `/cast:test-coverage` | 커버리지 분석 |
| `/cast:analyze` | 코드 분석 |
| `/cast:dev` | 개발 워크플로우 |

---

## 10. Example Session

```
> /cast:e2e

🎭 E2E Test Runner
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Detected: Playwright
Config: playwright.config.ts

Starting test server...
✅ Server ready at http://localhost:3000

Running tests...

  auth.spec.ts
    ✅ should signup new user (3.2s)
    ✅ should login with valid credentials (1.8s)
    ✅ should show error for invalid credentials (1.5s)
    ✅ should logout successfully (1.2s)

  checkout.spec.ts
    ✅ should add item to cart (2.1s)
    ✅ should complete checkout (4.5s)
    ❌ should handle payment failure (2.3s)

  profile.spec.ts
    ✅ should update user profile (2.8s)
    ✅ should change password (2.4s)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Results: 8 passed, 1 failed

Failed test:
  checkout.spec.ts > should handle payment failure

  Error: Timeout waiting for element [data-testid="error-toast"]

  Screenshot: e2e/screenshots/payment-failure-error.png
  Trace: e2e/traces/checkout-payment-failure.zip

Debug with: npx playwright show-trace e2e/traces/checkout-payment-failure.zip

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Retry failed test? [Y/n/debug]
> debug

Opening trace viewer...
```

---

*Version: 0.3.0*
*Last Updated: 2026-01-26*

---
name: test-coverage
description: Analyze and improve test coverage
disable-model-invocation: true
---


테스트 커버리지를 분석하고 개선 방안을 제시하는 마법입니다.

---

## Usage

```
/cast:test-coverage                    # 전체 커버리지 분석
/cast:test-coverage --path=src/auth    # 특정 경로만
/cast:test-coverage --threshold=80     # 임계값 지정
/cast:test-coverage --report=html      # HTML 리포트 생성
/cast:test-coverage --diff             # 변경된 파일만
```

---

## 1. Overview

테스트 커버리지는 코드의 어느 부분이 테스트되고 있는지를 측정합니다.

```
┌─────────────────────────────────────────────────────────────────┐
│                 TEST COVERAGE WORKFLOW                           │
│                                                                  │
│   /cast:test-coverage                                            │
│        │                                                         │
│        ▼                                                         │
│   ┌───────────────────────────────────────────────────────┐     │
│   │              1. COLLECT COVERAGE                       │     │
│   │   - 테스트 실행 with coverage                         │     │
│   │   - 메트릭 수집 (line, branch, function)              │     │
│   └───────────────────────────────────────────────────────┘     │
│        │                                                         │
│        ▼                                                         │
│   ┌───────────────────────────────────────────────────────┐     │
│   │              2. ANALYZE GAPS                           │     │
│   │   - 커버되지 않은 코드 식별                            │     │
│   │   - 임계값 미달 파일 표시                              │     │
│   │   - 복잡도 대비 커버리지 분석                          │     │
│   └───────────────────────────────────────────────────────┘     │
│        │                                                         │
│        ▼                                                         │
│   ┌───────────────────────────────────────────────────────┐     │
│   │            3. GENERATE RECOMMENDATIONS                 │     │
│   │   - 우선순위별 테스트 추가 제안                        │     │
│   │   - 테스트 케이스 자동 생성                            │     │
│   │   - 리스크 기반 분석                                   │     │
│   └───────────────────────────────────────────────────────┘     │
│        │                                                         │
│        ▼                                                         │
│   ┌───────────────────────────────────────────────────────┐     │
│   │              4. REPORT                                 │     │
│   │   - 요약 리포트                                        │     │
│   │   - 상세 파일별 분석                                   │     │
│   │   - 트렌드 (이전 대비)                                 │     │
│   └───────────────────────────────────────────────────────┘     │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 2. Coverage Metrics

### 2.1 Metric Types

| Metric | Description | Target |
|--------|-------------|--------|
| **Line** | 실행된 코드 라인 비율 | 80% |
| **Branch** | 조건문 분기 커버리지 | 70% |
| **Function** | 호출된 함수 비율 | 80% |
| **Statement** | 실행된 구문 비율 | 80% |

### 2.2 Thresholds

```json
{
  "coverageThreshold": {
    "global": {
      "lines": 80,
      "branches": 70,
      "functions": 80,
      "statements": 80
    },
    "src/critical/**": {
      "lines": 90,
      "branches": 85
    }
  }
}
```

---

## 3. Analysis Report

### 3.1 Summary Report

```
📊 Coverage Report
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Overall Coverage:
  Lines:      85.2% (2,341/2,748) ✅
  Branches:   72.1% (892/1,237)   ✅
  Functions:  88.4% (423/478)     ✅
  Statements: 84.9% (2,567/3,023) ✅

Status: ✅ All thresholds met

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Coverage by Directory:
  src/auth/       92.3% ████████████████████░░ ✅
  src/api/        87.1% █████████████████░░░░░ ✅
  src/services/   78.4% ███████████████░░░░░░░ ⚠️
  src/utils/      95.2% ███████████████████░░░ ✅
  src/components/ 71.2% ██████████████░░░░░░░░ ⚠️
```

### 3.2 Uncovered Files

```
⚠️ Files Below Threshold (80%):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

File                          Lines   Branches  Priority
───────────────────────────────────────────────────────
src/services/payment.ts       62.3%   45.2%     🔴 High
src/components/Checkout.tsx   68.1%   52.4%     🔴 High
src/utils/legacy.ts           45.0%   30.0%     🟡 Medium
src/api/webhooks.ts           71.2%   65.3%     🟡 Medium
```

### 3.3 Uncovered Lines Detail

```
📍 Uncovered Lines in src/services/payment.ts:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Line 45-52: Error handling for network timeout
  async processPayment(data: PaymentData) {
    try {
      return await this.gateway.process(data);
    } catch (error) {
→     if (error instanceof TimeoutError) {    // ❌ Not covered
→       await this.retryQueue.add(data);      // ❌ Not covered
→       throw new PaymentPendingError();      // ❌ Not covered
→     }
      throw error;
    }
  }

Line 78-85: Refund flow
  async refund(transactionId: string) {
→   const transaction = await this.findTransaction(transactionId);  // ❌
→   if (transaction.status !== 'completed') {                       // ❌
→     throw new InvalidRefundError();                               // ❌
→   }
    // ...
  }
```

---

## 4. Recommendations

### 4.1 Priority-based Suggestions

```
🎯 Recommended Actions (by priority):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🔴 HIGH PRIORITY (Impact: Critical paths)

1. src/services/payment.ts - Error handling
   Missing tests:
   - [ ] Network timeout retry logic
   - [ ] Refund flow validation
   - [ ] Concurrent payment handling

   Suggested test:
   ```typescript
   it('should retry on network timeout', async () => {
     mockGateway.process.mockRejectedValueOnce(new TimeoutError());

     await expect(service.processPayment(data))
       .rejects.toThrow(PaymentPendingError);

     expect(retryQueue.add).toHaveBeenCalledWith(data);
   });
   ```

🟡 MEDIUM PRIORITY (Impact: Common flows)

2. src/components/Checkout.tsx - Form validation
   Missing tests:
   - [ ] Invalid credit card format
   - [ ] Expired card handling
   - [ ] Form submission error state

🟢 LOW PRIORITY (Impact: Edge cases)

3. src/utils/legacy.ts - Deprecated functions
   Consider:
   - [ ] Mark as excluded from coverage
   - [ ] Or add minimal tests before removal
```

### 4.2 Auto-generated Test Suggestions

```typescript
// Generated test suggestions for src/services/payment.ts

describe('PaymentService', () => {
  describe('processPayment', () => {
    // ❌ Currently missing
    it('should add to retry queue on TimeoutError', async () => {
      // Arrange
      const mockError = new TimeoutError('Gateway timeout');
      gateway.process.mockRejectedValueOnce(mockError);

      // Act & Assert
      await expect(service.processPayment(paymentData))
        .rejects.toThrow(PaymentPendingError);

      expect(retryQueue.add).toHaveBeenCalledWith(paymentData);
    });

    // ❌ Currently missing
    it('should throw original error for non-timeout errors', async () => {
      // Arrange
      const mockError = new Error('Unknown error');
      gateway.process.mockRejectedValueOnce(mockError);

      // Act & Assert
      await expect(service.processPayment(paymentData))
        .rejects.toThrow('Unknown error');

      expect(retryQueue.add).not.toHaveBeenCalled();
    });
  });

  describe('refund', () => {
    // ❌ Currently missing
    it('should throw InvalidRefundError for non-completed transaction', async () => {
      // Arrange
      const transaction = createTransaction({ status: 'pending' });
      transactionRepo.findById.mockResolvedValue(transaction);

      // Act & Assert
      await expect(service.refund(transaction.id))
        .rejects.toThrow(InvalidRefundError);
    });
  });
});
```

---

## 5. Options

| Option | Description | Default |
|--------|-------------|---------|
| `--path` | 분석할 경로 | `src/` |
| `--threshold` | 커버리지 임계값 | 80 |
| `--report` | 리포트 형식 (text/html/json) | text |
| `--diff` | 변경된 파일만 분석 | false |
| `--suggest` | 테스트 제안 생성 | true |
| `--compare` | 이전 커버리지와 비교 | false |

---

## 6. Coverage Trend

```
📈 Coverage Trend (Last 5 runs):
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Date         Lines    Branches   Trend
─────────────────────────────────────────────────────
2024-01-26   85.2%    72.1%      ↑ +2.1%
2024-01-25   83.1%    70.8%      ↑ +1.5%
2024-01-24   81.6%    69.2%      ↓ -0.3%
2024-01-23   81.9%    68.5%      ↑ +3.2%
2024-01-22   78.7%    66.4%      —

Overall trend: ↑ Improving (+6.5% in 5 days)
```

---

## 7. Integration

### 7.1 CI/CD Integration

```yaml
# .github/workflows/coverage.yml
name: Coverage Check

on: [push, pull_request]

jobs:
  coverage:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install dependencies
        run: npm ci

      - name: Run tests with coverage
        run: npm test -- --coverage --coverageReporters=json-summary

      - name: Check thresholds
        run: |
          LINES=$(jq '.total.lines.pct' coverage/coverage-summary.json)
          if (( $(echo "$LINES < 80" | bc -l) )); then
            echo "Coverage below threshold: $LINES%"
            exit 1
          fi

      - name: Upload coverage report
        uses: codecov/codecov-action@v3
```

### 7.2 Pre-commit Hook

```bash
#!/bin/bash
# .husky/pre-commit

npm test -- --coverage --changedSince=HEAD

# Check if any file dropped below threshold
if grep -q "below threshold" coverage/coverage-summary.txt; then
  echo "❌ Coverage dropped below threshold"
  exit 1
fi
```

---

## 8. Related Spells

| Spell | Description |
|-------|-------------|
| `/cast:tdd` | TDD 워크플로우 |
| `/cast:e2e` | E2E 테스트 |
| `/cast:analyze` | 코드 분석 |
| `/cast:review` | 코드 리뷰 |

---

## 9. Example Session

```
> /cast:test-coverage --path=src/services

🔍 Collecting coverage data...

Running: npm test -- --coverage --collectCoverageFrom='src/services/**/*.ts'

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 Coverage Report: src/services/
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Overall:
  Lines:      78.4% ⚠️ (below 80% threshold)
  Branches:   65.2% ⚠️ (below 70% threshold)
  Functions:  82.1% ✅
  Statements: 77.9% ⚠️

Files:
  ✅ auth.service.ts       92.1% / 88.3% / 95.0%
  ✅ user.service.ts       89.4% / 82.1% / 91.2%
  ⚠️ payment.service.ts    62.3% / 45.2% / 70.0%  🔴
  ⚠️ order.service.ts      71.2% / 58.4% / 78.3%  🟡
  ✅ notification.ts       85.6% / 79.0% / 88.9%

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🎯 Recommendations
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. [HIGH] payment.service.ts
   Missing coverage: Error handling, refund flow
   Estimated tests needed: 5

2. [MEDIUM] order.service.ts
   Missing coverage: Cancellation logic
   Estimated tests needed: 3

Generate test suggestions? [Y/n]
> Y

📝 Generating test suggestions...

[Test suggestions output as shown above]

Apply suggestions? [Y/n]
```

---

*Version: 0.3.0*
*Last Updated: 2026-01-26*

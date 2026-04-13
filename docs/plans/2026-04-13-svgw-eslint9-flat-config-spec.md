---
title: SVGW ESLint 9 + Flat Config 마이그레이션 스펙
date: 2026-04-13
repo: SeoulVentures/SeoulVenturesGroupware
issue: "#574"
branch: chore/eslint9-flat-config
status: draft
handoff: docs/plans/2026-04-13-svgw-eslint9-flat-config-handoff.md
---

# ESLint 9 + Flat Config 마이그레이션 스펙

## 1. 목표

- `frontend/` 의 ESLint 8.57.1 + legacy `.eslintrc.cjs` 를 ESLint 9.x + flat config (`eslint.config.js`) 로 이관한다.
- 관련 플러그인·파서를 ESLint 9 호환 버전으로 일괄 업데이트한다.
- `bun run lint`, `bun run typecheck`, `bun run build`, `deploy.yml` CI 가 모두 그린 상태를 유지한다.
- 이후 dependabot 그룹 PR (eslint, typescript-eslint, vue) 이 정상 통과되도록 차단을 해제한다.

## 2. 현재 상태 요약 (확인 완료)

- `frontend/package.json` scripts:
  - `"lint": "eslint . -c .eslintrc.cjs --fix --ext .ts,.js,.cjs,.vue,.tsx,.jsx"`
  - `"typecheck": "vue-tsc --noEmit"`, `"build": "vite build"`
  - `lint-staged`: `*.{ts,js,cjs,vue,tsx,jsx}` → `eslint --fix`
- `.eslintrc.cjs` 246줄, 13개 ESLint 관련 패키지, `env/extends/parser/parserOptions/plugins/ignorePatterns/rules/settings` 구조.
- `.github/workflows/` 에 ESLint 관련 단계는 grep 결과 **없음** — CI lint 는 `deploy.yml` 내 `bun run lint` 호출로 실행되므로 스크립트만 수정해도 CI 가 따라옴. (deploy.yml 재검증 필요 항목으로 체크리스트에 유지)

## 3. 타겟 패키지 버전

| 패키지 | 현재 | 목표 | 비고 |
| --- | --- | --- | --- |
| `eslint` | 8.57.1 | `^9.14.0` | flat config 기본 |
| `@typescript-eslint/eslint-plugin` | 7.18.0 | `^8.x` | v8 = ESLint 9 전제 |
| `@typescript-eslint/parser` | 7.18.0 | `^8.x` | 위와 세트 |
| `eslint-plugin-vue` | 9.33.0 | `^10.x` | vue3 flat 지원 |
| `vue-eslint-parser` | (eslint-plugin-vue peer) | `^10.x` | parserOptions.parser 방식 유지 |
| `eslint-plugin-sonarjs` | 0.24.0 | `^3.x` 선호 (4.x 는 major 변경 큼) | ⚠ rule id 변경 가능 |
| `eslint-plugin-import` | 2.32.0 | 유지 (flat 지원됨, 2.30+ 에서 `flatConfig` 노출) | |
| `eslint-plugin-promise` | 6.6.0 | `^7.x` | flat 지원 |
| `eslint-plugin-regexp` | 2.10.0 | 유지 | flat 지원 확인됨 |
| `eslint-plugin-regex` | 1.10.0 | **제거 후보** | 1건만 사용 (regex/invalid) → `eslint-plugin-regexp` 또는 `no-restricted-syntax` 로 대체 검토. 우선 유지하고 flat 호환 확인 |
| `eslint-plugin-unicorn` | 51.0.1 | `^56.x` | ESLint 9 지원 |
| `eslint-plugin-case-police` | 0.6.1 | 조사 필요 | ⚠ flat 미지원이면 제거 결정 |
| `@antfu/eslint-config-vue` | 0.43.1 | **제거** | legacy 전용. antfu/eslint-config 3.x 로 이관 or 제거 |
| `eslint-config-airbnb-base` | 15.0.0 | **제거** | flat 미지원. 필요한 룰은 직접 이관 |
| `eslint-import-resolver-typescript` | 3.10.1 | 유지 | flat 에서 `settings` 로 연결 |

## 4. 선택된 전략

1. **antfu/airbnb 제거**: 기존 `.eslintrc.cjs` 의 커스텀 rule set 이 매우 구체적이라 preset 을 한두 개 교체하는 것보다 **최소 preset + 커스텀 룰 직계승** 이 안전.
   - 유지 preset: `@eslint/js recommended`, `eslint-plugin-vue` flat preset (`vue3-recommended`), `@typescript-eslint` recommended, `eslint-plugin-import` flat recommended, `eslint-plugin-promise` flat recommended, `eslint-plugin-sonarjs` recommended, `eslint-plugin-regexp` recommended, `eslint-plugin-unicorn` (필요 룰만)
   - 제거: `@antfu/eslint-config-vue`, `eslint-config-airbnb-base`
2. **case-police**: 0.6.1 은 legacy only. flat 지원 버전 확인 후, 없으면 플러그인+룰 모두 제거 (복원은 별도 이슈).
3. **regex 플러그인**: flat 미지원이면 4개 규칙을 `no-restricted-syntax` + 커스텀 정규식 체크 스크립트로 대체. 우선 flat 호환 버전 찾아 유지.
4. **parser 설정**: flat 에서는 `languageOptions.parser = vueEslintParser`, `languageOptions.parserOptions.parser = tseslintParser` 형식. `.vue` 파일 override block 으로 분리.
5. **ignorePatterns**: flat 은 `ignores` 최상위 키. 기존 4개 항목 그대로 이관 + `eslint.config.js` 자체는 자동 무시.
6. **스크립트 변경**: `"lint": "eslint . --fix"` (flat 은 `-c` / `--ext` 불필요).

## 5. 엣지 케이스·대응

| 번호 | 케이스 | 대응 |
| --- | --- | --- |
| E1 | antfu preset 제거 시 `antfu/top-level-function` 룰 존재하지 않음 | 룰 자체 삭제 (현재 `off` 이므로 영향 없음) |
| E2 | airbnb-base 제거 시 누락되는 룰 발생 가능 (예: `no-unused-expressions`, `prefer-const`) | `@eslint/js recommended` 가 대부분 커버. 체크리스트에서 `bun run lint` 결과의 "신규 경고" 그룹을 육안 검토 후 필요하면 직접 추가 |
| E3 | `plugin:vue/vue3-recommended` (legacy) → flat 에서는 `pluginVue.configs['flat/recommended']` | 공식 문서 기준으로 이관 |
| E4 | sonarjs major bump 시 rule id 변경 | 기존 off 규칙 2개 (`cognitive-complexity`, `no-duplicate-string`, `no-nested-template-literals`) 을 새 rule id 로 매핑 or 주석 처리. `bun run lint` 경고 검토 |
| E5 | `eslint-plugin-case-police` 제거 시 대소문자 규칙 완화 | 규칙 본문이 영문 고유명사 기반 → 한국어 UI 코드베이스에서는 실질 영향 작음. 복원은 별도 이슈 |
| E6 | `deploy.yml` 에 ESLint 관련 step 부재 확인 → 실제 lint 는 어디서? | deploy.yml 상세 읽고 `bun run lint` 호출 위치 재확인 필수 |
| E7 | dependabot 이 이미 close 한 PR #558/#560/#563/#601/#602 재활성화 | 본 PR 머지 후 `gh pr reopen` 또는 다음 weekly 사이클 대기. 재트리거는 별도 단계 |
| E8 | `lint-staged` 훅 | flat 은 `eslint --fix <file>` 자동 감지 OK. 변경 불필요 |

## 6. 작업 순서

1. 패키지 bump: `eslint`, `@typescript-eslint/*`, `eslint-plugin-vue`, `vue-eslint-parser`, `eslint-plugin-sonarjs`, `eslint-plugin-promise`, `eslint-plugin-unicorn`, `eslint-plugin-import`
2. `@antfu/eslint-config-vue`, `eslint-config-airbnb-base` 제거
3. `eslint-plugin-case-police`, `eslint-plugin-regex` flat 호환성 조사 후 유지/제거 결정
4. `frontend/eslint.config.js` 작성 — 기존 246줄 룰을 최대한 동일 의미로 이관
5. `.eslintrc.cjs` 삭제
6. `package.json` lint 스크립트를 `"eslint . --fix"` 로 수정
7. `bun install && bun run lint` 로컬 검증 (실패 rule 개별 대응)
8. `bun run typecheck`, `bun run build` 확인
9. `.github/workflows/deploy.yml` lint 관련 부분 재검증
10. Draft PR 생성 (`Closes #574`)
11. CI 그린 확인 후 리뷰 요청

## 7. 검증 체크리스트

- [ ] `frontend/.eslintrc.cjs` 삭제됨
- [ ] `frontend/eslint.config.js` 생성됨
- [ ] `frontend/package.json` lint script 에서 `-c .eslintrc.cjs --ext ...` 제거됨
- [ ] `bun run lint` 로컬 통과 (신규 경고 0 또는 승인된 경고 목록 문서화)
- [ ] `bun run typecheck` 통과
- [ ] `bun run build` 통과
- [ ] `.github/workflows/deploy.yml` 내 lint 관련 명령 모두 신 스크립트 호환
- [ ] CI 의 "테스트" job 그린
- [ ] PR 본문에 제거된 preset (antfu/airbnb) 영향 요약 명시
- [ ] 머지 후 dependabot 그룹 PR (#558/#560/#563/#601/#602 재생성) 상태 추적

## 8. 위험 및 롤백

- 위험도: **중간** — 프로덕션 코드는 건드리지 않지만 lint 룰 차이로 향후 커밋 DX 영향.
- 롤백: 브랜치 단독 PR 이므로 `git revert` 한 번으로 원복. 의존성 lockfile 도 함께 revert.

## 9. 관련 문서·메모리

- 핸드오프: `docs/plans/2026-04-13-svgw-eslint9-flat-config-handoff.md`
- 메모리: `svgw-dependabot-2026-04-13.md`
- 이슈: #574 (본 작업), close 대상 재생성 #558/#560/#563/#601/#602

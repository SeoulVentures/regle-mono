---
title: SVGW ESLint 9 + Flat Config 마이그레이션 핸드오프
date: 2026-04-13
repo: SeoulVentures/SeoulVenturesGroupware
issue: "#574"
blocked_by: []
blocks:
  - "#558 (eslint-plugin-vue 10.x) — 이미 close, 재생성 대상"
  - "#560 (@typescript-eslint/parser 8.x) — 이미 close"
  - "#563 (eslint-plugin-sonarjs 4.x) — 이미 close"
  - "#601 @typescript-eslint 그룹 PR — 이미 close"
  - "#602 eslint 그룹 PR — 이미 close"
---

# ESLint 9 + Flat Config 마이그레이션 (차단 해제 작업)

## 배경

2026-04-13 dependabot 그룹 설정(#598) 머지 후 자동 생성된 그룹 PR 중 2건이 ESLint 9/10 호환성 이슈로 close 처리됨.

- **#602 eslint 그룹** (7 패키지) 테스트 실패 로그:
  ```
  ESLint: 10.2.0
  A config object is using the "env" key, which is not supported in flat config system.
  ```
- **#601 typescript-eslint 그룹**: parser 가 ignore 되어 peer 충돌 (parser 는 ESLint 9 전제)

이 이슈(#574)를 해결하지 않는 한 dependabot 이 관련 PR 을 계속 close 당하는 상황이 반복됨.

## 현재 상태

- ESLint 본체: `8.57.1`
- 설정 파일: `frontend/.eslintrc.cjs` (246줄, legacy)
- 실행 스크립트: `eslint . -c .eslintrc.cjs --fix --ext .ts,.js,.cjs,.vue,.tsx,.jsx`
- 관련 패키지 (frontend/package.json devDependencies):
  - `@antfu/eslint-config-vue: 0.43.1`
  - `eslint-config-airbnb-base: 15.0.0`
  - `eslint-import-resolver-typescript: 3.10.1`
  - `eslint-plugin-case-police: 0.6.1`
  - `eslint-plugin-import: 2.32.0`
  - `eslint-plugin-promise: 6.6.0`
  - `eslint-plugin-regex: 1.10.0`
  - `eslint-plugin-regexp: 2.10.0`
  - `eslint-plugin-sonarjs: 0.24.0`
  - `eslint-plugin-unicorn: 51.0.1`
  - `eslint-plugin-vue: 9.33.0`
  - `@typescript-eslint/eslint-plugin: 7.18.0`
  - `@typescript-eslint/parser: 7.18.0`

## 엣지 케이스·리스크

1. **`@antfu/eslint-config-vue 0.43.1`** 이 legacy format. flat config 지원 여부 확인 필요
   - 대안: `@antfu/eslint-config` 3.x (flat 지원) 로 전환, Vue 플러그인은 `eslint-plugin-vue 10.x` 로 분리
2. **`eslint-config-airbnb-base`** 는 flat config 공식 지원 안 됨 → `eslint-config-airbnb-extended` 또는 직접 rule 이관 필요
3. **`eslint-plugin-case-police 0.6.1`** flat config 호환성 별도 조사
4. **`eslint-plugin-regex 1.10.0`** (regex ≠ regexp) — 두 플러그인 병존, 하나는 deprecated 가능성
5. **Vue 3 + vue-eslint-parser** flat config 에서 `parserOptions.parser` 지정 방식 변경됨
6. **CI 영향**: `deploy.yml` 의 lint step 에 `-c .eslintrc.cjs --fix --ext ...` 플래그 남아있으면 실패 → script/workflow 모두 수정
7. **이미 close 된 dependabot PR 5건** (#558/#560/#563/#601/#602) 의 재활성화 시점 관리

## 권장 실행 커맨드 (새 세션)

```bash
# 0. 프로젝트 진입
cd /opt/SeoulVentures/regle/SeoulVenturesGroupware

# 1. 최신 master 확인 및 브랜치 생성
git checkout master && git pull
git checkout -b chore/eslint9-flat-config

# 2. 핸드오프 문서 읽기 (이 파일)
cat /opt/SeoulVentures/regle/docs/plans/2026-04-13-svgw-eslint9-flat-config-handoff.md

# 3. 현재 eslintrc 와 lint 스크립트 전수 파악
cat frontend/.eslintrc.cjs
grep -n "eslint" frontend/package.json
grep -rn "eslintrc\|eslint \." .github/workflows/

# 4. 관련 공식 마이그레이션 가이드 확인 (context7 MCP 또는 웹)
# - https://eslint.org/docs/latest/use/configure/migration-guide
# - https://eslint.vuejs.org/user-guide/#usage (vue 10.x + flat)
# - https://typescript-eslint.io/getting-started (v8 flat)
# - https://github.com/antfu/eslint-config (antfu 3.x flat)

# 5. 스펙 문서 작성 (선택된 전략 기록)
# docs/plans/2026-04-13-svgw-eslint9-flat-config-spec.md

# 6. 작업 단계 권장 순서
#    a. eslint 본체 8 → 9 로 먼저 올림 (flat config 도입 전, legacy 모드 가능)
#    b. @typescript-eslint 7 → 8 동시 bump (plugin + parser 세트)
#    c. @antfu/eslint-config 전략 결정 (유지 / 3.x 이관 / 제거)
#    d. eslint-plugin-vue 9.x → 10.x
#    e. eslint-plugin-sonarjs 0.24 → 4.x
#    f. .eslintrc.cjs → eslint.config.js 변환
#    g. package.json lint 스크립트에서 `-c .eslintrc.cjs` 제거
#    h. bun install && bun run lint 로컬 검증
#    i. CI 통과 확인

# 7. 검증
cd frontend
bun install
bun run lint
bun run typecheck
bun run build

# 8. Draft PR 생성 (이슈 #574 와 연결)
gh pr create --draft --title "chore(eslint): ESLint 9 + Flat Config 마이그레이션" --body "Closes #574"

# 9. 머지 후 dependabot 재트리거 — 다음 weekly 사이클 또는:
gh workflow list  # dependabot workflow 재실행 가능 여부 확인
```

## 관련 메모리

- `/opt/SeoulVentures/.claude/projects/-opt-SeoulVentures-regle/memory/svgw-dependabot-2026-04-13.md`
- MEMORY.md 인덱스 항목: "SVGW Dependabot 일괄 리뷰"

## 참고 이슈·PR

- 이슈: #574 (본 작업), #571 Tiptap, #573 ApexCharts, #576 claude-review
- 머지됨: #598 (group 설정), #600 (FullCalendar)
- Close 됨 (재생성 대상): #558, #560, #563, #601, #602

## 검증 체크리스트

- [ ] `bun run lint` 경고/에러 없이 통과
- [ ] `bun run typecheck` 통과
- [ ] `bun run build` 통과
- [ ] `frontend/.eslintrc.cjs` 삭제, `frontend/eslint.config.js` (또는 `.mjs`) 생성
- [ ] `frontend/package.json` lint 스크립트에서 `-c .eslintrc.cjs --ext` 제거
- [ ] `.github/workflows/deploy.yml` lint step 점검
- [ ] CI (`테스트` job) 통과
- [ ] PR 머지 후 다음 dependabot 사이클에서 eslint/typescript-eslint/vue 그룹 PR 이 정상 생성되고 테스트 통과

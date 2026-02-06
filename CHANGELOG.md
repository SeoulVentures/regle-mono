# Changelog

Regle Monorepo의 모든 주요 변경사항이 이 파일에 기록됩니다.

이 프로젝트는 [Semantic Versioning](https://semver.org/spec/v2.0.0.html)을 따르며,
변경 이력 형식은 [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)를 기반으로 합니다.

## [Unreleased]

## [0.1.0] - 2026-02-06

### Added
- **모노리포 구조 초기화**: Git Submodule 기반 모노리포 생성
  - 8개 프로젝트 서브모듈 추가
  - Claude Code 통합 설정 (`.claude/`)
  - Serena 에이전트 설정 (`.serena/`)
  - 종합 README.md 작성
  - 프로젝트별 설정 파일 (CLAUDE.md, AGENTS.md, grimoire.yaml)

#### 서브모듈 목록
| 프로젝트 | 설명 | 브랜치 |
|---------|------|--------|
| SeoulVenturesGroupware | 서울벤처스 그룹웨어 시스템 | master |
| regle-co-kr | Regle 메인 웹사이트 | master |
| regle-mcp-server | Regle MCP 서버 | main |
| regle-universe | Regle Universe 통합 플랫폼 | master |
| review-moai-refactoring | Review Moai 리팩토링 | master |
| specto-admin | Specto 어드민 패널 | master |
| sv-nova-master | SV Nova 마스터 | master |
| tm-regle.kr | TikTok Manager Regle | master |

### Changed
- **regle-universe 서브모듈 업데이트** (2026-02-06)
  - README.md 전면 개편
  - CHANGELOG.md 신규 추가
  - 문서화 품질 대폭 향상
  - 관련 PR: [#743](https://github.com/SeoulVentures/regle-universe/pull/743)

### Infrastructure
- **GitHub 리포지토리 생성**: https://github.com/SeoulVentures/regle-mono
- **모노리포 빌드 설정**: 서브모듈 기반 구조
- **Claude Code 통합**: AI 어시스턴트 설정 완료

---

## 버전 관리 규칙

### 버전 포맷
- **Major.Minor.Patch** (예: 1.0.0)
  - **Major**: 서브모듈 구조 변경 또는 호환되지 않는 변경
  - **Minor**: 새로운 서브모듈 추가 또는 주요 기능 추가
  - **Patch**: 서브모듈 업데이트, 설정 수정, 문서 개선

### 변경 유형
- **Added**: 새로운 서브모듈, 기능, 또는 설정 추가
- **Changed**: 기존 서브모듈 업데이트 또는 설정 변경
- **Deprecated**: 곧 제거될 서브모듈 또는 기능
- **Removed**: 제거된 서브모듈 또는 기능
- **Fixed**: 서브모듈 참조 수정 또는 버그 수정
- **Security**: 보안 관련 수정

### 서브모듈 업데이트 기록 방식

서브모듈의 주요 업데이트는 다음 형식으로 기록됩니다:

```markdown
### Changed
- **[서브모듈명] 업데이트** (날짜)
  - 주요 변경사항 1
  - 주요 변경사항 2
  - 관련 PR: [#번호](PR 링크)
  - 커밋: `해시` → `해시`
```

---

## 참고 링크

- **GitHub 리포지토리**: https://github.com/SeoulVentures/regle-mono
- **서브모듈 리포지토리들**: https://github.com/SeoulVentures
- **이슈 트래커**: https://github.com/SeoulVentures/regle-mono/issues
- **Pull Requests**: https://github.com/SeoulVentures/regle-mono/pulls

---

**참고**: 각 서브모듈의 상세한 변경 이력은 해당 리포지토리의 CHANGELOG를 참조하세요.

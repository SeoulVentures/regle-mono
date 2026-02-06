# Regle Monorepo

서울벤처스의 Regle 프로젝트 통합 모노리포지토리입니다. Git Submodule을 사용하여 여러 프로젝트를 하나의 리포지토리에서 관리합니다.

## 📁 프로젝트 구조

```
regle-mono/
├── SeoulVenturesGroupware/    # 서울벤처스 그룹웨어
├── regle-co-kr/                # Regle 메인 웹사이트
├── regle-mcp-server/           # Regle MCP 서버
├── regle-universe/             # Regle Universe 프로젝트
├── review-moai-refactoring/    # Review Moai 리팩토링
├── specto-admin/               # Specto 어드민 패널
├── sv-nova-master/             # SV Nova 마스터
├── tm-regle.kr/                # TikTok Manager Regle
├── .claude/                    # Claude Code 설정
├── CLAUDE.md                   # 프로젝트별 Claude 지침
├── grimoire.yaml               # Grimoire 설정
└── README.md                   # 이 파일
```

## 🚀 시작하기

### 초기 클론

```bash
# 모노리포 클론 (submodule 포함)
git clone --recurse-submodules https://github.com/SeoulVentures/regle-mono.git

# 또는 이미 클론한 경우
git clone https://github.com/SeoulVentures/regle-mono.git
cd regle-mono
git submodule update --init --recursive
```

### Submodule 업데이트

```bash
# 모든 submodule 최신 상태로 업데이트
git submodule update --remote --merge

# 또는 개별 업데이트
cd SeoulVenturesGroupware
git pull origin master
cd ..
```

### 새로운 변경사항 푸시

```bash
# 특정 submodule에서 작업 후
cd SeoulVenturesGroupware
git add .
git commit -m "feat: add new feature"
git push origin master

# 메인 리포지토리에서 submodule 참조 업데이트
cd ..
git add SeoulVenturesGroupware
git commit -m "chore: update SeoulVenturesGroupware submodule"
git push origin master
```

## 📋 Submodule 목록

| 프로젝트 | 설명 | 브랜치 |
|---------|------|--------|
| **SeoulVenturesGroupware** | 서울벤처스 그룹웨어 시스템 | master |
| **regle-co-kr** | Regle 메인 웹사이트 | master |
| **regle-mcp-server** | Regle MCP(Model Context Protocol) 서버 | main |
| **regle-universe** | Regle Universe 통합 프로젝트 | master |
| **review-moai-refactoring** | Review Moai 리팩토링 프로젝트 | master |
| **specto-admin** | Specto 어드민 패널 | master |
| **sv-nova-master** | SV Nova 마스터 프로젝트 | master |
| **tm-regle.kr** | TikTok Manager Regle | master |

## 🤖 Claude Code 설정

이 모노리포는 Claude Code와 함께 사용할 수 있도록 구성되어 있습니다.

- **`.claude/`**: Claude Code 프로젝트 설정 및 메모리
- **`CLAUDE.md`**: 프로젝트별 개발 가이드라인 및 Claude 지침
- **`grimoire.yaml`**: Grimoire 에이전트 설정

### Claude Code 사용

```bash
# Claude Code CLI로 프로젝트 작업
claude-code

# 또는 특정 작업 실행
claude-code "모든 리포지토리를 최신 상태로 업데이트하라"
```

## 🔧 유용한 명령어

### 모든 Submodule 상태 확인

```bash
git submodule foreach 'git status'
```

### 모든 Submodule 풀

```bash
git submodule foreach 'git pull origin $(git rev-parse --abbrev-ref HEAD)'
```

### Submodule 추가

```bash
git submodule add <repository-url> <path>
```

### Submodule 제거

```bash
git submodule deinit -f <path>
git rm -f <path>
rm -rf .git/modules/<path>
```

## 📝 개발 워크플로우

1. **Submodule에서 작업**
   ```bash
   cd <submodule-directory>
   git checkout -b feature/my-feature
   # 작업 수행
   git commit -am "feat: implement feature"
   git push origin feature/my-feature
   ```

2. **메인 브랜치에 머지 후 모노리포 업데이트**
   ```bash
   cd <submodule-directory>
   git checkout master
   git pull origin master
   cd ..
   git add <submodule-directory>
   git commit -m "chore: update <submodule> to latest"
   git push origin master
   ```

## 🔐 권한 관리

각 submodule은 독립적인 리포지토리이므로:
- 각 리포지토리에 대한 접근 권한이 필요합니다
- GitHub 인증 정보가 올바르게 설정되어 있어야 합니다

## 📚 참고 자료

- [Git Submodules 공식 문서](https://git-scm.com/book/en/v2/Git-Tools-Submodules)
- [Claude Code 문서](https://claude.ai/code)
- [Seoul Ventures GitHub](https://github.com/SeoulVentures)

## 📞 문의

- **Organization**: Seoul Ventures
- **GitHub**: https://github.com/SeoulVentures

---

*Last updated: 2026-02-06*

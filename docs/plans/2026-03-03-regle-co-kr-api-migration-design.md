# [Regle] Phase 3: regle-co-kr 프론트엔드 API 전환 설계 문서

## 관련 이슈
- https://github.com/SeoulVentures/SeoulVenturesGroupware/issues/452
- 의존성: Phase 1 (#450, 완료) — Groupware에 `/api/regle/inquiry` 엔드포인트 이미 구현됨

## 목표
`regle-co-kr` 프론트엔드의 문의 폼 API 호출 대상을 기존 Vapor 백엔드에서 SeoulVenturesGroupware로 전환

## 범위

Laravel + Vite 구조 유지 (Phase 4 정적 전환 전 과도기 단계)

### 변경 파일

#### 1. `resources/views/components/ContactForm.vue`

| 항목 | 현재 | 변경 후 |
|------|------|---------|
| 엔드포인트 | `/send-contact-request` | `${API_BASE}/api/regle/inquiry` |
| 요청 바디 | `form` (HTMLFormElement) | `body` (plain object, 이미 선언됨) |
| 성공 판단 | `response.value.status === 200` | `response.value?.success === true` |
| 에러 필드 | `response?.errors?.*` | 동일 구조 유지 |

**API_BASE 설정:**
```typescript
const API_BASE = import.meta.env.VITE_API_BASE || 'https://groupware.seoulventures.net';
```

**Groupware 응답 구조:**
```json
// 성공 (200)
{ "success": true, "message": "문의가 접수되었습니다." }

// 실패 (422)
{ "message": "...", "errors": { "name": [...], "phone": [...] } }
```

#### 2. `.env.production`
```
VITE_API_BASE=https://groupware.seoulventures.net
```

## 범위 외 (Phase 4에서 처리)
- vite.config.js 변경 (라라벨 플러그인 → 일반 Vite)
- S3 + CloudFront 배포
- Vapor 인프라 정리

## 테스트 항목
- [ ] 로컬에서 Groupware API 호출 테스트 (`VITE_API_BASE=http://localhost` 등)
- [ ] CORS 정상 동작 확인
- [ ] Pixel 트래킹 정상 동작 확인 (Naver WCS, Facebook, Kakao)
- [ ] 422 validation 에러 시 폼 에러 표시 확인

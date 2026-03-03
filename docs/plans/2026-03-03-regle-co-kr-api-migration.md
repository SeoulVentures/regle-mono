# [Regle] Phase 3: regle-co-kr 프론트엔드 API 전환 구현 계획

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** regle-co-kr ContactForm.vue의 API 호출 대상을 Vapor 백엔드에서 SeoulVenturesGroupware로 전환

**Architecture:** 기존 Laravel + Vite 구조를 유지한 채, ContactForm.vue의 axios 호출 URL과 바디 형식, 응답 판단 로직만 수정. 환경변수 `VITE_API_BASE`로 API 베이스 URL 관리.

**Tech Stack:** Vue 3, TypeScript, axios, Vite, Laravel Vapor (호스팅 유지)

**작업 디렉터리:** `/opt/SeoulVentures/regle/regle-co-kr`

---

### Task 1: ContactForm.vue API 호출 전환

**Files:**
- Modify: `resources/views/components/ContactForm.vue` (onSubmit 함수 내부)

**Step 1: 현재 상태 확인**

```bash
grep -n "axios.post\|status === 200\|API_BASE" resources/views/components/ContactForm.vue
```

Expected output:
```
60:    axios.post('/send-contact-request', form)
69:  if (response.value.status === 200) {
```

**Step 2: onSubmit 함수 수정**

`resources/views/components/ContactForm.vue`의 `onSubmit` 함수를 아래와 같이 수정:

```typescript
const onSubmit = async (event: Event) => {
  const form = event.target as HTMLFormElement;
  const elements = form.elements as unknown as Record<string, HTMLInputElement>;
  const body = Object.fromEntries(new FormData(form).entries());
  formStatus.value = 'submit';

  const API_BASE = import.meta.env.VITE_API_BASE || 'https://groupware.seoulventures.net';

  response.value = await
    axios.post(`${API_BASE}/api/regle/inquiry`, body)
    .catch(function (error) {
      if (error.response) {
        formStatus.value = 'ready';
        error.response.data.body = body;
        return error.response.data;
      }
    });

  if (response.value?.success === true) {
    let _nasa: Record<string, string> = {};
    _nasa['cnv'] = customWindow.wcs.cnv('4', '1');
    customWindow.wcs_do(_nasa);

    customWindow.fbq('track', 'CompleteRegistration', {
      content_name: elements['name'].value,
      status: true,
      currency: 'KRW',
      value: 100000,
      em: elements['email'].value,
      ph: elements['phone'].value,
      fn: elements['name'].value,
    });

    customWindow.kakaoPixel('4217747893436723343').participation();

    formStatus.value = 'done';
    alert('문의가 접수되었습니다.');
  }
};
```

변경 포인트 3가지:
- `axios.post('/send-contact-request', form)` → `axios.post(\`${API_BASE}/api/regle/inquiry\`, body)`
  - `form` (HTMLFormElement) → `body` (plain object): JSON 전송을 위해
- `API_BASE` 상수 추가 (`VITE_API_BASE` 환경변수 또는 기본값)
- `response.value.status === 200` → `response.value?.success === true`
  - Groupware 응답: `{ success: true, message: "문의가 접수되었습니다." }`

**Step 3: 변경 확인**

```bash
grep -n "axios.post\|success === true\|API_BASE" resources/views/components/ContactForm.vue
```

Expected:
```
XX:  const API_BASE = import.meta.env.VITE_API_BASE || 'https://groupware.seoulventures.net';
XX:    axios.post(`${API_BASE}/api/regle/inquiry`, body)
XX:  if (response.value?.success === true) {
```

**Step 4: 커밋**

```bash
git add resources/views/components/ContactForm.vue
git commit -m "feat: ContactForm API 호출 대상을 Groupware로 전환 (Phase 3)"
```

---

### Task 2: 환경변수 설정

**Files:**
- Create or Modify: `.env.production`

**Step 1: .env.production 파일 존재 여부 확인**

```bash
ls -la .env* 2>/dev/null || echo "없음"
```

**Step 2: VITE_API_BASE 추가**

`.env.production`에 아래 내용 추가 (파일이 없으면 생성):

```
VITE_API_BASE=https://groupware.seoulventures.net
```

> **주의:** `.env.production`은 보통 `.gitignore`에 포함되어 있음.
> Vapor 배포 환경에는 별도로 환경변수를 주입해야 함.

**Step 3: .gitignore 확인**

```bash
grep "env" .gitignore
```

`.env.production`이 gitignore에 포함되어 있다면, Vapor 환경변수 설정에서 `VITE_API_BASE`를 직접 설정해야 함.

**Step 4: 로컬 테스트 빌드 확인 (선택)**

```bash
npm run build 2>&1 | tail -20
```

빌드 중 에러가 없으면 성공.

---

### Task 3: PR 생성

**Step 1: 브랜치 생성 (아직 안 했다면)**

```bash
git checkout -b feat/phase3-api-migration
git push -u origin feat/phase3-api-migration
```

**Step 2: PR 생성**

```bash
gh pr create \
  --repo SeoulVentures/SeoulVenturesGroupware \
  --title "[Regle] Phase 3: regle-co-kr 프론트엔드 API 전환" \
  --body "## 개요
regle-co-kr ContactForm.vue의 API 호출 대상을 Vapor 백엔드에서 SeoulVenturesGroupware로 전환

## 변경 내역
- \`axios.post('/send-contact-request', form)\` → \`axios.post(\${API_BASE}/api/regle/inquiry\`, body)\`
- \`VITE_API_BASE\` 환경변수로 API 베이스 URL 관리
- 성공 판단 로직: \`status === 200\` → \`success === true\`

## 테스트 항목
- [ ] 로컬에서 Groupware API 호출 테스트
- [ ] CORS 정상 동작 확인
- [ ] Pixel 트래킹 정상 동작 확인 (Naver WCS, Facebook, Kakao)
- [ ] 422 validation 에러 시 폼 에러 표시 확인

Closes #452"
```

> **참고:** `regle-co-kr`은 별도 리포지터리이므로, 실제 작업은 해당 리포에서 PR을 열거나
> Groupware 이슈(#452)를 닫는 방식으로 진행.

---

## 완료 기준

- [ ] `ContactForm.vue`에서 Groupware API로 정상 요청
- [ ] 성공 시 Pixel 트래킹 정상 동작
- [ ] 실패 시 폼 에러 표시 정상 동작
- [ ] Vapor 서버에 `VITE_API_BASE` 환경변수 설정

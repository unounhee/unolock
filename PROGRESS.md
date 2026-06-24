# UnoLock — 현재 진행 상황 (이어서 작업용)

> 데스크탑 → 노트북으로 작업을 이어가기 위해 작성. 노트북에서 저장소를 받으면 이 파일부터 읽으세요.
> 마지막 업데이트: 2026-06-23

## 무엇을 만들고 있나
교재 업로드 → AI 출제(수학) → 학생 풀이 → 채점·재출제 → 통과 → 학부모 통과 알림.
자세한 기획·설계: `unolock-docs/CLAUDE.md` 와 `unolock-docs/설계자료/` 참고.

## 확정된 기술 방향
- **두뇌(서버·DB·로그인·사진저장): Supabase**
- **출제자 화면: 웹** (`web/` 폴더, Vite + React). 모든 로직은 두뇌(API)에 두는 *API-first*로 짜서 나중에 출제자 앱 전환 여지를 열어둠.
- **학생·학부모 앱: Flutter** (아직 시작 안 함. 폰 잠금은 2차).
- **AI 출제: Claude API** (Haiku 기본 / 복잡하면 Sonnet).
- **첫 과목: 수학** (재출제 루프). 영단어는 자리만 비워둠.

## 지금까지 한 것
- [x] 개발 도구 확인 — Git, Node.js, VS Code 있음 (Flutter는 나중에 학생 앱 만들 때 설치)
- [x] Supabase 무료 프로젝트 생성 (Seoul 리전, Free 요금제)
- [x] 출제자 웹 뼈대 생성 (`web/`, Vite + React) — 브라우저 구동 확인됨
- [x] `supabase-js` 설치 + 연결 코드(`web/src/supabaseClient.js`) + 연결 확인 화면(`web/src/App.jsx`)
- [x] **④-4: Supabase 키를 `web/.env.local` 에 입력 + 연결 확인 완료** (2026-06-23 노트북에서)
  - anon 키 대신 신형 **Publishable 키**(`sb_publishable_...`) 사용 — 역할 동일
  - 연결 테스트 통과: REST 응답 PGRST205("표 없음") = 연결 성공, 개발 서버 HTTP 200

## ⑤ 데이터베이스 표 설계 — 완료 ✓ (2026-06-23)
도면: `unolock-docs/설계자료/데이터베이스_설계.md` (3층 11개 시트). SQL: `supabase/migrations/`.
**11개 표 전부 생성·확인 완료(HTTP 200), 모두 RLS 잠금 ON.**
- [x] 1층(사람·공간): profiles, academies, classes, memberships, guardianships (`0001`)
  - classes 난이도 칸은 제거(난이도는 반 이름에 포함).
- [x] 2층(콘텐츠): materials, missions (`0002`)
- [x] 3층(기록): attempts, questions, answers, notifications (`0003`)
  - ⚠️ 3층 SQL은 한글 주석이 붙여넣기 때 깨져서 **주석 없는 버전**으로 실행함.

## ⑥ 로그인/인증 — 완료 ✓ (2026-06-23)
출제자 웹 이메일 로그인/가입 동작 확인.
- [x] 6-1: 가입 시 profiles 자동 생성 트리거 `handle_new_user`(`0004`). 역할 기본 'teacher'.
  - Supabase Authentication에서 "Confirm email" Off(개발 편의). 출시 전 다시 켤 것.
- [x] 6-2: 웹 로그인/가입 화면(`web/src/App.jsx`) — 가입·로그인·로그아웃, 세션 추적.
- [x] 6-3: 실제 가입 성공 확인.
- 메모: 오류 번역 함수가 'email' 포함 메시지를 전부 "형식 오류"로 가리던 버그 수정 → 모르는 오류는 원문 노출.

## ⑦ RLS 권한 규칙(정보 비대칭) — 진행 중
잠긴 표에 "출입증 규칙"을 하나씩 연다. auth.uid() = 로그인한 사람 id.
- [x] 7-1: "로그인한 사용자는 자기 profiles 줄 읽기"(`0005`). 화면에 이름·역할 표시로 검증 완료.
- [x] 7-2: "출제자는 자기 학원/반만 관리"(`0006`). Supabase에서 Run + 학원·반 생성 테스트 통과 (2026-06-24, 데스크톱).
- [ ] 7-3: 학생은 자기 미션, 학부모는 통과 결과만(정보 비대칭 핵심). ← 학생/학부모 화면 만들 때 함께.
- 이후: 교재 업로드(Storage) → AI 출제(수학).

## ⑧ 교재 업로드 — 완료 ✓ (2026-06-24)
출제자가 교재(사진/PDF)를 올리는 기능. 핵심 루프 첫 조각.
- [x] 8-1: 파일 창고(Storage 버킷 `materials`, 비공개) + 권한 규칙 (`0007_materials_storage.sql`).
  - materials 표: 출제자=자기 학원 교재만. 파일 경로 `<학원id>/<파일명>`, split_part로 첫 폴더 검사.
- [x] 8-2: 업로드 UI — `web/src/App.jsx`에 학원별 "📚 교재" 영역(`MaterialList`): 제목+파일선택 업로드, 목록 칩, 클릭 시 서명URL(60초)로 열기.
- [x] 8-3: 실제 업로드·열기 테스트 통과.

## ⑨ AI 출제(수학) — 완료 ✓ (2026-06-24) ★ 핵심 루프 첫 동작!
교재를 Claude AI가 읽고 수학 문제(객관식3+주관식2+해설)를 생성. "교사 노동 0"의 심장.
- [x] 9-1: Claude API 키 발급(Anthropic Console) — 사용 한도 설정.
- [x] 9-2: 키를 Supabase Secrets에 `ANTHROPIC_API_KEY` 로 저장(브라우저 노출 0).
- [x] 9-3: Edge Function `supabase/functions/generate-questions/index.ts` 작성·배포.
  - 호출자 JWT로 RLS 적용(자기 교재만) → Storage에서 파일 download → base64 →
    Claude + 구조화출력(JSON schema)으로 문제 생성 → 반환.
  - 모델: **`claude-sonnet-4-6`**(수학 정확도). 더 저렴하게 하려면 `claude-haiku-4-5`로 한 단어만 바꾸면 됨.
  - 프롬프트: 주관식은 "딱 하나의 명확한 값(숫자)"만(2x+y 같은 다형 문자식 답 금지 → 채점 오류 방지),
    정답·해설 자가검산, 수식은 LaTeX($...$).
- [x] 9-4: 웹 `MaterialList`에 "✨ AI 출제" 버튼 + 결과 미리보기.
- [x] 9-5: 실제 교재로 문제 생성 성공 확인.

## ⑩ 학생 풀이 화면(웹 버전) — 완료 ✓ (2026-06-24) ★ 핵심 루프 끝까지 동작!
교재 옆 "▶ 풀어보기" → 풀이 → 채점 → 8할 미달 시 재출제 루프 → 통과. (출제자가 미리 테스트 가능)
- [x] 10-1: `Solver` 컴포넌트(`web/src/App.jsx`) — 객관식/주관식 풀이, 채점(80%), 정답·해설,
  미달 시 "비슷한 문제로 다시 도전"(AI 재호출 = 재출제 루프), 통과 시 🏆.
- [x] 10-2: **KaTeX 수식 렌더링**(`MathText`) — `$...$` LaTeX를 예쁜 수식으로. (`web`에 `katex` 설치)
- 메모: 채점은 정규화 후 정확매칭. 주관식 다형 답 문제는 9-3 프롬프트에서 출제 금지로 회피.
- 한계: 아직 **출제자 화면 안에서 미리보기/테스트용**. 실제 학생이 따로 접속(계정·링크)하는 건 다음.

## ⑪ 학생 공유 링크 + 재출제 변형 + 품질보정 — 완료 ✓ (2026-06-24)
학생이 로그인 없이 "링크"로 풀고, 재도전 시 숫자만 바뀐 변형이 나오게.
- [x] 11-1: `share_links` 표 + RLS (`0008_share_links.sql`). 출제자=자기 교재 링크만.
- [x] 11-2: 공개 Edge Function `solve-link`(토큰→교재→출제, service_role, **Verify JWT OFF**).
- [x] 11-3: 웹 — 교재별 "📨 보내기"(토큰 생성+링크 복사), `?s=토큰`이면 `PublicSolve`(로그인 없이 풀이).
- [x] 11-4(품질): 재출제 = 직전 문항 `previous` 전달 → "구조 그대로, 숫자만 변형"(`generate-questions`/`solve-link` 둘 다).
  프롬프트 강화(깔끔한 정수/분수 답만, 혼잣말 금지, 문제·정답·해설 일치). JSON 파싱 안전장치.
- ⚠️ 교훈: `thinking:{adaptive}` + `output_config` + max_tokens 낮음 → JSON 잘림/낭비. **thinking 제거함.**
- 한계: 링크가 아직 `localhost` → 다른 기기에서 열리려면 웹 인터넷 배포 필요(아래).

## 🖥️ 다음 할 일 (현재 위치)
링크로 학생이 풀이까지 웹에서 완성. 다음 후보:
- **웹 인터넷 배포(호스팅)** ⭐ — Vercel 등에 올려 공개 URL 확보. → 그래야 보낸 링크가 학생 폰에서 열림(진짜 테스트).
  (Vite 빌드 + `.env`의 Supabase 값 호스팅쪽에 입력 필요.)
- **풀이 결과 저장**: `attempts`/`questions`/`answers` 기록(통과 여부·재시험 횟수 → 정보 비대칭 데이터) + 7-3 권한.
- **학부모 통과 알림**(`notifications`).
- 그 뒤(앱화): 학생/학부모 Flutter 앱 + 폰 잠금(2차).
- 보류: 영단어 과목, 결제, 주간 리포트.
- 비용 메모: 출제 모델 `claude-sonnet-4-6`(정확도). 절약하려면 함수에서 `claude-haiku-4-5`로 교체. 사용 한도는 Anthropic Console.

## 노트북에서 처음 시작하기
1. **Git, Node.js, VS Code** 설치 (없으면)
2. 저장소 받기: `git clone https://github.com/unounhee/unolock.git`
   (처음에 GitHub 로그인 = **unounhee** 계정으로)
3. `cd unolock/web` 후 `npm install` (부품(node_modules)은 업로드 안 됐으니 다시 받음)
4. `web/.env.local` 파일을 **새로 만들고** 위 ④-4의 두 값을 입력
   (이 파일은 보안상 GitHub에 올리지 않으므로 노트북엔 없음 — 직접 다시 만들어야 함)
5. `npm run dev` → 브라우저에서 `http://localhost:5173` 열기

## 작업 규칙 (대표님 요청 — 꼭 지킬 것)
- 한 번에 다 하지 말고 **한 단계씩**, 끝나면 "이거 됐는지 확인" 받고 다음으로.
- 비밀번호·API 키 같은 민감정보는 **대표님이 직접 입력.** Claude는 위치만 안내하고 값은 보지 않음.
- 비전공자 대상 → 무엇을·왜 하는지 **쉽게 먼저 설명**하고 진행.

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

## 바로 다음 할 일 (⑤: 데이터베이스 표 설계)
연결이 끝났으니 이제 **계정·권한 구조(표/테이블) 설계**로 넘어갑니다.
- `unolock-docs/설계자료/`의 계정·화면·보상 다이어그램을 근거로 표 구조를 잡는다.
- 첫 표 후보: 사용자(출제자/학생/학부모 역할), 교재, 문제, 풀이/채점 기록.
- Supabase 대시보드 SQL Editor 또는 마이그레이션으로 표 생성 → RLS(접근권한) 고려.
- 그다음: 교재 업로드 → AI 출제(수학) 순서.

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

# UnoLock — 현재 진행 상황 (이어서 작업용)

> 데스크탑 → 노트북으로 작업을 이어가기 위해 작성. 노트북에서 저장소를 받으면 이 파일부터 읽으세요.
> 마지막 업데이트: 2026-06-27 — ⑯ **2차 앱 착수: 폰 잠금 실험 성공 ✓** (`app/` Flutter, 실제 폰에서 화면 고정 작동 확인). **다음: 학생/학부모 Flutter 앱 본격 제작 + DB 계정 정리(7-3, attempts/notifications), 별도로 AI 출제 방식 실험.**

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

## ⑫ 웹 인터넷 배포 — 완료 ✓ (2026-06-24)
공개 URL 확보 → 보낸 링크가 학생 폰에서 진짜로 열림.
- [x] 12-1: **Cloudflare Pages**에 GitHub(unounhee/unolock) 연결 배포. 루트 `web`, 빌드 `npm run build`, 출력 `dist`.
  Supabase 값 2개는 Cloudflare 환경변수에 입력. 이후 git push 시 자동 재배포.
- [x] 12-2: 공개 주소 **https://unolock.pages.dev** (HTTP 200 확인). 최신 빌드 해시 일치 확인.
- [x] 12-3: 공유 링크는 `window.location.origin` 사용 → 자동으로 `https://unolock.pages.dev/?s=토큰` 생성.
  Edge Function 2개 CORS `*` 라 새 도메인에서 호출 OK. 화면의 옛 'localhost' 안내문구 수정.

## ⑬ 수업 묶음(반마다 여러 장 업로드 + 무작위 출제) — 완료 ✓ (2026-06-25)
대표님 요청: 한 반에 사진 여러 장을 한 번에 올리고(=그 반의 오늘 수업), 출제는 그 페이지 중 **무작위**로.
**새 업로드가 시작되면 이전 묶음은 "지난 수업"이라 출제에서 자동으로 빠짐(무시, 파일은 안 지움).**
결정사항: 경계=**반(클래스)마다**, 옛 묶음=**무시**(삭제 안 함), 학생 링크=**반당 1개**(항상 그 반 최신 수업으로 자동 갱신).

- [x] 13-1(DB): `0009_lesson_batches.sql` — `lesson_batches` 표 + `materials`에 `batch_id`/`class_id` 칸 + `share_links`에 `class_id`(material_id는 nullable로). RLS 갱신. **→ Supabase에서 Run 완료(성공 확인).**
- [x] 13-2(웹): `web/src/App.jsx` — 교재 영역을 **반 밑(`ClassLesson`)으로 이동**. `<input multiple>`로 여러 장 업로드=새 묶음. "오늘 수업 N장" 표시, 이전 묶음은 화면에서 안 보임. 버튼: ✨AI출제 / ▶풀어보기 / 📨학생 링크(반당 1개 재사용). `MaterialList` 컴포넌트 삭제. `Solver`는 `material`→`batch` 사용. **빌드 통과 확인.**
- [x] 13-3(함수): `generate-questions`(인증 호출, batch_id) + `solve-link`(토큰→반→최신 묶음) 둘 다 **여러 장 다운로드 → 무작위 최대 2장 골라 출제**(`buildImageBlocks`). 옛 단일 교재/링크 호환 유지.
- [x] 13-4(배포·테스트) — 데스크톱에서 완료 (2026-06-25):
  - 함수 2개 재배포(`generate-questions`, `solve-link`(Verify JWT OFF)) — 대시보드에 VS Code 코드 붙여넣기.
  - 웹은 push됨 → Cloudflare 자동배포.
  - 실제 테스트 통과: 반 만들기 → 사진 여러 장 업로드(묶음) → ✨AI출제(무작위) → ▶풀어보기 → 📨학생 링크 폰 풀이까지 정상.

## ⑭ 풀이 결과 저장 — 거의 완료 ✓ (2026-06-25), 14-4(결과 화면)만 남음
학생이 링크에서 이름 한 번 입력 → 풀이 → 채점되면 **서버가 결과를 기록**. 정보 비대칭 데이터의 토대.
설계 충돌 해소: 옛 기록표는 "학생계정+저장된 미션" 가정이었으나, 지금 제품은 "링크 익명풀이+즉석 AI출제+묶음 기준".
→ 학생 구분은 **"이름만 입력"**(계정 없음, 검증 안 됨, 학부모 연결은 나중)로 결정.
- [x] 14-1(DB): `0010_attempt_records.sql` — `attempts`에 `batch_id`/`student_name`/`share_token` 추가,
  `mission_id`·`student_id`를 nullable로, 옛 유니크 제약 제거 + 색인. 출제자가 **자기 반 풀이만 읽는** RLS
  (attempts/questions/answers). **→ Supabase Run 완료.**
- [x] 14-2(함수): 공개 `record-attempt`(신규, **Verify JWT OFF**) — 토큰+이름+풀이 받아 **서버가 정답 대조로 재채점**
  → attempts/questions/answers 저장. (브라우저의 passed는 신뢰 안 함). **→ 배포 완료.**
- [x] 14-3(웹): `PublicSolve`에 **이름 입력칸** + 채점 시 `record-attempt` 호출. 출제자 미리보기(batch)는 기록 안 함.
  채점할 때마다 기록(통과/실패 무관, 회차=attempt_no). **→ push·자동배포 완료.**
- [x] 14-4(웹): 출제자 화면 **"📊 풀이 결과"** 보기(`loadResults`) — 학생 이름별 시도 횟수·처음 통과 회차·최고 점수. **동작 확인 완료(2026-06-26).**
- ⚠️ 배포 사고/교훈(2026-06-26): `record-attempt` 함수가 대시보드에서 **임의 이름(`smooth-hand-…`)으로 배포**돼 있어서 웹의 `invoke('record-attempt')`가 404(함수 없음) → 결과가 조용히 저장 안 됨(웹은 `.catch` 무시). **올바른 이름 `record-attempt`로 재배포(Verify JWT OFF)하니 해결.** 교훈: 대시보드 "Via Editor"로 함수 만들 때 **이름 칸의 임의 이름을 꼭 폴더명과 똑같이 바꿀 것.** 함수명은 곧 URL이고, 한번 만들면 이름 변경 불가(새로 만들고 옛것 삭제).
- 메모(출제 품질): 불량 문항(답이 범위/조건/θ/근사) 방지 — 프롬프트 강화 + **코드 자동 검열**(`isGoodQuestion`,
  불량 버리고 부족하면 재생성 최대 2회) 적용. **언제든 규칙만 고쳐 두 함수 재배포하면 수정 가능.** (둘 다 배포 완료)

## ⑮ 학부모 통과 알림 — 간단 버전 ✓ (2026-06-26)
학부모 **계정 없이**, 학생이 통과하면 "통과증 링크"를 카톡 등으로 전달하는 방식. (옛 `notifications` 표는 parent_id/student_id 계정 가정이라 지금 모델과 안 맞음 → 보류, 나중에 계정 생기면 사용.)
- [x] 15-1(함수): 공개 `pass-cert`(신규, **Verify JWT OFF**) — `?cert=결과ID(attempt_id)` → 이름·점수·회차·통과여부만 반환(문제/답은 비공개). service_role, 추측 불가 UUID로 접근통제. **→ 배포·확인 완료.**
- [x] 15-2(웹): 학생 통과(🏆) 시 **"📩 부모님께 통과 소식 보내기"** 버튼 → `?cert=` 링크 복사. `record-attempt` 응답의 `attempt_id`를 받아 사용. **→ push·자동배포.**
- [x] 15-3(웹): `PassCertificate` 화면 — 학부모가 `?cert=` 링크 열면 "○○ 학생, N번 만에 통과! XX점" 통과증. **→ push·자동배포.**
- [x] 15-4: **실제 통과 테스트 통과(2026-06-26)** — 학생 링크로 통과 → "📩 부모님께" 버튼 → 통과증 링크 다른 데서 열어 정상 확인. ⑮ 전체 완료 ✓
- 메모: 통과 못 하면 버튼 안 뜸(통과 시에만). 출제자 미리보기(batch)는 certId 안 생겨 버튼 없음(학생 링크 풀이일 때만).

## ⑯ 2차 — 학생/학부모 앱(Flutter) 착수 + 폰 잠금 실험 ✓ (2026-06-27)
웹+Supabase 핵심 완성 후 앱 단계로. 가장 불확실한 **"폰 잠금이 진짜 되나"**부터 실험.
- 폴더: 기존 저장소 안에 **`app/`** (web/과 나란히, web/은 안 건드림). `flutter create --org com.unolock --platforms=android --project-name unolock_app app`.
- [x] 16-1: 초미니 실험 앱 — 🔒/🔓 버튼 화면(`app/lib/main.dart`) + 네이티브 화면고정(`MainActivity.kt`, MethodChannel `unolock/lock` → `startLockTask()`/`stopLockTask()`). flutter analyze 통과.
- [x] 16-2: 실제 폰(SM S948N, Android 16)에 설치·실행 → **버튼으로 화면 고정(다른 앱 차단) 작동 확인 성공!** 🎉
  - 지금은 **간이 잠금(Screen Pinning)** — 학생이 뒤로+최근앱 길게 누르면 풀림. 나중에 **완전 잠금(기기 관리자 모드)**으로 강화 가능(같은 원리 확장).
- [x] 16-3: 앱을 **Supabase(두뇌)에 연결** — `supabase_flutter` 추가, `app/lib/supabase_client.dart`(init), 연결값은 `app/env.json`(gitignore, `--dart-define-from-file`로 주입, `env.example.json` 템플릿). 임시 "두뇌 연결 확인" 화면으로 **실제 폰에서 연결 성공 확인**. 잠금 실험은 `lock_test_page.dart`로 분리 보관. (출제자 키 publishable이라 공개 안전·RLS 보호) **다음: 출제자 로그인(웹 이메일 계정 재사용) → 반 목록 → 촬영·업로드 → AI 출제.**
- [x] 16-4: 출제자 **로그인**(웹 이메일 계정 재사용, `login_page.dart`) + **내 학원·반 목록**(`teacher_home_page.dart`, `academies` + 중첩 `classes` 조회, RLS가 내 것만). `main.dart`에 AuthGate(로그인 상태 분기)·NoKeysPage 추가. 실제 폰에서 로그인·반 목록 확인. **다음: 반 탭 → 사진 촬영·업로드(image_picker, Storage `materials` 버킷, lesson_batches=오늘 수업) → ✨AI 출제(generate-questions 호출).**
- [x] 16-5: 출제자 앱 **촬영→업로드→AI출제** 완성(`class_lesson_page.dart`) — image_picker(촬영/갤러리 여러 장), 웹과 동일하게 `lesson_batches` 새 묶음 생성 + `materials` 버킷 업로드(경로 `학원id/묶음id/시간_파일`), `generate-questions` 호출. **수식 렌더링 `MathText`**(flutter_math_fork, `$...$` LaTeX) 추가 — 출제자 미리보기와 학생 화면 공용. ⚠️ 함수가 주는 문항 필드명은 `body/choices/correct_answer/explanation/type`(question/options/answer 아님). 실제 폰에서 전 과정 + 정답·해설 수식 확인. **다음: 학생 앱(잠금+풀이 화면, MathText·검증된 폰잠금 결합).**
- [x] 16-6 (S1): **정식 계정 기초** — 유형 선택(`landing_page.dart`: 학생/출제자) + 학생 가입/로그인(`student_auth_page.dart`, `signUp` 시 `data:{role:'student',full_name}` → 0004 트리거가 student 프로필 생성) + 역할 라우팅(`main.dart` RoleRouter: profiles.role 읽어 학생홈/출제자홈 분기) + `student_home_page.dart`(자리). 로그인/가입 성공 시 `popUntil(isFirst)`로 첫화면 복귀 → AuthGate가 역할별 홈으로. 실제 폰에서 학생 가입·역할 분기 확인. **다음 S2: 반 코드 + 선생님 승인/내보내기(DB: classes 참가코드 + join RPC + memberships RLS, 앱: 코드입력·관리 화면). 이후 S3 학생 오늘 미션, S4 풀이+잠금, S5 RLS 7-3.**
- [x] 16-7 (S2): **반 코드 + 승인/내보내기** — DB `0011_class_join_codes.sql`(classes.join_code 기본값 자동부여, `join_class_by_code` RPC=학생이 코드로 신청, memberships/profiles/classes RLS) + `0012_fix_policy_recursion.sql`(정책 상호참조 무한반복 → `is_class_owner`/`is_my_class`/`is_my_student` SECURITY DEFINER 함수로 끊음). 앱: 출제자 홈에 참가코드+[학생 관리], `class_members_page.dart`(승인/거절/내보내기), `student_home_page.dart`(코드 신청 + 내 반 상태). 실제 폰에서 가입→코드신청→승인→내보내기 전 과정 확인.
  - ⚠️ Supabase SQL Editor 교훈: 함수는 **plpgsql begin/end 형태**로 쓸 것(`language sql` 단일 select 본문이 에디터에서 syntax error 유발). 그리고 **실행 전 에디터를 꼭 비울 것**(이전 내용 남으면 줄 밀려 엉뚱한 에러).
  - **다음 S3: 학생이 승인된 반의 "오늘 미션" 풀기(잠금+MathText) + record-attempt에 student_id. 학생이 자기 반 batch/materials/questions 읽는 RLS(7-3) 필요.**
- [x] 16-8 (S3b): **학생 미션 풀이 + 폰 잠금 틀 완성** — `0013_student_mission_read.sql`(승인 학생이 자기 반 lesson_batches/materials/storage 읽기 RLS: `is_approved_member`/`is_my_batch`/`can_read_material_path` SECURITY DEFINER) + `student_mission_page.dart`(최신 batch → `generate-questions` 재사용, 🔒startLockTask → 문제풀이(MathText) → 80% 채점 → 미달 시 previous로 재출제 루프 → 통과 시 🔓stopLockTask). 학생홈 승인 반 탭 → 미션. **잠금+풀이+채점+재출제+통과 기계장치 동작 확인.**
  - ⚠️ 알려진 한계: **AI 직접 생성 문항 품질 불량**(문제/정답/해설 불일치 → 채점·재출제 꼬임). 대표 결정대로 **이 부분은 "AI=단원분류 + 검증된 문항 DB에서 출제" 방식으로 교체 예정**(별도 작업, questions 형식 동일하면 앱·풀이화면 그대로). 지금은 틀만 확정.
  - **다음 후보: S3c(풀이 결과 student_id로 기록 → 교사 결과·학부모 통과알림) / 학부모 앱 / 문항 DB 방식 실험.**
- [x] 16-9 (S3c-1): **계정 학생 결과 기록** — 새 함수 `supabase/functions/record-mission/index.ts`(Verify JWT ON: JWT로 student_id 식별 → 승인 학생 확인 → 서버 재채점 → attempts/questions/answers에 student_id로 저장). 앱 `student_mission_page.dart`가 채점 끝(통과/실패)마다 학생답 모아 호출(회차=attempt_no). 실제 폰에서 통과 시 attempts에 student_id 기록 확인. **다음 S3c-2: 학부모 통과 알림(학부모 계정·guardianship 자녀연결·통과만 보기).**
- ⚠️ 연결 교훈: 이 노트북은 **유선 USB로 폰이 안 잡힘**(윈도우가 ADB 인터페이스를 안 만듦, `PID_6860` 단일기능). **무선(Wi-Fi) 디버깅으로 연결**해야 함. `adb`는 PATH에 없어 전체경로(`...\Android\Sdk\platform-tools\adb.exe`) 사용. 무선 연결: 폰 개발자옵션 → 무선 디버깅 → 페어링코드 → `adb pair ip:port code` → `adb connect ip:port`(포트 다름). IP/포트·코드는 매번 바뀜.
- 다음(이번 작업 이후): 학생/학부모 앱 본격 제작 + DB 계정 기반 정리(7-3 권한, attempts.student_id, notifications.parent_id — 지금은 "이름만/계정없음"으로 우회 중). 별개로 **AI 출제 방식 실험**(AI=단원 분류만, 문제는 검증된 문항 DB에서 — questions 표 형식 같으면 출제 방식만 교체라 독립적, 점검 예정).

## 🖥️ 그 다음 후보
- **학부모 통과 알림**(`notifications`) — 14-3에서 생긴 student_name에 연결.
- 학생/학부모 권한 7-3(정보 비대칭 마무리).
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

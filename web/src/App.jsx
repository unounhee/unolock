import { useEffect, useState } from 'react'
import katex from 'katex'
import 'katex/dist/katex.min.css'
import { supabase, hasKeys } from './supabaseClient'

// AI가 쓴 LaTeX 수식($...$)을 예쁜 수식으로 그려준다. 수식이 아니면 그냥 글자.
function MathText({ children }) {
  const parts = String(children ?? '').split(/(\$\$[^$]*\$\$|\$[^$]*\$)/g)
  return (
    <>
      {parts.map((p, i) => {
        const display = p.startsWith('$$') && p.endsWith('$$') && p.length >= 4
        const inline = !display && p.startsWith('$') && p.endsWith('$') && p.length >= 2
        if (display || inline) {
          const tex = p.slice(display ? 2 : 1, p.length - (display ? 2 : 1))
          try {
            const html = katex.renderToString(tex, { throwOnError: false, displayMode: display })
            return <span key={i} dangerouslySetInnerHTML={{ __html: html }} />
          } catch (_) {
            return <span key={i}>{p}</span>
          }
        }
        return <span key={i}>{p}</span>
      })}
    </>
  )
}

function App() {
  const [session, setSession] = useState(null)
  const [ready, setReady] = useState(false)

  // 로그인 상태를 확인하고, 바뀔 때마다 따라갑니다.
  useEffect(() => {
    if (!hasKeys) { setReady(true); return }
    supabase.auth.getSession().then(({ data }) => {
      setSession(data.session)
      setReady(true)
    })
    const { data: sub } = supabase.auth.onAuthStateChange((_e, s) => setSession(s))
    return () => sub.subscription.unsubscribe()
  }, [])

  if (!hasKeys) return <Center><Title emoji="🔌" text="키가 비어있어요" sub=".env.local 을 확인해 주세요." /></Center>
  // 학생 공유 링크(?s=토큰)로 들어오면 로그인 없이 바로 풀이 화면.
  const shareToken = new URLSearchParams(window.location.search).get('s')
  if (shareToken) return <Center><PublicSolve token={shareToken} /></Center>
  if (!ready) return <Center><Title emoji="⏳" text="확인 중…" /></Center>
  return <Center>{session ? <LoggedIn session={session} /> : <AuthForm />}</Center>
}

// 로그인된 대시보드 — 프로필 머리말 + 내 학원/반 관리
function LoggedIn({ session }) {
  const [profile, setProfile] = useState(null)
  const [loaded, setLoaded] = useState(false)

  // 권한 규칙(RLS)이 열려 있으면 자기 profiles 줄을 읽어옵니다.
  useEffect(() => {
    supabase.from('profiles').select('role, full_name').eq('id', session.user.id).maybeSingle()
      .then(({ data }) => { setProfile(data); setLoaded(true) })
  }, [session.user.id])

  const roleLabel = { teacher: '출제자', student: '학생', parent: '학부모' }[profile?.role] || profile?.role

  return (
    <div style={panel}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 18 }}>
        <div>
          <div style={{ fontSize: 18, fontWeight: 700, color: '#1a1a1a' }}>
            {profile?.full_name || session.user.email}
            {profile && <span style={{ fontSize: 13, color: '#2E75B6', marginLeft: 6 }}>{roleLabel}</span>}
          </div>
          <div style={{ fontSize: 12, color: '#999' }}>{session.user.email}</div>
        </div>
        <button style={btnGhost} onClick={() => supabase.auth.signOut()}>로그아웃</button>
      </div>

      {loaded && !profile && (
        <p style={errBox}>프로필을 못 읽었어요. 권한 규칙(RLS)이 켜졌는지 확인해 주세요.</p>
      )}

      <Workspace userId={session.user.id} />
      <p style={foot}>UnoLock · 출제자 웹</p>
    </div>
  )
}

// 내 학원 목록 + 학원 만들기
function Workspace({ userId }) {
  const [academies, setAcademies] = useState([])
  const [name, setName] = useState('')
  const [err, setErr] = useState('')

  const load = async () => {
    const { data, error } = await supabase.from('academies').select('id, name').order('created_at')
    if (error) setErr(error.message); else setAcademies(data || [])
  }
  useEffect(() => { load() }, [])

  const add = async (e) => {
    e.preventDefault()
    if (!name.trim()) return
    setErr('')
    const { error } = await supabase.from('academies').insert({ name: name.trim(), owner_id: userId })
    if (error) { setErr(error.message); return }
    setName(''); load()
  }

  return (
    <div>
      <h2 style={h2}>내 학원</h2>
      {academies.length === 0 && <p style={muted}>아직 학원이 없어요. 아래에서 하나 만들어 보세요.</p>}
      {academies.map((a) => (
        <div key={a.id} style={box}>
          <div style={{ fontWeight: 700, marginBottom: 8 }}>🏫 {a.name}</div>
          <ClassList academyId={a.id} />
          <MaterialList academyId={a.id} userId={userId} />
        </div>
      ))}
      <form onSubmit={add} style={{ display: 'flex', gap: 8, marginTop: 10 }}>
        <input style={{ ...input, marginBottom: 0, flex: 1 }} placeholder="학원/과외 이름"
          value={name} onChange={(e) => setName(e.target.value)} />
        <button style={{ ...btn, marginTop: 0, padding: '0 18px' }} type="submit">+ 학원</button>
      </form>
      {err && <p style={errBox}>{err}</p>}
    </div>
  )
}

// 한 학원의 반 목록 + 반 만들기
function ClassList({ academyId }) {
  const [classes, setClasses] = useState([])
  const [name, setName] = useState('')

  const load = async () => {
    const { data } = await supabase.from('classes').select('id, name').eq('academy_id', academyId).order('created_at')
    setClasses(data || [])
  }
  useEffect(() => { load() }, [academyId])

  const add = async (e) => {
    e.preventDefault()
    if (!name.trim()) return
    const { error } = await supabase.from('classes').insert({ academy_id: academyId, name: name.trim() })
    if (!error) { setName(''); load() }
  }

  return (
    <div style={{ paddingLeft: 6 }}>
      {classes.map((c) => <div key={c.id} style={chip}>📘 {c.name}</div>)}
      {classes.length === 0 && <span style={{ ...muted, fontSize: 12 }}>반 없음 · </span>}
      <form onSubmit={add} style={{ display: 'inline-flex', gap: 6, marginTop: 6 }}>
        <input style={{ ...input, marginBottom: 0, padding: '6px 10px', width: 130, fontSize: 13 }}
          placeholder="반 이름" value={name} onChange={(e) => setName(e.target.value)} />
        <button style={{ ...btnGhost, padding: '6px 12px', fontSize: 13 }} type="submit">+ 반</button>
      </form>
    </div>
  )
}

// 한 학원의 교재 목록 + 교재 업로드 (사진/PDF)
function MaterialList({ academyId, userId }) {
  const [materials, setMaterials] = useState([])
  const [title, setTitle] = useState('')
  const [file, setFile] = useState(null)
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState('')
  const [genBusy, setGenBusy] = useState('')  // AI 출제 중인 교재 id
  const [genErr, setGenErr] = useState('')
  const [quiz, setQuiz] = useState(null)      // { title, questions }
  const [solving, setSolving] = useState(null) // 학생처럼 풀어보는 교재
  const [shareUrl, setShareUrl] = useState('')  // 방금 만든 학생 링크

  const load = async () => {
    const { data } = await supabase.from('materials')
      .select('id, title, file_type, storage_path, created_at')
      .eq('academy_id', academyId).order('created_at')
    setMaterials(data || [])
  }
  useEffect(() => { load() }, [academyId])

  const upload = async (e) => {
    e.preventDefault()
    setErr('')
    if (!file) { setErr('파일을 먼저 선택해 주세요.'); return }
    const fileType = file.type === 'application/pdf' ? 'pdf'
      : file.type.startsWith('image/') ? 'image' : null
    if (!fileType) { setErr('이미지(JPG/PNG) 또는 PDF만 올릴 수 있어요.'); return }
    setBusy(true)
    try {
      // 파일 경로: "<학원id>/<시간>_<파일명>" — 권한 규칙이 첫 폴더(학원id)로 확인합니다.
      const safe = file.name.replace(/[^\w.\-]/g, '_')
      const path = `${academyId}/${Date.now()}_${safe}`
      const up = await supabase.storage.from('materials').upload(path, file)
      if (up.error) throw up.error
      const ins = await supabase.from('materials').insert({
        academy_id: academyId,
        uploaded_by: userId,
        title: title.trim() || file.name,
        storage_path: path,
        file_type: fileType,
      })
      if (ins.error) throw ins.error
      setTitle(''); setFile(null)
      if (e.target.reset) e.target.reset()
      load()
    } catch (e2) {
      setErr(e2.message || '업로드에 실패했어요.')
    } finally {
      setBusy(false)
    }
  }

  // 비공개 파일이라, 잠깐 열어볼 임시 링크(60초)를 만들어 새 탭으로 엽니다.
  const open = async (m) => {
    const { data, error } = await supabase.storage.from('materials').createSignedUrl(m.storage_path, 60)
    if (!error && data?.signedUrl) window.open(data.signedUrl, '_blank')
  }

  // AI 출제: 교재를 서버(Edge Function)로 보내 수학 문제를 생성받는다.
  const generate = async (m) => {
    setGenErr(''); setQuiz(null); setGenBusy(m.id)
    const { data, error } = await supabase.functions.invoke('generate-questions', {
      body: { material_id: m.id },
    })
    setGenBusy('')
    if (error) {
      let msg = error.message || 'AI 출제에 실패했어요.'
      try { const b = await error.context.json(); if (b?.error) msg = b.error } catch (_) { /* noop */ }
      setGenErr(msg); return
    }
    if (data?.error) { setGenErr(data.error); return }
    setQuiz({ title: data?.title, questions: data?.questions || [] })
  }

  // 학생에게 보낼 풀이 링크 생성 + 클립보드 복사
  const share = async (m) => {
    setGenErr(''); setShareUrl('')
    const token = (crypto.randomUUID?.() || `${Date.now()}-${Math.random()}`).replace(/-/g, '')
    const { error } = await supabase.from('share_links')
      .insert({ token, material_id: m.id, created_by: userId, label: m.title })
    if (error) { setGenErr(error.message); return }
    const url = `${window.location.origin}/?s=${token}`
    try { await navigator.clipboard.writeText(url) } catch (_) { /* noop */ }
    setShareUrl(url)
  }

  return (
    <div style={{ paddingLeft: 6, marginTop: 10, borderTop: '1px solid #eee', paddingTop: 10 }}>
      <div style={{ fontSize: 13, fontWeight: 700, color: '#555', marginBottom: 6 }}>📚 교재</div>
      {materials.map((m) => (
        <div key={m.id} style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 6 }}>
          <span style={{ ...chip, marginBottom: 0, background: '#f0f7ee', color: '#3d7a2e', cursor: 'pointer' }}
            onClick={() => open(m)} title="클릭하면 열려요">
            {m.file_type === 'pdf' ? '📄' : '🖼️'} {m.title}
          </span>
          <button type="button" disabled={genBusy === m.id}
            style={{ ...btn, marginTop: 0, padding: '6px 12px', fontSize: 13, background: '#6c5ce7' }}
            onClick={() => generate(m)}>
            {genBusy === m.id ? 'AI 출제 중…' : '✨ AI 출제'}
          </button>
          <button type="button"
            style={{ ...btnGhost, padding: '6px 12px', fontSize: 13 }}
            onClick={() => setSolving(m)}>
            ▶ 풀어보기
          </button>
          <button type="button"
            style={{ ...btnGhost, padding: '6px 12px', fontSize: 13 }}
            onClick={() => share(m)}>
            📨 보내기
          </button>
        </div>
      ))}
      {materials.length === 0 && <span style={{ ...muted, fontSize: 12 }}>교재 없음 · </span>}
      <form onSubmit={upload} style={{ marginTop: 8 }}>
        <input style={{ ...input, marginBottom: 6, padding: '8px 10px', fontSize: 13 }}
          placeholder="교재 제목 (예: 일차방정식 p.32)" value={title} onChange={(e) => setTitle(e.target.value)} />
        <div style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
          <input type="file" accept="image/*,application/pdf" style={{ fontSize: 12, flex: 1 }}
            onChange={(e) => setFile(e.target.files[0] || null)} />
          <button style={{ ...btn, marginTop: 0, padding: '8px 14px', fontSize: 13 }} type="submit" disabled={busy}>
            {busy ? '올리는 중…' : '+ 교재'}
          </button>
        </div>
      </form>
      {err && <p style={errBox}>{err}</p>}
      {genErr && <p style={errBox}>{genErr}</p>}
      {shareUrl && (
        <div style={{ marginTop: 8, fontSize: 12, background: '#eef7ff', border: '1px solid #cfe6ff', borderRadius: 8, padding: '8px 10px' }}>
          ✅ 학생에게 보낼 링크가 <b>복사</b>됐어요. 카톡 등에 붙여넣어 보내세요:
          <div style={{ marginTop: 4, wordBreak: 'break-all', color: '#2E75B6' }}>{shareUrl}</div>
          <div style={{ marginTop: 4, color: '#999' }}>※ 지금은 이 컴퓨터(localhost)에서만 열려요. ⑪-4에서 인터넷에 올리면 다른 폰에서도 열립니다.</div>
        </div>
      )}
      {quiz && (
        <div style={{ marginTop: 10, background: '#faf9ff', border: '1px solid #e6e1fb', borderRadius: 10, padding: '12px 14px' }}>
          <div style={{ fontSize: 13, fontWeight: 700, color: '#4b3bbd', marginBottom: 8 }}>
            ✨ AI가 만든 문제 미리보기{quiz.title ? ` · ${quiz.title}` : ''}
          </div>
          {(quiz.questions || []).map((q, i) => (
            <div key={i} style={{ marginBottom: 10, fontSize: 13 }}>
              <div style={{ fontWeight: 600 }}>{i + 1}. [{q.type === 'mc' ? '객관식' : '주관식'}] <MathText>{q.body}</MathText></div>
              {q.type === 'mc' && (q.choices || []).map((c, j) => (
                <div key={j} style={{ color: '#555', marginLeft: 8 }}>{['①', '②', '③', '④', '⑤'][j] || '·'} <MathText>{c}</MathText></div>
              ))}
              <div style={{ color: '#2e7d32', marginTop: 2 }}>정답: <MathText>{q.correct_answer}</MathText></div>
              {q.explanation && <div style={{ color: '#888' }}>해설: <MathText>{q.explanation}</MathText></div>}
            </div>
          ))}
          {(!quiz.questions || quiz.questions.length === 0) && (
            <div style={{ ...muted, fontSize: 12 }}>문제가 비어있어요. 다시 시도해 주세요.</div>
          )}
        </div>
      )}
      {solving && <Solver material={solving} onClose={() => setSolving(null)} />}
    </div>
  )
}

// 학생처럼 풀어보기 — 풀이 → 채점 → 8할 미달 시 비슷한 새 문제 재출제 → 통과
function Solver({ material, token, onClose }) {
  const isPublic = !!token
  const [round, setRound] = useState(1)
  const [questions, setQuestions] = useState([])
  const [answers, setAnswers] = useState({})   // 문제번호 → 학생 답
  const [phase, setPhase] = useState('loading') // loading | solving | graded
  const [graded, setGraded] = useState(null)
  const [err, setErr] = useState('')
  const [title, setTitle] = useState(material?.title || '')

  const fetchQuestions = async (prev) => {
    setPhase('loading'); setErr(''); setAnswers({}); setGraded(null)
    const base = isPublic ? { token } : { material_id: material.id }
    const reqBody = (prev && prev.length) ? { ...base, previous: prev } : base
    const { data, error } = await supabase.functions.invoke(
      isPublic ? 'solve-link' : 'generate-questions',
      { body: reqBody },
    )
    if (error) {
      let msg = error.message || '문제를 불러오지 못했어요.'
      try { const b = await error.context.json(); if (b?.error) msg = b.error } catch (_) { /* noop */ }
      setErr(msg); setQuestions([]); setPhase('solving'); return
    }
    if (data?.error) { setErr(data.error); setQuestions([]); setPhase('solving'); return }
    if (data?.title) setTitle(data.title)
    setQuestions(data.questions || [])
    setPhase('solving')
  }
  useEffect(() => { fetchQuestions(null) }, []) // 첫 출제(교재 기반). 재출제는 retry()가 처리.

  const norm = (s) => (s ?? '').toString().trim().replace(/\s+/g, ' ').toLowerCase()
  const allAnswered = questions.length > 0 && questions.every((_, i) => (answers[i] ?? '') !== '')

  const grade = () => {
    const results = questions.map((q, i) => ({
      correct: (answers[i] ?? '') !== '' && norm(answers[i]) === norm(q.correct_answer),
    }))
    const correctCount = results.filter((r) => r.correct).length
    const total = questions.length || 1
    setGraded({ results, correctCount, total, passed: correctCount / total >= 0.8 })
    setPhase('graded')
  }

  // 재출제: 직전 문항의 구조는 그대로, 숫자만 바꾼 새 문제를 받는다.
  const retry = () => {
    const prev = questions.map((q) => ({ type: q.type, body: q.body, choices: q.choices }))
    setRound((r) => r + 1)
    fetchQuestions(prev)
  }

  const tag = { fontSize: 11, fontWeight: 700, color: '#fff', background: '#6c5ce7', borderRadius: 12, padding: '3px 10px' }

  return (
    <div style={{ marginTop: 12, border: '2px solid #c5b9f7', borderRadius: 14, background: '#fff', padding: '14px 16px' }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 10 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
          <span style={tag}>수학</span>
          <span style={{ fontSize: 13, fontWeight: 700 }}>{title || '수학 미션'}</span>
          <span style={{ fontSize: 11, color: '#999' }}>· 통과 80% · {round}회차</span>
        </div>
        {onClose && <button style={{ ...btnGhost, padding: '4px 10px', fontSize: 12 }} onClick={onClose}>닫기 ✕</button>}
      </div>

      {err && <p style={errBox}>{err}</p>}
      {phase === 'loading' && <p style={{ ...muted, textAlign: 'center', padding: 16 }}>⏳ AI가 문제를 준비하고 있어요…</p>}

      {phase !== 'loading' && questions.map((q, i) => {
        const r = graded?.results[i]
        return (
          <div key={i} style={{ marginBottom: 14, paddingBottom: 12, borderBottom: '1px solid #f0f0f0' }}>
            <div style={{ fontWeight: 600, fontSize: 14, marginBottom: 6 }}>
              {i + 1}. <MathText>{q.body}</MathText>
              {graded && (r.correct
                ? <span style={{ color: '#2e7d32', marginLeft: 6 }}>✓ 정답</span>
                : <span style={{ color: '#d64545', marginLeft: 6 }}>✗ 오답</span>)}
            </div>
            {q.type === 'mc' ? (
              (q.choices || []).map((c, j) => {
                const sel = answers[i] === c
                const isCorrect = graded && norm(c) === norm(q.correct_answer)
                let bg = '#fff', bd = '#ddd'
                if (graded) { if (isCorrect) { bg = '#eafaf0'; bd = '#2eb86a' } else if (sel) { bg = '#fff0f0'; bd = '#e08e8e' } }
                else if (sel) { bg = '#f3f1fe'; bd = '#6c5ce7' }
                return (
                  <button key={j} type="button" disabled={phase === 'graded'}
                    onClick={() => setAnswers({ ...answers, [i]: c })}
                    style={{ display: 'block', width: '100%', textAlign: 'left', marginBottom: 6, padding: '9px 12px',
                      borderRadius: 9, border: `1.5px solid ${bd}`, background: bg,
                      cursor: phase === 'graded' ? 'default' : 'pointer', fontSize: 14 }}>
                    {['①', '②', '③', '④', '⑤'][j] || '·'} <MathText>{c}</MathText>
                  </button>
                )
              })
            ) : (
              <input disabled={phase === 'graded'} value={answers[i] ?? ''}
                onChange={(e) => setAnswers({ ...answers, [i]: e.target.value })}
                placeholder="답을 입력하세요"
                style={{ ...input, marginBottom: 0, fontSize: 14 }} />
            )}
            {graded && (
              <div style={{ fontSize: 12, color: '#666', marginTop: 6 }}>
                정답: <b><MathText>{q.correct_answer}</MathText></b>
                {q.explanation && <> · <MathText>{q.explanation}</MathText></>}
              </div>
            )}
          </div>
        )
      })}

      {phase === 'solving' && questions.length > 0 && (
        <button style={{ ...btn, width: '100%' }} disabled={!allAnswered} onClick={grade}>
          {allAnswered ? '채점하기' : '모든 문제에 답해주세요'}
        </button>
      )}

      {phase === 'graded' && graded && (graded.passed ? (
        <div style={{ textAlign: 'center', padding: '8px 0' }}>
          <div style={{ fontSize: 40 }}>🏆</div>
          <div style={{ fontSize: 18, fontWeight: 800, color: '#1a6b32' }}>미션 통과! ({graded.correctCount}/{graded.total})</div>
          <div style={{ fontSize: 12, color: '#888', marginTop: 4 }}>📨 (실제 서비스에선 부모님께 “통과했어요” 알림이 갑니다)</div>
          {onClose && <button style={{ ...btnGhost, marginTop: 10 }} onClick={onClose}>닫기</button>}
        </div>
      ) : (
        <div style={{ textAlign: 'center', padding: '8px 0' }}>
          <div style={{ fontSize: 36 }}>📘</div>
          <div style={{ fontSize: 16, fontWeight: 800, color: '#6c5ce7' }}>조금만 더! ({graded.correctCount}/{graded.total})</div>
          <div style={{ fontSize: 12, color: '#888', margin: '4px 0 10px' }}>해설을 보고, 비슷한 새 문제로 다시 도전해요.</div>
          <button style={{ ...btn, width: '100%', background: '#6c5ce7' }} onClick={retry}>
            ✨ 비슷한 문제로 다시 도전
          </button>
        </div>
      ))}
    </div>
  )
}

// 학생이 공유 링크(?s=토큰)로 들어왔을 때 보는 전체 화면 (로그인 없음)
function PublicSolve({ token }) {
  return (
    <div style={{ ...panel, width: 460 }}>
      <div style={{ fontSize: 18, fontWeight: 800, color: '#1a1a1a' }}>📚 오늘의 수학 미션</div>
      <div style={{ fontSize: 12, color: '#999', marginBottom: 4 }}>UnoLock · 선생님이 보낸 문제예요</div>
      <Solver token={token} />
      <p style={foot}>UnoLock</p>
    </div>
  )
}

// 로그인 / 가입 폼
function AuthForm() {
  const [mode, setMode] = useState('login') // login | signup
  const [name, setName] = useState('')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')

  const submit = async (e) => {
    e.preventDefault()
    setError(''); setBusy(true)
    try {
      if (mode === 'signup') {
        const { error } = await supabase.auth.signUp({
          email, password,
          options: { data: { full_name: name, role: 'teacher' } },
        })
        if (error) throw error
      } else {
        const { error } = await supabase.auth.signInWithPassword({ email, password })
        if (error) throw error
      }
      // 성공하면 onAuthStateChange 가 화면을 자동으로 바꿉니다.
    } catch (err) {
      setError(translate(err.message))
    } finally {
      setBusy(false)
    }
  }

  return (
    <form style={card} onSubmit={submit}>
      <h1 style={h1}>{mode === 'login' ? '로그인' : '출제자 가입'}</h1>
      <p style={sub}>UnoLock 출제자 대시보드</p>

      {mode === 'signup' && (
        <input style={input} placeholder="이름 (예: 김선생)" value={name}
          onChange={(e) => setName(e.target.value)} />
      )}
      <input style={input} type="email" placeholder="이메일" value={email}
        required onChange={(e) => setEmail(e.target.value)} />
      <input style={input} type="password" placeholder="비밀번호 (6자 이상)" value={password}
        required minLength={6} onChange={(e) => setPassword(e.target.value)} />

      {error && <p style={errBox}>{error}</p>}

      <button style={btn} type="submit" disabled={busy}>
        {busy ? '처리 중…' : mode === 'login' ? '로그인' : '가입하기'}
      </button>

      <button type="button" style={linkBtn}
        onClick={() => { setMode(mode === 'login' ? 'signup' : 'login'); setError('') }}>
        {mode === 'login' ? '계정이 없어요 → 가입하기' : '이미 계정이 있어요 → 로그인'}
      </button>
      <p style={foot}>UnoLock · 출제자 웹</p>
    </form>
  )
}

// 자주 나오는 영어 오류만 한국어로 바꾸고, 모르는 건 원문을 그대로 보여줍니다.
function translate(msg = '') {
  const m = msg.toLowerCase()
  if (m.includes('invalid login')) return '이메일 또는 비밀번호가 맞지 않아요.'
  if (m.includes('already registered') || m.includes('already been registered'))
    return '이미 가입된 이메일이에요. 로그인해 주세요.'
  if (m.includes('signup') && m.includes('disabled'))
    return '가입이 꺼져 있어요. Supabase → Authentication 설정에서 "Allow new users to sign up"을 켜주세요.'
  if (m.includes('signups not allowed'))
    return '가입이 막혀 있어요. Supabase Authentication 설정을 확인해 주세요.'
  if (m.includes('database error'))
    return '가입 중 DB 오류예요(트리거 의심). 원문: ' + msg
  if (m.includes('password'))
    return '비밀번호는 6자 이상이어야 해요.'
  if (m.includes('unable to validate email') || (m.includes('email') && m.includes('invalid')))
    return '이메일 형식을 확인해 주세요.'
  // 모르는 오류는 원문 그대로 (진단용)
  return msg || '알 수 없는 오류예요.'
}

// ---- 간단한 스타일 ----
const Center = ({ children }) => (
  <div style={{
    minHeight: '100vh', display: 'flex', alignItems: 'center', justifyContent: 'center',
    fontFamily: 'Pretendard, system-ui, sans-serif', padding: 24, background: '#f6f7f9',
  }}>{children}</div>
)
const Title = ({ emoji, text, sub }) => (
  <div style={{ textAlign: 'center' }}>
    <div style={{ fontSize: 64 }}>{emoji}</div>
    <h1 style={h1}>{text}</h1>
    {sub && <p style={sub}>{sub}</p>}
  </div>
)
const card = {
  width: 340, background: '#fff', borderRadius: 18, padding: '32px 28px',
  boxShadow: '0 8px 30px rgba(0,0,0,0.08)', display: 'flex', flexDirection: 'column',
}
const h1 = { fontSize: 24, margin: '0 0 4px', textAlign: 'center', color: '#1a1a1a' }
const sub = { fontSize: 13, color: '#888', textAlign: 'center', margin: '0 0 20px' }
const input = {
  width: '100%', boxSizing: 'border-box', padding: '12px 14px', marginBottom: 10,
  border: '1px solid #ddd', borderRadius: 10, fontSize: 15,
}
const btn = {
  marginTop: 6, padding: '13px', border: 'none', borderRadius: 10, fontSize: 15,
  fontWeight: 700, color: '#fff', background: '#2E75B6', cursor: 'pointer',
}
const btnGhost = {
  padding: '11px', border: '1px solid #ddd', borderRadius: 10, fontSize: 14,
  background: '#fff', color: '#555', cursor: 'pointer',
}
const linkBtn = {
  marginTop: 14, border: 'none', background: 'none', color: '#2E75B6',
  fontSize: 13, cursor: 'pointer',
}
const errBox = {
  fontSize: 13, color: '#c0392b', background: '#fff0f0', padding: '9px 12px',
  borderRadius: 8, margin: '4px 0 8px', textAlign: 'center',
}
const foot = { fontSize: 11, color: '#bbb', textAlign: 'center', marginTop: 18 }
const panel = {
  width: 440, maxWidth: '92vw', background: '#fff', borderRadius: 18, padding: '24px 24px',
  boxShadow: '0 8px 30px rgba(0,0,0,0.08)',
}
const h2 = { fontSize: 16, margin: '0 0 10px', color: '#1a1a1a' }
const muted = { fontSize: 13, color: '#999', margin: '0 0 10px' }
const box = {
  border: '1px solid #eee', borderRadius: 12, padding: '12px 14px', marginBottom: 10, background: '#fafbfc',
}
const chip = {
  display: 'inline-block', background: '#eef4fa', color: '#2E75B6', borderRadius: 8,
  padding: '4px 10px', fontSize: 13, marginRight: 6, marginBottom: 6,
}

export default App

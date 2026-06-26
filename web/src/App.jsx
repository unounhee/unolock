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
  const params = new URLSearchParams(window.location.search)
  const shareToken = params.get('s')
  if (shareToken) return <Center><PublicSolve token={shareToken} /></Center>
  // 학부모 통과증 링크(?cert=결과ID)로 들어오면 로그인 없이 통과 결과만 보여준다.
  const certId = params.get('cert')
  if (certId) return <Center><PassCertificate id={certId} /></Center>
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
          <ClassList academyId={a.id} userId={userId} />
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

// 한 학원의 반 목록 + 반 만들기. 각 반마다 "오늘 수업(업로드 묶음)"을 갖는다.
function ClassList({ academyId, userId }) {
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
      {classes.map((c) => (
        <div key={c.id} style={{ ...box, background: '#fff', marginTop: 8 }}>
          <div style={{ fontWeight: 700, marginBottom: 6 }}>📘 {c.name}</div>
          <ClassLesson classId={c.id} academyId={academyId} userId={userId} classLabel={c.name} />
        </div>
      ))}
      {classes.length === 0 && <span style={{ ...muted, fontSize: 12 }}>반 없음 · </span>}
      <form onSubmit={add} style={{ display: 'inline-flex', gap: 6, marginTop: 6 }}>
        <input style={{ ...input, marginBottom: 0, padding: '6px 10px', width: 130, fontSize: 13 }}
          placeholder="반 이름" value={name} onChange={(e) => setName(e.target.value)} />
        <button style={{ ...btnGhost, padding: '6px 12px', fontSize: 13 }} type="submit">+ 반</button>
      </form>
    </div>
  )
}

// 한 반의 "오늘 수업" = 가장 최근 업로드 묶음. 사진 여러 장을 한 번에 올리면 새 묶음이 되고,
// 이전 묶음은 출제에 쓰이지 않는다(무시). AI 출제는 그 묶음의 여러 페이지에서 무작위로 낸다.
function ClassLesson({ classId, academyId, userId, classLabel }) {
  const [batch, setBatch] = useState(null)      // 현재 수업 묶음 { id, created_at }
  const [files, setFiles] = useState([])        // 현재 묶음에 담긴 사진/PDF들
  const [picked, setPicked] = useState([])      // 올리려고 고른 파일들
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState('')
  const [genBusy, setGenBusy] = useState(false)
  const [genErr, setGenErr] = useState('')
  const [quiz, setQuiz] = useState(null)        // { title, questions }
  const [solving, setSolving] = useState(false) // 학생처럼 풀어보기
  const [shareUrl, setShareUrl] = useState('')
  const [results, setResults] = useState(null)  // null=안 봄, []=푼 학생 없음, [..]=학생별 요약
  const [resBusy, setResBusy] = useState(false)
  const [resErr, setResErr] = useState('')

  // 이 반의 "가장 최근 묶음"과 그 안의 파일들을 불러온다.
  const load = async () => {
    const { data: batches } = await supabase.from('lesson_batches')
      .select('id, created_at').eq('class_id', classId)
      .order('created_at', { ascending: false }).limit(1)
    const b = batches?.[0] || null
    setBatch(b)
    if (b) {
      const { data: mats } = await supabase.from('materials')
        .select('id, title, file_type, storage_path').eq('batch_id', b.id).order('created_at')
      setFiles(mats || [])
    } else { setFiles([]) }
  }
  useEffect(() => { load() }, [classId])

  // 여러 장을 한 번에 업로드 → 새 묶음 1개 생성(= 오늘 수업). 이전 묶음은 자동으로 뒤로 밀림.
  const upload = async (e) => {
    e.preventDefault()
    setErr('')
    if (!picked.length) { setErr('사진을 한 장 이상 선택해 주세요.'); return }
    for (const f of picked) {
      const ok = f.type === 'application/pdf' || f.type.startsWith('image/')
      if (!ok) { setErr('이미지(JPG/PNG) 또는 PDF만 올릴 수 있어요.'); return }
    }
    setBusy(true)
    try {
      // 1) 새 수업 묶음 만들기
      const { data: b, error: bErr } = await supabase.from('lesson_batches')
        .insert({ class_id: classId, academy_id: academyId, created_by: userId })
        .select('id').single()
      if (bErr) throw bErr
      // 2) 고른 파일을 모두 올리고 materials 줄에 기록. 경로 첫 폴더는 학원id(=권한 규칙)
      for (const f of picked) {
        const fileType = f.type === 'application/pdf' ? 'pdf' : 'image'
        const safe = f.name.replace(/[^\w.\-]/g, '_')
        const path = `${academyId}/${b.id}/${Date.now()}_${safe}`
        const up = await supabase.storage.from('materials').upload(path, f)
        if (up.error) throw up.error
        const ins = await supabase.from('materials').insert({
          academy_id: academyId, class_id: classId, batch_id: b.id,
          uploaded_by: userId, title: f.name, storage_path: path, file_type: fileType,
        })
        if (ins.error) throw ins.error
      }
      setPicked([]); setQuiz(null)
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

  // AI 출제(미리보기): 현재 묶음을 서버로 보내 문제를 받는다(서버가 페이지를 무작위로 고름).
  const generate = async () => {
    if (!batch) { setGenErr('먼저 사진을 올려 주세요.'); return }
    setGenErr(''); setQuiz(null); setGenBusy(true)
    const { data, error } = await supabase.functions.invoke('generate-questions', {
      body: { batch_id: batch.id },
    })
    setGenBusy(false)
    if (error) {
      let msg = error.message || 'AI 출제에 실패했어요.'
      try { const b = await error.context.json(); if (b?.error) msg = b.error } catch (_) { /* noop */ }
      setGenErr(msg); return
    }
    if (data?.error) { setGenErr(data.error); return }
    setQuiz({ title: data?.title, questions: data?.questions || [] })
  }

  // 학생에게 보낼 링크 — 반당 1개. 이미 있으면 그대로 재사용(링크는 항상 그 반의 최신 수업을 보여줌).
  const share = async () => {
    setGenErr(''); setShareUrl('')
    const { data: existing } = await supabase.from('share_links')
      .select('token').eq('class_id', classId).eq('created_by', userId).limit(1)
    let token = existing?.[0]?.token
    if (!token) {
      token = (crypto.randomUUID?.() || `${Date.now()}-${Math.random()}`).replace(/-/g, '')
      const { error } = await supabase.from('share_links')
        .insert({ token, class_id: classId, created_by: userId, label: classLabel })
      if (error) { setGenErr(error.message); return }
    }
    const url = `${window.location.origin}/?s=${token}`
    try { await navigator.clipboard.writeText(url) } catch (_) { /* noop */ }
    setShareUrl(url)
  }

  // 이 반의 풀이 결과를 학생 이름으로 묶어 보여준다(누가·몇 회 만에·통과 여부). 다시 누르면 닫힘(토글).
  const loadResults = async () => {
    if (results) { setResults(null); return }
    setResErr(''); setResBusy(true)
    try {
      // 이 반에 속한 모든 수업 묶음 → 그 묶음들의 풀이 기록을 가져온다(RLS가 자기 반만 허용).
      const { data: batches } = await supabase.from('lesson_batches').select('id').eq('class_id', classId)
      const ids = (batches || []).map((b) => b.id)
      if (!ids.length) { setResults([]); return }
      const { data: rows, error } = await supabase.from('attempts')
        .select('student_name, attempt_no, passed, score, created_at')
        .in('batch_id', ids).order('created_at', { ascending: true })
      if (error) throw error
      // 학생 이름으로 묶기: 시도 횟수·처음 통과한 회차·최고 점수
      const byName = new Map()
      for (const r of (rows || [])) {
        const name = (r.student_name || '').trim() || '이름없음'
        const g = byName.get(name) || { name, tries: 0, passedAt: null, best: 0 }
        g.tries = Math.max(g.tries, r.attempt_no || 1)
        g.best = Math.max(g.best, r.score || 0)
        if (r.passed && g.passedAt == null) g.passedAt = r.attempt_no || 1
        byName.set(name, g)
      }
      setResults(Array.from(byName.values()))
    } catch (e) {
      setResErr(e.message || '결과를 불러오지 못했어요.')
    } finally {
      setResBusy(false)
    }
  }

  return (
    <div style={{ paddingLeft: 2 }}>
      {/* 현재 수업(묶음) 파일들 */}
      {files.length > 0 ? (
        <div style={{ fontSize: 12, color: '#555', marginBottom: 6 }}>
          <span style={{ fontWeight: 700 }}>오늘 수업 · {files.length}장</span>
          <div style={{ marginTop: 4 }}>
            {files.map((m) => (
              <span key={m.id} style={{ ...chip, marginBottom: 4, background: '#f0f7ee', color: '#3d7a2e', cursor: 'pointer' }}
                onClick={() => open(m)} title="클릭하면 열려요">
                {m.file_type === 'pdf' ? '📄' : '🖼️'} {m.title}
              </span>
            ))}
          </div>
        </div>
      ) : (
        <div style={{ ...muted, fontSize: 12 }}>아직 올린 수업이 없어요. 아래에서 사진을 올려 주세요.</div>
      )}

      {/* 버튼들 */}
      <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap', marginBottom: 8 }}>
        <button type="button" disabled={!batch || genBusy}
          style={{ ...btn, marginTop: 0, padding: '6px 12px', fontSize: 13, background: '#6c5ce7', opacity: (!batch || genBusy) ? 0.5 : 1 }}
          onClick={generate}>
          {genBusy ? 'AI 출제 중…' : '✨ AI 출제'}
        </button>
        <button type="button" disabled={!batch}
          style={{ ...btnGhost, padding: '6px 12px', fontSize: 13, opacity: batch ? 1 : 0.5 }}
          onClick={() => setSolving(true)}>
          ▶ 풀어보기
        </button>
        <button type="button"
          style={{ ...btnGhost, padding: '6px 12px', fontSize: 13 }}
          onClick={share}>
          📨 학생 링크
        </button>
        <button type="button"
          style={{ ...btnGhost, padding: '6px 12px', fontSize: 13, opacity: resBusy ? 0.5 : 1 }}
          disabled={resBusy}
          onClick={loadResults}>
          {resBusy ? '불러오는 중…' : results ? '📊 결과 닫기' : '📊 풀이 결과'}
        </button>
      </div>

      {/* 여러 장 업로드 = 새 수업 */}
      <form onSubmit={upload} style={{ marginTop: 4 }}>
        <div style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
          <input type="file" multiple accept="image/*,application/pdf" style={{ fontSize: 12, flex: 1 }}
            onChange={(e) => setPicked(Array.from(e.target.files || []))} />
          <button style={{ ...btn, marginTop: 0, padding: '8px 14px', fontSize: 13 }} type="submit" disabled={busy}>
            {busy ? '올리는 중…' : picked.length > 1 ? `+ 새 수업 (${picked.length}장)` : '+ 새 수업'}
          </button>
        </div>
        <div style={{ ...muted, fontSize: 11, marginTop: 4 }}>
          여러 장을 한 번에 고르면 한 수업이 됩니다. 새로 올리면 이전 수업은 출제에서 빠져요.
        </div>
      </form>

      {err && <p style={errBox}>{err}</p>}
      {genErr && <p style={errBox}>{genErr}</p>}
      {shareUrl && (
        <div style={{ marginTop: 8, fontSize: 12, background: '#eef7ff', border: '1px solid #cfe6ff', borderRadius: 8, padding: '8px 10px' }}>
          ✅ 이 반 학생에게 보낼 링크가 <b>복사</b>됐어요. 카톡 등에 붙여넣어 보내세요:
          <div style={{ marginTop: 4, wordBreak: 'break-all', color: '#2E75B6' }}>{shareUrl}</div>
          <div style={{ marginTop: 4, color: '#999' }}>※ 링크 하나로 충분해요. 새 수업을 올리면 학생은 같은 링크에서 항상 오늘 수업을 풉니다.</div>
        </div>
      )}
      {resErr && <p style={errBox}>{resErr}</p>}
      {results && !resBusy && (
        <div style={{ marginTop: 8, background: '#fff8ef', border: '1px solid #ffe1bd', borderRadius: 10, padding: '10px 12px' }}>
          <div style={{ fontSize: 13, fontWeight: 700, color: '#b9651a', marginBottom: 8 }}>
            📊 이 반 풀이 결과 · {results.length}명
          </div>
          {results.length === 0 ? (
            <div style={{ ...muted, fontSize: 12 }}>아직 푼 학생이 없어요. 학생 링크를 보내 보세요.</div>
          ) : (
            results.map((g, i) => (
              <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 13, padding: '5px 0', borderTop: i ? '1px solid #f1e3cf' : 'none' }}>
                <span>{g.passedAt ? '🟢' : '🔴'}</span>
                <span style={{ fontWeight: 700, minWidth: 64 }}>{g.name}</span>
                <span style={{ color: '#555' }}>
                  {g.passedAt ? `${g.passedAt}회 만에 통과` : `${g.tries}회 시도 · 아직 통과 못함`}
                </span>
                <span style={{ marginLeft: 'auto', color: '#999', fontSize: 12 }}>최고 {g.best}점</span>
              </div>
            ))
          )}
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
      {solving && batch && <Solver batch={batch} onClose={() => setSolving(false)} />}
    </div>
  )
}

// 학생처럼 풀어보기 — 풀이 → 채점 → 8할 미달 시 비슷한 새 문제 재출제 → 통과
function Solver({ batch, token, studentName, onClose }) {
  const isPublic = !!token
  const [round, setRound] = useState(1)
  const [questions, setQuestions] = useState([])
  const [answers, setAnswers] = useState({})   // 문제번호 → 학생 답
  const [phase, setPhase] = useState('loading') // loading | solving | graded
  const [graded, setGraded] = useState(null)
  const [err, setErr] = useState('')
  const [title, setTitle] = useState('')
  const [certId, setCertId] = useState(null)      // 통과 시 부모님께 보낼 결과ID(서버가 돌려줌)
  const [certCopied, setCertCopied] = useState(false)

  const fetchQuestions = async (prev) => {
    setPhase('loading'); setErr(''); setAnswers({}); setGraded(null)
    const base = isPublic ? { token } : { batch_id: batch.id }
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

    // 학생(공개 링크) 풀이면 결과를 서버에 기록한다. (서버가 정답을 다시 대조해 채점)
    // 출제자 미리보기(batch 기반)는 기록하지 않는다. 기록 실패는 학생 화면을 막지 않는다.
    if (isPublic) {
      const items = questions.map((q, i) => ({
        type: q.type, body: q.body, choices: q.choices,
        correct_answer: q.correct_answer, explanation: q.explanation,
        student_answer: answers[i] ?? '',
      }))
      supabase.functions.invoke('record-attempt', {
        body: { token, student_name: studentName, attempt_no: round, items },
      }).then(({ data }) => { if (data?.attempt_id) setCertId(data.attempt_id) })
        .catch(() => { /* noop */ })
    }
  }

  // 통과 결과를 부모님께 보낼 링크(?cert=결과ID)를 복사한다. (학생 풀이일 때만 certId 가 생김)
  const shareCert = async () => {
    const url = `${window.location.origin}/?cert=${certId}`
    try { await navigator.clipboard.writeText(url) } catch (_) { /* noop */ }
    setCertCopied(true)
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
          {certId ? (
            <div style={{ marginTop: 10 }}>
              <button style={{ ...btn, width: '100%', background: '#1a6b32' }} onClick={shareCert}>
                📩 부모님께 통과 소식 보내기
              </button>
              {certCopied && (
                <div style={{ marginTop: 8, fontSize: 12, background: '#eafaf0', border: '1px solid #bfe6cd',
                  borderRadius: 8, padding: '8px 10px', color: '#1a6b32', textAlign: 'left' }}>
                  ✅ 통과 결과 링크가 <b>복사</b>됐어요. 부모님께 카톡 등으로 붙여넣어 보내세요.
                </div>
              )}
            </div>
          ) : (
            <div style={{ fontSize: 12, color: '#888', marginTop: 4 }}>잘했어요! 🎉</div>
          )}
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
// 먼저 이름을 한 번 입력받고(결과 기록용), 그다음 풀이를 시작한다.
function PublicSolve({ token }) {
  const [name, setName] = useState('')
  const [entered, setEntered] = useState('')

  return (
    <div style={{ ...panel, width: 460 }}>
      <div style={{ fontSize: 18, fontWeight: 800, color: '#1a1a1a' }}>📚 오늘의 수학 미션</div>
      <div style={{ fontSize: 12, color: '#999', marginBottom: 4 }}>UnoLock · 선생님이 보낸 문제예요</div>
      {!entered ? (
        <form onSubmit={(e) => { e.preventDefault(); if (name.trim()) setEntered(name.trim()) }}
          style={{ marginTop: 8 }}>
          <label style={{ fontSize: 13, fontWeight: 700 }}>이름을 입력해 주세요</label>
          <input value={name} onChange={(e) => setName(e.target.value)} maxLength={40}
            placeholder="예: 김유노" autoFocus style={{ ...input, marginTop: 6 }} />
          <button type="submit" disabled={!name.trim()} style={{ ...btn, width: '100%' }}>
            시작하기 ▶
          </button>
        </form>
      ) : (
        <Solver token={token} studentName={entered} />
      )}
      <p style={foot}>UnoLock</p>
    </div>
  )
}

// 학부모가 통과증 링크(?cert=결과ID)로 들어왔을 때 보는 화면 (로그인 없음)
// 공개 함수 pass-cert 가 "이름·점수·회차·통과여부"만 돌려준다(문제/답은 안 보임).
function PassCertificate({ id }) {
  const [data, setData] = useState(null)
  const [err, setErr] = useState('')
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    let alive = true
    supabase.functions.invoke('pass-cert', { body: { cert: id } })
      .then(({ data, error }) => {
        if (!alive) return
        if (error) { setErr('결과를 불러오지 못했어요.'); return }
        if (data?.error) { setErr(data.error); return }
        setData(data)
      })
      .catch(() => { if (alive) setErr('결과를 불러오지 못했어요.') })
      .finally(() => { if (alive) setLoading(false) })
    return () => { alive = false }
  }, [id])

  const name = (data?.student_name || '').trim() || '학생'
  const subject = data?.class_name ? `${data.class_name} 수학 미션` : '오늘의 수학 미션'
  const when = data?.created_at ? new Date(data.created_at).toLocaleDateString('ko-KR') : ''

  return (
    <div style={{ ...panel, width: 420, textAlign: 'center' }}>
      <div style={{ fontSize: 12, color: '#999' }}>UnoLock · 통과 소식</div>
      {loading ? (
        <p style={{ ...muted, padding: 16 }}>⏳ 불러오는 중…</p>
      ) : err ? (
        <p style={errBox}>{err}</p>
      ) : data?.passed ? (
        <div style={{ padding: '10px 0' }}>
          <div style={{ fontSize: 52 }}>🏆</div>
          <div style={{ fontSize: 20, fontWeight: 800, color: '#1a6b32', marginTop: 6 }}>
            {name} 학생, 통과했어요!
          </div>
          <div style={{ fontSize: 15, color: '#333', marginTop: 10, lineHeight: 1.6 }}>
            {subject}을<br />
            <b>{data.attempt_no}번 만에</b> 통과했어요{data.score != null ? <> · <b>{data.score}점</b></> : null}
          </div>
          {when && <div style={{ fontSize: 12, color: '#999', marginTop: 10 }}>{when}</div>}
          <div style={{ marginTop: 14, fontSize: 12, color: '#888' }}>오늘도 잘 해냈어요 🎉</div>
        </div>
      ) : (
        <div style={{ padding: '10px 0' }}>
          <div style={{ fontSize: 44 }}>📘</div>
          <div style={{ fontSize: 16, fontWeight: 800, color: '#6c5ce7', marginTop: 6 }}>
            {name} 학생이 오늘도 열심히 풀었어요
          </div>
          <div style={{ fontSize: 13, color: '#666', marginTop: 8 }}>곧 통과 소식을 전해드릴게요!</div>
        </div>
      )}
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

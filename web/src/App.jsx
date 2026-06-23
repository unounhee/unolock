import { useEffect, useState } from 'react'
import { supabase, hasKeys } from './supabaseClient'

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
  if (!ready) return <Center><Title emoji="⏳" text="확인 중…" /></Center>
  return <Center>{session ? <LoggedIn session={session} /> : <AuthForm />}</Center>
}

// 로그인된 모습 — 이메일·이름·역할과 로그아웃 버튼
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
    <div style={card}>
      <div style={{ fontSize: 56, textAlign: 'center' }}>✅</div>
      <h1 style={h1}>로그인됐어요!</h1>
      <p style={{ ...sub, marginBottom: 18 }}>
        {profile?.full_name && <><b style={{ color: '#222' }}>{profile.full_name}</b> ({roleLabel})<br /></>}
        {session.user.email}
      </p>
      {loaded && !profile && (
        <p style={errBox}>프로필을 못 읽었어요. 권한 규칙(RLS)이 켜졌는지 확인해 주세요.</p>
      )}
      <button style={btnGhost} onClick={() => supabase.auth.signOut()}>로그아웃</button>
      <p style={foot}>UnoLock · 출제자 웹</p>
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

export default App

import { useEffect, useState } from 'react'
import { supabase, hasKeys } from './supabaseClient'

function App() {
  const [status, setStatus] = useState('checking') // checking | missing | connected | badkey | error
  const [detail, setDetail] = useState('')

  useEffect(() => {
    if (!hasKeys) {
      setStatus('missing')
      return
    }
    // 가벼운 시험 요청을 보내 두뇌(Supabase)에 실제로 닿는지 확인합니다.
    // 아직 표(table)가 하나도 없어서 "표 없음" 응답이 오는데, 그건 곧 "연결 성공"이라는 뜻이에요.
    ;(async () => {
      const { error } = await supabase.from('__healthcheck__').select('*').limit(1)
      if (!error) {
        setStatus('connected')
        return
      }
      const msg = (error.message || '').toLowerCase()
      const code = error.code || ''
      const tableMissing =
        msg.includes('does not exist') ||
        msg.includes('not find the table') ||
        code === '42P01' ||
        code === 'PGRST205' ||
        code === 'PGRST116'
      const keyProblem = msg.includes('api key') || msg.includes('jwt') || msg.includes('invalid')

      if (tableMissing) setStatus('connected')
      else if (keyProblem) { setStatus('badkey'); setDetail(error.message) }
      else { setStatus('error'); setDetail(error.message) }
    })()
  }, [])

  const view = {
    checking: { emoji: '⏳', title: '연결 확인 중…', sub: '잠깐만요.' },
    missing: { emoji: '🔌', title: '아직 키가 비어있어요', sub: '.env.local 빈칸에 Supabase 주소와 공개키를 넣어주세요.' },
    connected: { emoji: '✅', title: 'Supabase에 연결됐어요!', sub: '두뇌(Supabase)와 웹이 정상적으로 이어졌습니다.' },
    badkey: { emoji: '⚠️', title: '키가 잘못된 것 같아요', sub: '주소나 공개키를 다시 확인해 주세요.' },
    error: { emoji: '❓', title: '연결 확인 중 문제가 있어요', sub: '아래 메시지를 저에게 알려주세요.' },
  }[status]

  return (
    <div style={{
      minHeight: '100vh', display: 'flex', flexDirection: 'column',
      alignItems: 'center', justifyContent: 'center', gap: 12,
      fontFamily: 'Pretendard, system-ui, sans-serif', textAlign: 'center', padding: 24,
    }}>
      <div style={{ fontSize: 72 }}>{view.emoji}</div>
      <h1 style={{ fontSize: 26, margin: 0 }}>{view.title}</h1>
      <p style={{ fontSize: 15, color: '#888', maxWidth: 420, margin: 0 }}>{view.sub}</p>
      {detail && (
        <pre style={{
          marginTop: 10, fontSize: 12, color: '#c0392b', background: '#fff0f0',
          padding: '10px 14px', borderRadius: 10, maxWidth: 460, whiteSpace: 'pre-wrap',
        }}>{detail}</pre>
      )}
      <p style={{ fontSize: 12, color: '#bbb', marginTop: 16 }}>UnoLock · 출제자 웹 (연결 확인용 임시 화면)</p>
    </div>
  )
}

export default App

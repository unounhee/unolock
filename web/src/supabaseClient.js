import { createClient } from '@supabase/supabase-js'

// .env.local 비밀 파일에서 주소(URL)와 공개 출입증(anon key)을 읽어옵니다.
const url = import.meta.env.VITE_SUPABASE_URL
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

// 두 값이 채워져 있을 때만 진짜 연결을 만듭니다. 비어있으면 null.
export const hasKeys = Boolean(url && anonKey)
export const supabase = hasKeys ? createClient(url, anonKey) : null

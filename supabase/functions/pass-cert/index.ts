// ============================================================
// UnoLock · 통과 알림(간단 버전) — 공개 Edge Function (로그인 불필요)
// 학생이 통과하면 받은 결과ID(attempt_id)를 ?cert=ID 링크로 학부모에게 전달.
// 학부모가 그 링크를 열면 이 함수가 "통과 정보"만 돌려준다(통과증 화면용).
// service_role 로 읽되, "추측 불가능한 결과ID(UUID)"가 있어야만 동작(접근 통제).
// 학생 답·문제 내용은 돌려주지 않는다(이름·점수·회차·통과여부만 = 학부모가 볼 최소 정보).
// ⚠️ 배포 시 "Verify JWT" 를 OFF 로 둘 것(학부모는 로그인 안 함).
// ============================================================
import { createClient } from "npm:@supabase/supabase-js@2"

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
}
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  })

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors })
  try {
    const body = await req.json().catch(() => ({}))
    const cert: string | undefined = body.cert
    if (!cert) return json({ error: "잘못된 링크예요." }, 400)

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    )

    // 결과ID(attempt) 한 줄. 학부모가 볼 최소 정보만 고른다.
    const { data: a } = await admin
      .from("attempts")
      .select("student_name, score, attempt_no, passed, created_at, batch_id")
      .eq("id", cert).single()
    if (!a) return json({ error: "통과 결과를 찾을 수 없어요." }, 404)

    // 어느 반/수업인지(있으면 제목에 사용). 없으면 일반 문구.
    let className: string | null = null
    if ((a as any).batch_id) {
      const { data: b } = await admin
        .from("lesson_batches").select("classes(name)")
        .eq("id", (a as any).batch_id).single()
      className = (b as any)?.classes?.name ?? null
    }

    return json({
      ok: true,
      student_name: (a as any).student_name ?? null,
      score: (a as any).score ?? null,
      attempt_no: (a as any).attempt_no ?? 1,
      passed: !!(a as any).passed,
      class_name: className,
      created_at: (a as any).created_at ?? null,
    })
  } catch (e) {
    return json({ error: (e as Error)?.message ?? String(e) }, 500)
  }
})

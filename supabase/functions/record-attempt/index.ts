// ============================================================
// UnoLock · ⑭ 풀이 결과 저장 — 공개 Edge Function (로그인 불필요)
// 학생이 링크에서 채점을 마치면, 그 결과(문제 + 학생답 + 정답)를 받아
//   서버가 "다시 채점"해서 attempts / questions / answers 표에 기록한다.
//   (브라우저가 보낸 passed 를 믿지 않고, 서버가 정답 대조로 재계산한다.)
// service_role 로 저장하되, "유효한 토큰"이 있어야만 동작(접근 통제).
// ⚠️ 배포 시 "Verify JWT" 를 OFF 로 둘 것(학생은 로그인 안 함).
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

// 채점용 정규화 — 웹의 norm()과 동일(공백 정리 + 소문자). 서버가 정답을 직접 대조한다.
const norm = (s: unknown) =>
  (s ?? "").toString().trim().replace(/\s+/g, " ").toLowerCase()

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors })
  try {
    const body = await req.json().catch(() => ({}))
    const token: string | undefined = body.token
    const studentName: string = (body.student_name ?? "").toString().trim().slice(0, 40)
    const attemptNo: number = Number.isFinite(body.attempt_no) ? Math.max(1, Math.trunc(body.attempt_no)) : 1
    const items = Array.isArray(body.items) ? body.items : []
    if (!token) return json({ error: "잘못된 링크예요." }, 400)
    if (!items.length) return json({ error: "저장할 풀이가 없어요." }, 400)

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    )

    // 1) 토큰 → 반 → 그 반의 가장 최근 수업 묶음(있으면 attempt 를 그 묶음에 연결)
    const { data: link } = await admin
      .from("share_links").select("class_id").eq("token", token).single()
    if (!link) return json({ error: "유효하지 않은 링크예요." }, 404)

    let batchId: string | null = null
    if (link.class_id) {
      const { data: batches } = await admin
        .from("lesson_batches").select("id")
        .eq("class_id", link.class_id).order("created_at", { ascending: false }).limit(1)
      batchId = (batches?.[0] as any)?.id ?? null
    }

    // 2) 서버가 다시 채점(정답 대조) → 믿을 수 있는 점수
    const graded = items.map((q: any) => ({
      ...q,
      is_correct: norm(q.student_answer) !== "" && norm(q.student_answer) === norm(q.correct_answer),
    }))
    const total = graded.length
    const correct = graded.filter((q: any) => q.is_correct).length
    const score = Math.round((correct / total) * 100)
    const passed = score >= 80

    // 3) attempts 한 줄 저장
    const { data: attempt, error: aErr } = await admin
      .from("attempts")
      .insert({
        batch_id: batchId,
        share_token: token,
        student_name: studentName || null,
        attempt_no: attemptNo,
        score,
        passed,
      })
      .select("id").single()
    if (aErr || !attempt) return json({ error: "결과 저장에 실패했어요." }, 500)

    // 4) 각 문제 + 그 문제에 대한 학생 답 저장
    for (let i = 0; i < graded.length; i++) {
      const q = graded[i]
      const { data: qRow } = await admin
        .from("questions")
        .insert({
          attempt_id: attempt.id,
          order_no: i + 1,
          type: q.type === "mc" ? "mc" : "short",
          body: (q.body ?? "").toString(),
          choices: Array.isArray(q.choices) ? q.choices : null,
          correct_answer: (q.correct_answer ?? "").toString(),
          explanation: q.explanation ? q.explanation.toString() : null,
        })
        .select("id").single()
      if (!qRow) continue
      await admin.from("answers").insert({
        question_id: qRow.id,
        attempt_id: attempt.id,
        student_answer: (q.student_answer ?? "").toString(),
        is_correct: q.is_correct,
      })
    }

    return json({ ok: true, attempt_id: attempt.id, score, passed, correct, total })
  } catch (e) {
    return json({ error: (e as Error)?.message ?? String(e) }, 500)
  }
})

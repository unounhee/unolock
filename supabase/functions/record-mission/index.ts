// ============================================================
// UnoLock · S3c-1 — 계정 학생의 미션 결과 저장 (Edge Function)
// 로그인한 학생이 미션 채점을 마치면, 그 결과(문제+학생답+정답)를 받아
//   서버가 "다시 채점"해서 attempts/questions/answers 에 student_id 로 기록한다.
//   (브라우저가 보낸 점수는 믿지 않고 서버가 정답 대조로 재계산.)
// 호출자(학생)는 JWT 로 식별 → attempts.student_id 에 본인 id 저장.
// 저장은 service_role 로(RLS 우회), 단 "그 반의 승인된 학생"인지 먼저 확인.
// ⚠️ 배포 시 "Verify JWT" 는 ON (로그인한 학생만 호출).
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

const norm = (s: unknown) =>
  (s ?? "").toString().trim().replace(/\s+/g, " ").toLowerCase()

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors })
  try {
    const authHeader = req.headers.get("Authorization")
    if (!authHeader) return json({ error: "로그인이 필요해요." }, 401)

    const body = await req.json().catch(() => ({}))
    const batchId: string | undefined = body.batch_id
    const attemptNo: number =
      Number.isFinite(body.attempt_no) ? Math.max(1, Math.trunc(body.attempt_no)) : 1
    const items = Array.isArray(body.items) ? body.items : []
    if (!batchId) return json({ error: "batch_id 가 필요해요." }, 400)
    if (!items.length) return json({ error: "저장할 풀이가 없어요." }, 400)

    // 1) 호출자(학생) 식별 — JWT
    const userClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } },
    )
    const { data: { user } } = await userClient.auth.getUser()
    if (!user) return json({ error: "로그인이 필요해요." }, 401)
    const studentId = user.id

    // 2) service_role 로 저장(RLS 우회). 단, "그 반 승인 학생"인지 확인.
    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    )
    const { data: batch } = await admin
      .from("lesson_batches").select("id, class_id").eq("id", batchId).single()
    if (!batch) return json({ error: "수업을 찾을 수 없어요." }, 404)

    const { data: mem } = await admin
      .from("memberships").select("status")
      .eq("class_id", (batch as any).class_id)
      .eq("student_id", studentId)
      .maybeSingle()
    if (!mem || (mem as any).status !== "approved")
      return json({ error: "이 반의 학생이 아니에요." }, 403)

    // 3) 서버 재채점
    const graded = items.map((q: any) => ({
      ...q,
      is_correct:
        norm(q.student_answer) !== "" &&
        norm(q.student_answer) === norm(q.correct_answer),
    }))
    const total = graded.length
    const correct = graded.filter((q: any) => q.is_correct).length
    const score = Math.round((correct / total) * 100)
    const passed = score >= 80

    // 4) attempts 한 줄(계정 학생 id 로)
    const { data: attempt, error: aErr } = await admin
      .from("attempts")
      .insert({
        batch_id: batchId,
        student_id: studentId,
        attempt_no: attemptNo,
        score,
        passed,
      })
      .select("id").single()
    if (aErr || !attempt) return json({ error: "결과 저장에 실패했어요." }, 500)

    // 5) 문제 + 학생답 저장
    for (let i = 0; i < graded.length; i++) {
      const q = graded[i]
      const { data: qRow } = await admin
        .from("questions")
        .insert({
          attempt_id: (attempt as any).id,
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
        question_id: (qRow as any).id,
        attempt_id: (attempt as any).id,
        student_answer: (q.student_answer ?? "").toString(),
        is_correct: q.is_correct,
      })
    }

    return json({ ok: true, attempt_id: (attempt as any).id, score, passed, correct, total })
  } catch (e) {
    return json({ error: (e as Error)?.message ?? String(e) }, 500)
  }
})

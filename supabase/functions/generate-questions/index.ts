// ============================================================
// UnoLock · AI 출제 (수학) — Supabase Edge Function
// 교재(사진/PDF)를 읽고 Claude(Haiku)가 수학 문제를 생성해 돌려준다.
// 비밀키는 Supabase Secrets의 ANTHROPIC_API_KEY 에서만 읽는다(브라우저 노출 없음).
// ============================================================
import { createClient } from "npm:@supabase/supabase-js@2"
import Anthropic from "npm:@anthropic-ai/sdk"
import { encodeBase64 } from "jsr:@std/encoding@1/base64"

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

// 파일 확장자로 Claude에 보낼 미디어 종류를 정한다.
function mediaTypeFor(path: string): string {
  const p = path.toLowerCase()
  if (p.endsWith(".png")) return "image/png"
  if (p.endsWith(".jpg") || p.endsWith(".jpeg")) return "image/jpeg"
  if (p.endsWith(".webp")) return "image/webp"
  if (p.endsWith(".gif")) return "image/gif"
  if (p.endsWith(".pdf")) return "application/pdf"
  return "image/jpeg"
}

// Claude가 "정확히 이 형식(JSON)"으로만 답하도록 강제하는 스키마.
const SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["questions"],
  properties: {
    questions: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["type", "body", "correct_answer", "explanation"],
        properties: {
          type: { type: "string", enum: ["mc", "short"] }, // mc=객관식, short=주관식
          body: { type: "string" },                         // 문제 본문
          choices: { type: "array", items: { type: "string" } }, // 객관식 보기(주관식은 비움)
          correct_answer: { type: "string" },               // 정답
          explanation: { type: "string" },                  // 해설
        },
      },
    },
  },
}

const PROMPT = `너는 한국 중·고등 수학 출제 선생님이야.
첨부된 교재(이미지 또는 PDF)를 보고, 그 내용에 맞는 수학 문제를 만들어줘.
- 객관식(type:"mc") 3문제 + 주관식(type:"short") 2문제, 총 5문제.
- 객관식은 choices에 보기 4개를 넣고, correct_answer는 정답 보기의 "텍스트"로.
- 주관식은 choices 없이, correct_answer는 정답 값으로.
- 난이도는 교재 수준에 맞춰 너무 어렵지 않게(매일 가볍게 푸는 '리추얼'용).
- explanation에는 풀이를 1~2줄로 쉽게.
- 모든 텍스트는 한국어로.`

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors })
  try {
    const authHeader = req.headers.get("Authorization")
    if (!authHeader) return json({ error: "로그인이 필요해요." }, 401)

    const { material_id } = await req.json().catch(() => ({}))
    if (!material_id) return json({ error: "material_id 가 필요해요." }, 400)

    // 호출한 사용자 권한으로 접근 → RLS 적용(자기 학원 교재만 읽힘)
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } },
    )

    const { data: mat, error: matErr } = await supabase
      .from("materials")
      .select("id, title, storage_path, file_type")
      .eq("id", material_id)
      .single()
    if (matErr || !mat || !mat.storage_path) {
      return json({ error: "교재를 찾을 수 없어요(권한 또는 파일 확인)." }, 403)
    }

    const { data: file, error: dlErr } = await supabase.storage
      .from("materials")
      .download(mat.storage_path)
    if (dlErr || !file) return json({ error: "교재 파일을 불러오지 못했어요." }, 500)

    const base64 = encodeBase64(new Uint8Array(await file.arrayBuffer()))
    const mediaType = mediaTypeFor(mat.storage_path)
    const mediaBlock = mediaType === "application/pdf"
      ? { type: "document", source: { type: "base64", media_type: mediaType, data: base64 } }
      : { type: "image", source: { type: "base64", media_type: mediaType, data: base64 } }

    const anthropic = new Anthropic({ apiKey: Deno.env.get("ANTHROPIC_API_KEY")! })
    const msg = await anthropic.messages.create({
      model: "claude-haiku-4-5", // 기본 저가 모델. 복잡하면 나중에 sonnet으로 라우팅.
      max_tokens: 2000,
      messages: [{ role: "user", content: [mediaBlock as any, { type: "text", text: PROMPT }] }],
      // 정해진 형식(JSON)으로만 답하게 강제
      output_config: { format: { type: "json_schema", schema: SCHEMA } } as any,
    })

    const textBlock: any = msg.content.find((b: any) => b.type === "text")
    const parsed = JSON.parse(textBlock?.text ?? '{"questions":[]}')
    return json({ title: mat.title, questions: parsed.questions ?? [] })
  } catch (e) {
    return json({ error: (e as Error)?.message ?? String(e) }, 500)
  }
})

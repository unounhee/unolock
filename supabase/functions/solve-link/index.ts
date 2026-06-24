// ============================================================
// UnoLock · 학생 공개 풀이 — Supabase Edge Function (로그인 불필요)
// 첫 출제: 링크 토큰 → 그 반의 "현재 수업 묶음" → 무작위 페이지로 Claude 문제 생성.
// 재출제(previous 있음): 직전 문항의 "구조 그대로, 숫자만 바꾼 변형" 생성.
// service_role로 교재를 읽지만, "유효한 토큰"이 있어야만 동작(접근 통제).
// ⚠️ 배포 시 "Verify JWT" 를 OFF 로 둘 것(학생은 로그인 안 함).
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

function mediaTypeFor(path: string): string {
  const p = path.toLowerCase()
  if (p.endsWith(".png")) return "image/png"
  if (p.endsWith(".jpg") || p.endsWith(".jpeg")) return "image/jpeg"
  if (p.endsWith(".webp")) return "image/webp"
  if (p.endsWith(".gif")) return "image/gif"
  if (p.endsWith(".pdf")) return "application/pdf"
  return "image/jpeg"
}

// 묶음의 여러 페이지 중에서 무작위로 최대 2장을 골라 이미지/문서 블록으로 만든다(출제마다 랜덤).
async function buildImageBlocks(client: any, files: { storage_path: string }[]) {
  const shuffled = [...files].sort(() => Math.random() - 0.5)
  const pick = shuffled.slice(0, Math.min(2, shuffled.length))
  const blocks: any[] = []
  for (const f of pick) {
    const { data: file } = await client.storage.from("materials").download(f.storage_path)
    if (!file) continue
    const base64 = encodeBase64(new Uint8Array(await file.arrayBuffer()))
    const mediaType = mediaTypeFor(f.storage_path)
    blocks.push(mediaType === "application/pdf"
      ? { type: "document", source: { type: "base64", media_type: mediaType, data: base64 } }
      : { type: "image", source: { type: "base64", media_type: mediaType, data: base64 } })
  }
  return blocks
}

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
          type: { type: "string", enum: ["mc", "short"] },
          body: { type: "string" },
          choices: { type: "array", items: { type: "string" } },
          correct_answer: { type: "string" },
          explanation: { type: "string" },
        },
      },
    },
  },
}

const PROMPT = `너는 한국 중·고등 수학 출제 선생님이야. 첨부된 교재(이미지/PDF)를 보고 수학 문제를 만들어줘.

[가장 중요한 규칙 — 반드시 지켜]
1. 모든 문제(객관식 포함)는 정답이 "깔끔한 정수 또는 간단한 분수"로 딱 떨어져야 해(예: 4, -3, 3/2).
   답이 무리수·복잡한 식·문자식이 되는 문제는 처음부터 만들지 마.
2. 각 문제를 직접 풀어서 정답이 깔끔한 숫자인지 먼저 확인해. 아니면 그 문제는 버리고 다른 문제로 바꿔서,
   "최종 확정된 5문제만" JSON에 담아. (만들다 바꾸는 과정을 겉으로 드러내지 마.)
3. explanation에는 "최종 문제의 풀이"만 1~2줄로 써. 출제 과정·자기검토·고민·
   '문제를 교체합니다' 같은 혼잣말이나 메타 설명은 절대 쓰지 마.
4. body(문제)·correct_answer(정답)·explanation(해설)은 반드시 같은 하나의 문제에 대해 서로 일치해야 해.
5. 교재가 여러 페이지면, 그 안에서 골고루(어느 한 페이지에 치우치지 말고) 문제를 뽑아.

[형식]
- 객관식(type:"mc") 3문제 + 주관식(type:"short") 2문제, 총 5문제.
- 객관식: choices에 보기 4개, correct_answer는 정답 보기 텍스트와 똑같이.
- 주관식: choices 없이, correct_answer는 공백 없는 숫자 하나(예: "12", "3/2").
- 난이도는 교재 수준에 맞춰 너무 어렵지 않게(매일 가볍게 푸는 '리추얼'용).
- 수식은 LaTeX로 쓰고 인라인 수식은 $...$ 로 감싸. 모든 설명 텍스트는 한국어로.`

const VARIANT = `[재출제 — 숫자만 바꾸기]
아래 '직전 문항'들과 구조·유형·문장 형태를 "완전히 똑같이" 유지하고, 숫자(계수·상수)만 바꿔서 새 5문항을 만들어.
- 같은 순서, 같은 위치에 같은 유형(mc/short)으로 1:1 대응.
- 예: "a+b=3, a-b=7일 때 a의 값?" → "a+b=10, a-b=4일 때 a의 값?" 처럼 숫자만 교체.
- 바뀐 숫자로 다시 풀어서 정답이 여전히 깔끔한 정수/간단한 분수가 되도록 숫자를 신중히 골라.
- 위의 [가장 중요한 규칙]과 [형식]을 그대로 지켜. 교재는 참고하지 말고 아래 직전 문항 구조만 따라.`

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors })
  try {
    const body0 = await req.json().catch(() => ({}))
    const token = body0.token
    const previous = Array.isArray(body0.previous) ? body0.previous : null
    if (!token) return json({ error: "잘못된 링크예요." }, 400)

    // 관리자 권한 클라이언트(RLS 우회). 접근 통제는 "유효한 토큰"으로만.
    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    )

    const { data: link } = await admin
      .from("share_links").select("class_id, material_id").eq("token", token).single()
    if (!link) return json({ error: "유효하지 않은 링크예요." }, 404)

    // 재출제(previous)면 교재 없이 직전 문항의 변형을 만든다. 첫 출제면 그 반 최신 묶음의 사진들로.
    let content: any[]
    let title = "오늘의 수학 미션"
    if (previous && previous.length) {
      content = [{ type: "text", text: PROMPT + "\n\n" + VARIANT + "\n\n직전 문항(JSON):\n" + JSON.stringify(previous) }]
    } else {
      let files: { storage_path: string }[] = []
      if (link.class_id) {
        // 그 반의 "가장 최근 수업 묶음" 하나
        const { data: batches } = await admin
          .from("lesson_batches").select("id, classes(name)")
          .eq("class_id", link.class_id).order("created_at", { ascending: false }).limit(1)
        const b = batches?.[0]
        if (!b) return json({ error: "아직 오늘 수업이 올라오지 않았어요. 선생님께 문의해 주세요." }, 404)
        const cname = (b as any).classes?.name
        if (cname) title = `${cname} · 오늘 수업`
        const { data: mats } = await admin
          .from("materials").select("storage_path").eq("batch_id", (b as any).id).order("created_at")
        files = (mats || []).filter((m: any) => m.storage_path)
      } else if (link.material_id) {
        // 옛 단일 교재 링크 호환
        const { data: m } = await admin
          .from("materials").select("storage_path, title").eq("id", link.material_id).single()
        if (m?.storage_path) { files = [m as any]; title = (m as any).title || title }
      }
      if (!files.length) return json({ error: "교재를 찾을 수 없어요." }, 404)
      const blocks = await buildImageBlocks(admin, files)
      if (!blocks.length) return json({ error: "교재 파일을 불러오지 못했어요." }, 500)
      content = [...blocks, { type: "text", text: PROMPT }]
    }

    const anthropic = new Anthropic({ apiKey: Deno.env.get("ANTHROPIC_API_KEY")! })
    const msg = await anthropic.messages.create({
      model: "claude-sonnet-4-6",
      max_tokens: 3000,
      messages: [{ role: "user", content }],
      output_config: { format: { type: "json_schema", schema: SCHEMA } } as any,
    })

    const textBlock: any = msg.content.find((b: any) => b.type === "text")
    let parsed: any
    try {
      parsed = JSON.parse(textBlock?.text ?? '{"questions":[]}')
    } catch (_) {
      return json({ error: "문제 생성 결과를 읽지 못했어요(형식 오류). 다시 시도해 주세요." }, 502)
    }
    return json({ title, questions: parsed.questions ?? [] })
  } catch (e) {
    return json({ error: (e as Error)?.message ?? String(e) }, 500)
  }
})

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

[정답 형식 — 절대 규칙(어기면 안 됨)]
1. 모든 문제의 정답은 "정확히 떨어지는 단 하나의 값"이어야 한다(정수 또는 간단한 분수. 예: 4, -3, 3/2).
2. 정답이 아래 중 하나라도 되는 문제는 "처음부터 절대 만들지 마". 교재에 그런 문제가 있어도 건너뛰고
   정답이 깔끔하게 떨어지는 다른 문제를 골라:
   - 범위·구간·부등식 (예: 2<x<5, 0<k<3)
   - 조건·경우를 묻는 것 (예: "θ의 조건", "k의 범위를 구하라", "~이 성립할 조건")
   - 각도(θ)·무리수·복잡한 식·문자식(예: 2a+b)이 답이 되는 것
   - 정답이 2개 이상이거나 "모두 고르시오" 형태
   (이런 유형은 답이 한 값으로 안 떨어져 자동 채점이 불가능하다.)
3. 근사·어림 절대 금지. 정답이나 해설에 "근사값", "약", "≈", "대략"이 필요한 문제는 폐기하고
   정확히 떨어지는 다른 문제로 교체해. 틀린 답을 맞는 척 내놓는 것은 최악이다 — 차라리 더 쉬운 문제를 내라.
4. 각 문제를 네가 직접 끝까지 풀어 정답이 "정확한 하나의 정수/분수"인지 검산한 뒤에만 채택해.
   검산에 실패하면 버리고 교체해서, "최종 확정된 5문제만" JSON에 담아(고치는 과정은 드러내지 마).

[그 밖의 규칙]
5. explanation에는 "최종 문제의 풀이"만 1~2줄. 출제 과정·자기검토·'문제를 교체합니다' 같은 혼잣말 금지.
6. body·correct_answer·explanation은 같은 하나의 문제에 대해 서로 일치해야 한다.
7. 교재가 여러 페이지면 골고루(한 페이지에 치우치지 말고) 뽑아.

[형식]
- 객관식(type:"mc") 3문제 + 주관식(type:"short") 2문제, 총 5문제.
- 객관식: choices는 보기 4개이고 "모두 하나의 구체적인 값(정수/분수)"이어야 한다. 범위·조건을 보기로 쓰지 마.
  정답 보기는 정확히 하나뿐이고, correct_answer는 그 보기 텍스트와 글자까지 똑같이.
- 주관식: choices 없이, correct_answer는 공백 없는 숫자 하나(예: "12", "3/2").
- 난이도는 교재 수준에 맞춰 너무 어렵지 않게(매일 가볍게 푸는 '리추얼'용).
- 수식은 LaTeX로 쓰고 인라인 수식은 $...$ 로 감싸. 모든 설명 텍스트는 한국어로.`

const VARIANT = `[재출제 — 숫자만 바꾸기]
아래 '직전 문항'들과 구조·유형·문장 형태를 "완전히 똑같이" 유지하고, 숫자(계수·상수)만 바꿔서 새 5문항을 만들어.
- 같은 순서·같은 위치에 같은 유형(mc/short)으로 1:1 대응.
- 예: "a+b=3, a-b=7일 때 a의 값?" → "a+b=10, a-b=4일 때 a의 값?" 처럼 숫자만 교체.
- ★가장 중요: 숫자를 바꾼 뒤 반드시 "네가 직접 다시 끝까지 풀어" 정답이 여전히 "정확한 하나의 정수/간단한 분수"인지
  검산해. 안 떨어지면 떨어질 때까지 다른 숫자로 바꿔. 어떤 숫자로도 안 떨어지면, 그 문항은 직전 문항의 숫자를
  거의 그대로 두고(정확히 떨어지는 선에서만 살짝 바꿔) 만들어. 근사·범위·조건이 답이 되게는 절대 만들지 마.
- 위 [정답 형식 — 절대 규칙]을 그대로 지켜. 교재는 보지 말고 아래 직전 문항 구조만 따라.`

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

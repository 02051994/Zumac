/**
 * Puerta de entrada autenticada para el análisis Documento → App.
 *
 * Valida empresa, usuario, importación y plan. Enruta al motor ZUMAC o a
 * OpenAI sin exponer secretos al cliente y registra el consumo individual.
 */
import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const allowedMimeTypes = new Set([
  "image/jpeg",
  "image/png",
  "image/webp",
  "application/pdf",
]);

const analysisSchema = {
  type: "object",
  additionalProperties: false,
  required: [
    "document_quality",
    "title",
    "description",
    "document_type",
    "header_row_candidates",
    "recommended_header_row",
    "preview_rows",
    "fields",
    "relationships",
    "warnings",
    "questions_for_user",
  ],
  properties: {
    document_quality: {
      type: "object",
      additionalProperties: false,
      required: ["acceptable", "message", "issues"],
      properties: {
        acceptable: { type: "boolean" },
        message: { type: "string" },
        issues: { type: "array", items: { type: "string" } },
      },
    },
    title: { type: "string" },
    description: { type: "string" },
    document_type: {
      type: "string",
      enum: ["FORMATO", "TABLA", "LISTA", "DESCONOCIDO"],
    },
    header_row_candidates: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["row", "confidence", "reason"],
        properties: {
          row: { type: "integer", minimum: 1 },
          confidence: { type: "number", minimum: 0, maximum: 1 },
          reason: { type: "string" },
        },
      },
    },
    recommended_header_row: { type: "integer", minimum: 1 },
    preview_rows: {
      type: "array",
      maxItems: 25,
      items: {
        type: "array",
        maxItems: 40,
        items: { type: "string" },
      },
    },
    fields: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: [
          "original_label",
          "suggested_label",
          "column_index",
          "table_name",
          "section",
          "ui_type",
          "required",
          "confidence",
          "options",
          "notes",
        ],
        properties: {
          original_label: { type: "string" },
          suggested_label: { type: "string" },
          column_index: { type: "integer", minimum: 0 },
          table_name: { type: "string" },
          section: { type: "string" },
          ui_type: {
            type: "string",
            enum: [
              "text",
              "multiline",
              "number",
              "integer",
              "date",
              "time",
              "datetime",
              "checkbox",
              "switch",
              "dropdown",
              "multiselect",
              "photo",
              "signature",
              "qr_scan",
              "barcode_scan",
              "email",
              "phone",
              "url",
              "percent",
            ],
          },
          required: { type: "boolean" },
          confidence: { type: "number", minimum: 0, maximum: 1 },
          options: { type: "array", items: { type: "string" } },
          notes: { type: "string" },
        },
      },
    },
    relationships: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["from", "to", "type", "reason"],
        properties: {
          from: { type: "string" },
          to: { type: "string" },
          type: { type: "string" },
          reason: { type: "string" },
        },
      },
    },
    warnings: { type: "array", items: { type: "string" } },
    questions_for_user: { type: "array", items: { type: "string" } },
  },
};

function json(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function record(value: unknown): Record<string, unknown> {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    return value as Record<string, unknown>;
  }
  return {};
}

function integer(value: unknown): number {
  const parsed = Number(value ?? 0);
  return Number.isFinite(parsed) && parsed > 0 ? Math.floor(parsed) : 0;
}

function outputText(payload: Record<string, unknown>): string | null {
  if (typeof payload.output_text === "string") return payload.output_text;
  if (!Array.isArray(payload.output)) return null;
  for (const item of payload.output) {
    const content = record(item).content;
    if (!Array.isArray(content)) continue;
    for (const part of content) {
      const typed = record(part);
      if (typed.type === "output_text" && typeof typed.text === "string") {
        return typed.text;
      }
    }
  }
  return null;
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return json(405, { error: "Método no permitido." });
  }

  const authorization = request.headers.get("Authorization");
  if (!authorization) return json(401, { error: "Sesión requerida." });

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
  if (!supabaseUrl || !supabaseAnonKey) {
    return json(503, {
      error: "El analizador todavía no está configurado por el administrador.",
    });
  }

  const supabase = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authorization } },
  });
  const { data: { user }, error: userError } = await supabase.auth.getUser();
  if (userError || !user) return json(401, { error: "Sesión inválida." });

  const { data: productValue, error: productError } = await supabase.rpc(
    "appgt_contexto_producto_v1",
  );
  if (productError) {
    return json(503, {
      code: "PRODUCT_CONTEXT_UNAVAILABLE",
      error: "No se pudo verificar la autorización de la empresa.",
    });
  }
  const product = record(productValue);
  if (product.zumac_creator_habilitado !== true) {
    return json(403, {
      code: "CREATOR_DISABLED",
      error: "Zumac Creator no está habilitado para esta empresa.",
    });
  }

  let input: Record<string, unknown>;
  try {
    input = await request.json();
  } catch (_) {
    return json(400, { error: "Solicitud inválida." });
  }
  const fileName = String(input.file_name ?? "documento").trim();
  const mimeType = String(input.mime_type ?? "").toLowerCase().trim();
  const fileBase64 = String(input.file_base64 ?? "").trim();
  const importId = String(input.import_id ?? "").trim();
  const engine = String(input.engine ?? "ZUMAC").trim().toUpperCase();
  if (engine !== "ZUMAC" && engine !== "OPENAI") {
    return json(400, {
      error: "Seleccione ZUMAC u OPENAI como motor de análisis.",
    });
  }
  if (!allowedMimeTypes.has(mimeType)) {
    return json(415, { error: "Use JPG, PNG, WEBP o PDF." });
  }
  if (!fileBase64) return json(400, { error: "El archivo está vacío." });
  const estimatedBytes = Math.floor(fileBase64.length * 0.75);
  if (estimatedBytes > 18 * 1024 * 1024) {
    return json(413, { error: "El archivo supera el máximo de 18 MB." });
  }

  if (engine === "ZUMAC") {
    const engineUrl = Deno.env.get("ZUMAC_AI_ENGINE_URL")?.replace(/\/$/, "");
    const engineSecret = Deno.env.get("ZUMAC_AI_ENGINE_SHARED_SECRET");
    if (!engineUrl || !engineSecret) {
      return json(503, {
        code: "ZUMAC_ENGINE_NOT_CONFIGURED",
        error: "Zumac AI Engine gratuito todavía no está desplegado por el administrador.",
      });
    }

    let localResponse: Response;
    try {
      localResponse = await fetch(engineUrl + "/v1/document/analyze", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Zumac-Engine-Secret": engineSecret,
        },
        body: JSON.stringify({
          file_name: fileName,
          mime_type: mimeType,
          file_base64: fileBase64,
          import_id: importId || null,
        }),
      });
    } catch (_) {
      return json(502, {
        code: "ZUMAC_ENGINE_UNAVAILABLE",
        error: "Zumac AI Engine no está disponible. Intenta nuevamente o comunica el incidente al administrador.",
      });
    }
    const localRaw = await localResponse.json().catch(() => ({})) as Record<string, unknown>;
    if (!localResponse.ok) {
      return json(localResponse.status >= 500 ? 502 : localResponse.status, {
        code: "ZUMAC_ENGINE_ERROR",
        error: String(
          localRaw.detail ?? localRaw.error ??
            "El motor propio no pudo analizar el documento.",
        ),
      });
    }
    return json(200, {
      analysis: record(localRaw.analysis),
      model: String(localRaw.model ?? "zumac-document-engine-v1"),
      engine: "ZUMAC",
      request_id: localRaw.request_id ?? null,
      usage: record(localRaw.usage),
      credits: { consumed: 0, remaining: null },
    });
  }

  if (product.ia_avanzada_habilitada !== true) {
    return json(403, {
      code: "AI_ADVANCED_DISABLED",
      error: "La IA avanzada no está habilitada para esta empresa.",
    });
  }
  const { data: preflightValue, error: preflightError } = await supabase.rpc(
    "appgt_preautorizar_consumo_ia_v1",
    { p_importacion_id: importId || null },
  );
  if (preflightError) {
    return json(503, {
      code: "AI_CREDIT_CHECK_FAILED",
      error: "No se pudo verificar el saldo de IA avanzada.",
    });
  }
  const preflight = record(preflightValue);
  if (preflight.autorizado !== true) {
    const code = String(preflight.codigo ?? "AI_PLAN_REQUIRED");
    const paymentRequired =
      code === "AI_CREDITS_EXHAUSTED" || code === "AI_PLAN_REQUIRED";
    return json(paymentRequired ? 402 : 403, {
      code,
      error: String(
        preflight.mensaje ?? "Necesitas un plan de IA avanzada.",
      ),
    });
  }

  const openAiKey = Deno.env.get("OPENAI_API_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!openAiKey || !serviceRoleKey) {
    return json(503, {
      code: "OPENAI_NOT_CONFIGURED",
      error: "La IA avanzada todavía no está configurada por el administrador.",
    });
  }

  const dataUrl = "data:" + mimeType + ";base64," + fileBase64;
  const media = mimeType === "application/pdf"
    ? {
      type: "input_file",
      filename: fileName,
      file_data: dataUrl,
      detail: "high",
    }
    : { type: "input_image", image_url: dataUrl, detail: "original" };
  const model = Deno.env.get("OPENAI_DOCUMENT_MODEL") ?? "gpt-5.6-sol";
  const systemPrompt = [
    "Eres el analizador documental avanzado de Zumac Creator, especializado en agroexportación.",
    "Tu trabajo es transcribir y estructurar un registro real para convertirlo después en una app editable.",
    "",
    "Reglas obligatorias:",
    "1. Primero evalúa si el documento es legible: enfoque, resolución útil, contraste, sombras, cortes y texto pequeño. Si no puedes leer con seguridad, document_quality.acceptable debe ser false. No inventes texto ilegible.",
    "2. Conserva una vista fiel de hasta 25 filas y 40 columnas en preview_rows. Los números de fila son base 1; column_index es base 0.",
    "3. Identifica candidatos a fila de encabezados y recomienda uno. Puede haber títulos antes del encabezado.",
    "4. Para cada campo conserva original_label y propone suggested_label corregido. Corrige errores evidentes de OCR, pero baja confidence y pregunta cuando exista ambigüedad.",
    "5. Infiere tipos de interfaz sólo con evidencia del documento. Una columna con catálogo visible puede ser dropdown e incluir options.",
    "6. Agrupa campos por table_name y section. Sugiere relaciones entre tablas o conceptos sólo cuando sean justificables.",
    "7. Toda salida es una sugerencia GENERADA_IA: el usuario decidirá nombres, fila de encabezados, campos y diseño antes de crear un borrador.",
    "8. Responde exclusivamente con el JSON solicitado y en español.",
  ].join("\n");

  const openAiResponse = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      Authorization: "Bearer " + openAiKey,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model,
      input: [
        {
          role: "system",
          content: [{ type: "input_text", text: systemPrompt }],
        },
        {
          role: "user",
          content: [
            {
              type: "input_text",
              text: "Analiza el archivo " + fileName +
                ". La sesión de importación es " + importId + ".",
            },
            media,
          ],
        },
      ],
      text: {
        format: {
          type: "json_schema",
          name: "zumac_creator_document_analysis",
          strict: true,
          schema: analysisSchema,
        },
      },
    }),
  });

  const raw = await openAiResponse.json() as Record<string, unknown>;
  if (!openAiResponse.ok) {
    const apiError = record(raw.error);
    return json(openAiResponse.status >= 500 ? 502 : 422, {
      error: String(
        apiError.message ?? "No fue posible analizar el documento.",
      ),
    });
  }
  const text = outputText(raw);
  if (!text) {
    return json(502, { error: "La IA no devolvió una estructura." });
  }

  let analysis: Record<string, unknown>;
  try {
    analysis = JSON.parse(text);
  } catch (_) {
    return json(502, {
      error: "La respuesta estructurada no pudo interpretarse.",
    });
  }

  const usage = record(raw.usage);
  const inputDetails = record(usage.input_tokens_details);
  const inputTokens = integer(usage.input_tokens);
  const cachedInputTokens = integer(inputDetails.cached_tokens);
  const outputTokens = integer(usage.output_tokens);
  const requestId = String(raw.id ?? crypto.randomUUID());
  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: chargeValue, error: chargeError } = await admin.rpc(
    "appgt_registrar_consumo_ia_v1",
    {
      p_empresa_id: String(product.empresa_id ?? ""),
      p_user_id: user.id,
      p_importacion_id: importId || null,
      p_proveedor: "OPENAI",
      p_modelo: model,
      p_request_id: requestId,
      p_input_tokens: inputTokens,
      p_cached_input_tokens: cachedInputTokens,
      p_output_tokens: outputTokens,
      p_metadata: { endpoint: "responses", feature: "CREATOR_DOCUMENT" },
    },
  );
  if (chargeError) {
    console.error("No se pudo registrar el consumo de IA", chargeError);
    return json(502, {
      code: "AI_USAGE_NOT_RECORDED",
      error: "El análisis terminó, pero no pudo registrarse su consumo. El administrador debe revisar el incidente.",
    });
  }
  const charge = record(chargeValue);
  return json(200, {
    analysis,
    model,
    engine: "OPENAI",
    request_id: requestId,
    usage: {
      input_tokens: inputTokens,
      cached_input_tokens: cachedInputTokens,
      output_tokens: outputTokens,
      credits_consumed: charge.creditos_consumidos ?? 0,
    },
    credits: {
      consumed: charge.creditos_consumidos ?? 0,
      remaining: charge.creditos_restantes ?? 0,
      exhausted: charge.agotado === true,
    },
  });
});

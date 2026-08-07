"""API HTTP del motor documental gratuito de Zumac Creator.

El servicio valida tamaño y legibilidad, ejecuta OCR sobre imágenes o PDF y
devuelve una propuesta estructurada. No publica formatos y no almacena el
archivo original; la autorización entre Supabase y el motor usa un secreto
compartido enviado en ``X-Zumac-Engine-Secret``.
"""

from __future__ import annotations

import base64
import io
import os
import re
import statistics
import unicodedata
from pathlib import Path
from typing import Any

import cv2
import fitz
import numpy as np
import pytesseract
from fastapi import FastAPI, Header, HTTPException
from PIL import Image
from pydantic import BaseModel, Field
from pytesseract import Output


app = FastAPI(
    title="Zumac AI Engine",
    version="1.0.0",
    description="Motor propio y autocontenido para convertir documentos en propuestas de app.",
)

ALLOWED_MIME_TYPES = {
    "image/jpeg",
    "image/png",
    "image/webp",
    "application/pdf",
}
MAX_FILE_BYTES = 18 * 1024 * 1024
ENGINE_MODEL = "zumac-document-engine-v1"


class AnalyzeRequest(BaseModel):
    file_name: str = "documento"
    mime_type: str
    file_base64: str
    import_id: str | None = None


class AnalyzeResponse(BaseModel):
    analysis: dict[str, Any]
    model: str = ENGINE_MODEL
    engine: str = "ZUMAC"
    usage: dict[str, int] = Field(
        default_factory=lambda: {
            "input_tokens": 0,
            "cached_input_tokens": 0,
            "output_tokens": 0,
            "credits_consumed": 0,
        }
    )


def _require_secret(value: str | None) -> None:
    expected = os.getenv("ZUMAC_AI_ENGINE_SHARED_SECRET", "").strip()
    if not expected:
        raise HTTPException(503, "El secreto interno de Zumac AI Engine no está configurado.")
    if value != expected:
        raise HTTPException(401, "Credencial interna inválida.")


def _decode_file(raw: str) -> bytes:
    clean = raw.split(",", 1)[-1].strip()
    try:
        payload = base64.b64decode(clean, validate=True)
    except Exception as exc:
        raise HTTPException(400, "El archivo no contiene base64 válido.") from exc
    if not payload:
        raise HTTPException(400, "El archivo está vacío.")
    if len(payload) > MAX_FILE_BYTES:
        raise HTTPException(413, "El archivo supera el máximo de 18 MB.")
    return payload


def _normalize(value: str) -> str:
    value = unicodedata.normalize("NFD", value or "")
    value = "".join(char for char in value if unicodedata.category(char) != "Mn")
    return re.sub(r"\s+", " ", value).strip()


def _clean_cell(value: str) -> str:
    value = value.replace("|", " ").replace("\u00ad", "")
    return re.sub(r"\s+", " ", value).strip(" -_:;,.\t")


def _row_from_positioned_words(words: list[dict[str, Any]]) -> list[list[str]]:
    if not words:
        return []
    words.sort(key=lambda item: (item["y"], item["x"]))
    heights = [max(1, int(item["h"])) for item in words]
    y_tolerance = max(8.0, statistics.median(heights) * 0.7)
    grouped: list[list[dict[str, Any]]] = []
    centers: list[float] = []
    for word in words:
        center = word["y"] + word["h"] / 2
        nearest = min(
            range(len(centers)),
            key=lambda index: abs(centers[index] - center),
            default=-1,
        )
        if nearest >= 0 and abs(centers[nearest] - center) <= y_tolerance:
            grouped[nearest].append(word)
            centers[nearest] = statistics.mean(
                item["y"] + item["h"] / 2 for item in grouped[nearest]
            )
        else:
            grouped.append([word])
            centers.append(center)

    ordered = [row for _, row in sorted(zip(centers, grouped), key=lambda item: item[0])]
    output: list[list[str]] = []
    for row in ordered:
        row.sort(key=lambda item: item["x"])
        widths_per_character = [
            item["w"] / max(len(item["text"]), 1) for item in row if item["text"]
        ]
        typical_character = statistics.median(widths_per_character or [7.0])
        gap_threshold = max(24.0, typical_character * 3.4)
        cells: list[str] = []
        current: list[str] = []
        right_edge: float | None = None
        for word in row:
            if right_edge is not None and word["x"] - right_edge > gap_threshold:
                cell = _clean_cell(" ".join(current))
                if cell:
                    cells.append(cell)
                current = []
            current.append(word["text"])
            right_edge = word["x"] + word["w"]
        cell = _clean_cell(" ".join(current))
        if cell:
            cells.append(cell)
        if cells:
            output.append(cells)
    return output[:25]


def _ocr_image(image: Image.Image) -> tuple[list[list[str]], dict[str, float], int]:
    rgb = np.array(image.convert("RGB"))
    gray = cv2.cvtColor(rgb, cv2.COLOR_RGB2GRAY)
    blur_score = float(cv2.Laplacian(gray, cv2.CV_64F).var())
    brightness = float(gray.mean())
    contrast = float(gray.std())
    data = pytesseract.image_to_data(
        image,
        lang="spa+eng",
        config="--oem 1 --psm 6",
        output_type=Output.DICT,
    )
    words: list[dict[str, Any]] = []
    for index, raw_text in enumerate(data.get("text", [])):
        text = _clean_cell(str(raw_text))
        try:
            confidence = float(data["conf"][index])
        except (TypeError, ValueError):
            confidence = -1
        if not text or confidence < 20:
            continue
        words.append(
            {
                "text": text,
                "x": int(data["left"][index]),
                "y": int(data["top"][index]),
                "w": int(data["width"][index]),
                "h": int(data["height"][index]),
            }
        )
    return (
        _row_from_positioned_words(words),
        {
            "ancho": float(image.width),
            "alto": float(image.height),
            "nitidez": blur_score,
            "brillo": brightness,
            "contraste": contrast,
        },
        len(words),
    )


def _pdf_rows(payload: bytes) -> tuple[list[list[str]], dict[str, float], int]:
    document = fitz.open(stream=payload, filetype="pdf")
    if document.page_count == 0:
        return [], {"paginas": 0.0}, 0
    all_rows: list[list[str]] = []
    word_count = 0
    first_metrics: dict[str, float] = {"paginas": float(document.page_count)}
    for page_index in range(min(document.page_count, 3)):
        page = document[page_index]
        positioned = []
        for item in page.get_text("words"):
            text = _clean_cell(str(item[4]))
            if not text:
                continue
            positioned.append(
                {
                    "text": text,
                    "x": float(item[0]),
                    "y": float(item[1]),
                    "w": float(item[2] - item[0]),
                    "h": float(item[3] - item[1]),
                }
            )
        if positioned:
            rows = _row_from_positioned_words(positioned)
            word_count += len(positioned)
        else:
            pixmap = page.get_pixmap(matrix=fitz.Matrix(2, 2), alpha=False)
            image = Image.open(io.BytesIO(pixmap.tobytes("png")))
            rows, metrics, words = _ocr_image(image)
            word_count += words
            if page_index == 0:
                first_metrics.update(metrics)
        all_rows.extend(rows)
        if len(all_rows) >= 25:
            break
    document.close()
    return all_rows[:25], first_metrics, word_count


def _header_candidates(rows: list[list[str]]) -> list[dict[str, Any]]:
    candidates = []
    for index, row in enumerate(rows[:12]):
        non_empty = [cell for cell in row if cell]
        if not non_empty:
            continue
        alpha = sum(bool(re.search(r"[A-Za-zÀ-ÿ]", cell)) for cell in non_empty)
        unique = len({_normalize(cell).upper() for cell in non_empty}) / len(non_empty)
        width_bonus = min(len(non_empty) / 6.0, 1.0)
        next_consistency = 0.0
        if index + 1 < len(rows):
            next_consistency = 1.0 - min(abs(len(rows[index + 1]) - len(row)) / max(len(row), 1), 1.0)
        score = min(
            0.99,
            0.20 + 0.30 * (alpha / len(non_empty)) + 0.20 * unique
            + 0.20 * width_bonus + 0.10 * next_consistency,
        )
        if len(non_empty) == 1 and len(rows) > 1:
            score -= 0.22
        candidates.append(
            {
                "row": index + 1,
                "confidence": round(max(0.05, score), 3),
                "reason": f"Contiene {len(non_empty)} encabezados legibles y una estructura comparable con las filas cercanas.",
            }
        )
    return sorted(candidates, key=lambda item: item["confidence"], reverse=True)[:4]


def _suggest_label(value: str, column: int) -> str:
    clean = _clean_cell(value)
    clean = re.sub(r"^[^A-Za-z0-9À-ÿ]+|[^A-Za-z0-9À-ÿ%]+$", "", clean)
    if not clean:
        return f"Campo {column + 1}"
    words = clean.lower().split()
    preserved = {"ph": "pH", "ce": "CE", "dni": "DNI", "qr": "QR", "id": "ID", "gps": "GPS"}
    return " ".join(preserved.get(word, word.capitalize()) for word in words)


def _ui_type(label: str, samples: list[str]) -> tuple[str, list[str]]:
    normalized = _normalize(label).upper()
    values = [value.strip() for value in samples if value.strip()]
    if re.search(r"FOTO|IMAGEN|EVIDENCIA", normalized):
        return "photo", []
    if re.search(r"FIRMA", normalized):
        return "signature", []
    if re.search(r"CODIGO QR|\bQR\b", normalized):
        return "qr_scan", []
    if re.search(r"BARRAS", normalized):
        return "barcode_scan", []
    if re.search(r"CORREO|EMAIL", normalized):
        return "email", []
    if re.search(r"TELEFONO|CELULAR", normalized):
        return "phone", []
    if re.search(r"FECHA.*HORA|HORA.*FECHA", normalized):
        return "datetime", []
    if re.search(r"FECHA|DIA", normalized):
        return "date", []
    if re.search(r"HORA", normalized):
        return "time", []
    if re.search(r"PORCENTAJE|%", normalized):
        return "percent", []
    if re.search(r"CANTIDAD|PESO|VOLUMEN|DOSIS|PH|CONDUCTIVIDAD|\bCE\b|DRENAJE", normalized):
        return "number", []
    if re.search(r"NUMERO|NRO|TOTAL", normalized):
        return "integer", []
    unique_values = list(dict.fromkeys(values))
    if 1 < len(unique_values) <= 8 and len(values) >= 2:
        return "dropdown", unique_values
    if re.search(r"OBSERVACION|COMENTARIO|DESCRIPCION|DETALLE", normalized):
        return "multiline", []
    return "text", []


def _relationships(labels: list[str]) -> list[dict[str, str]]:
    concepts = {_normalize(label).upper(): label for label in labels}
    agro_graph = {
        "DRENAJE": ["PH", "CE", "FERTIRRIEGO", "RIEGO", "VARIEDAD", "SECTOR", "MACETA"],
        "RIEGO": ["FERTIRRIEGO", "PH", "CE", "DRENAJE", "CALIDAD DEL AGUA"],
        "FERTIRRIEGO": ["RIEGO", "PH", "CE", "DOSIS", "FERTILIZANTE"],
        "PLAGA": ["CULTIVO", "LOTE", "VARIEDAD", "EVALUACION", "APLICACION"],
        "COSECHA": ["LOTE", "VARIEDAD", "CALIDAD", "TRAZABILIDAD", "RENDIMIENTO"],
    }
    output: list[dict[str, str]] = []
    for source_key, targets in agro_graph.items():
        source = next((label for key, label in concepts.items() if source_key in key), None)
        if not source:
            continue
        for target_key in targets:
            target = next((label for key, label in concepts.items() if target_key in key), None)
            if target and target != source:
                output.append(
                    {
                        "from": source,
                        "to": target,
                        "type": "RELACIONADO_CON",
                        "reason": "Relación operativa detectada entre campos del mismo registro agroexportador.",
                    }
                )
    return output[:20]


def _analysis(file_name: str, mime_type: str, payload: bytes) -> dict[str, Any]:
    metrics: dict[str, float]
    if mime_type == "application/pdf":
        rows, metrics, word_count = _pdf_rows(payload)
        acceptable = bool(rows and word_count >= 4)
        issues = [] if acceptable else ["El PDF no contiene texto o imágenes suficientemente legibles."]
    else:
        try:
            image = Image.open(io.BytesIO(payload))
            image.verify()
            image = Image.open(io.BytesIO(payload)).convert("RGB")
        except Exception as exc:
            raise HTTPException(400, "La imagen no pudo interpretarse.") from exc
        rows, metrics, word_count = _ocr_image(image)
        issues = []
        if min(image.width, image.height) < 720:
            issues.append("La resolución es demasiado baja para leer el registro con seguridad.")
        if metrics["nitidez"] < 45:
            issues.append("La imagen no es nítida; toma o sube otra fotografía.")
        if metrics["brillo"] < 45 or metrics["brillo"] > 235:
            issues.append("La iluminación no permite distinguir correctamente el texto.")
        if word_count < 4:
            issues.append("No se detectó suficiente texto legible.")
        acceptable = not issues

    candidates = _header_candidates(rows)
    header_row = candidates[0]["row"] if candidates else 1
    header = rows[header_row - 1] if rows and header_row <= len(rows) else []
    title_rows = rows[: max(0, header_row - 1)]
    detected_title = next((" ".join(row) for row in title_rows if row), "")
    title = detected_title or _suggest_label(Path(file_name).stem.replace("_", " "), 0)
    fields = []
    labels = []
    for column, original in enumerate(header):
        label = _suggest_label(original, column)
        samples = [row[column] for row in rows[header_row:] if column < len(row)]
        ui_type, options = _ui_type(label, samples)
        labels.append(label)
        fields.append(
            {
                "original_label": original,
                "suggested_label": label,
                "column_index": column,
                "table_name": title,
                "section": "Datos generales",
                "ui_type": ui_type,
                "required": False,
                "confidence": 0.86 if original == label else 0.74,
                "options": options,
                "notes": "Sugerencia del motor propio; debe ser confirmada por el usuario.",
            }
        )

    if acceptable and not fields:
        acceptable = False
        issues.append("No se pudo identificar una fila de encabezados con campos utilizables.")

    questions = []
    if candidates:
        questions.append(f"¿La fila {header_row} contiene los encabezados correctos?")
    questions.append("¿Los nombres y tipos de campo propuestos son correctos?")
    warnings = [
        "El resultado fue generado por Zumac AI Engine y no modifica datos hasta que el usuario lo apruebe."
    ]
    return {
        "document_quality": {
            "acceptable": acceptable,
            "message": "El documento es legible." if acceptable else "La imagen no es nítida o no contiene suficiente información legible; sube otra.",
            "issues": issues,
        },
        "title": title,
        "description": f"Formato propuesto a partir de {file_name} mediante Zumac AI Engine.",
        "document_type": "TABLA" if len(header) > 1 else "FORMATO",
        "header_row_candidates": candidates,
        "recommended_header_row": header_row,
        "preview_rows": rows,
        "fields": fields,
        "relationships": _relationships(labels),
        "warnings": warnings,
        "questions_for_user": questions,
    }


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "engine": ENGINE_MODEL}


@app.post("/v1/document/analyze", response_model=AnalyzeResponse)
def analyze_document(
    request: AnalyzeRequest,
    x_zumac_engine_secret: str | None = Header(default=None),
) -> AnalyzeResponse:
    _require_secret(x_zumac_engine_secret)
    mime_type = request.mime_type.lower().strip()
    if mime_type not in ALLOWED_MIME_TYPES:
        raise HTTPException(415, "Use JPG, PNG, WEBP o PDF.")
    payload = _decode_file(request.file_base64)
    return AnalyzeResponse(
        analysis=_analysis(request.file_name.strip() or "documento", mime_type, payload)
    )

import asyncio
import json
from pathlib import Path
from typing import Any

from google import genai
from google.genai import types
from pydantic import BaseModel

from app.config import GEMINI_MODEL, GOOGLE_API_KEY, PRICE_INPUT_PER_M, PRICE_OUTPUT_PER_M
from app.prompts import PROMPTS
from app.schemas import (
    BankStatement,
    DocumentType,
    IdentityDocument,
    MemorandumOfAssociation,
    UsageInfo,
)

client = genai.Client(api_key=GOOGLE_API_KEY)

SCHEMA_MAP: dict[DocumentType, type[BaseModel]] = {
    DocumentType.PASSPORT: IdentityDocument,
    DocumentType.DRIVING_LICENCE: IdentityDocument,
    DocumentType.NATIONAL_ID: IdentityDocument,
    DocumentType.VISA: IdentityDocument,
    DocumentType.BANK_STATEMENT: BankStatement,
    DocumentType.MEMORANDUM: MemorandumOfAssociation,
}

_DEFAULT_CUSTOM_PROMPT = (
    "Extract all relevant data from this document according to the provided schema. "
    "Use null for fields not found. Dates in YYYY-MM-DD format."
)

_MIME_TYPES: dict[str, str] = {
    ".pdf": "application/pdf",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".png": "image/png",
    ".webp": "image/webp",
    ".heic": "image/heic",
    ".tiff": "image/tiff",
    ".tif": "image/tiff",
}


def detect_mime_type(filename: str, content_type: str | None) -> str:
    ext = Path(filename).suffix.lower()
    return _MIME_TYPES.get(ext, content_type or "application/octet-stream")


def _calc_usage(usage_metadata: Any) -> UsageInfo:
    inp = usage_metadata.prompt_token_count
    out = usage_metadata.candidates_token_count
    cost = (inp / 1_000_000) * PRICE_INPUT_PER_M + (out / 1_000_000) * PRICE_OUTPUT_PER_M
    return UsageInfo(
        input_tokens=inp,
        output_tokens=out,
        total_tokens=usage_metadata.total_token_count,
        cost_usd=round(cost, 8),
    )


def _extract_sync(
    file_bytes: bytes,
    mime_type: str,
    document_type: DocumentType,
    custom_schema: dict[str, Any] | None = None,
    custom_prompt: str | None = None,
) -> tuple[dict[str, Any], UsageInfo]:
    if document_type == DocumentType.CUSTOM:
        schema: type[BaseModel] | dict[str, Any] = custom_schema or {}
        prompt = custom_prompt or _DEFAULT_CUSTOM_PROMPT
    else:
        schema = SCHEMA_MAP[document_type]
        prompt = PROMPTS[document_type]

    response = client.models.generate_content(
        model=GEMINI_MODEL,
        contents=[
            prompt,
            types.Part.from_bytes(data=file_bytes, mime_type=mime_type),
        ],
        config=types.GenerateContentConfig(
            response_mime_type="application/json",
            response_schema=schema,
        ),
    )

    if not response.text:
        msg = f"Gemini returned empty response for {document_type}"
        raise RuntimeError(msg)

    if document_type == DocumentType.CUSTOM:
        result = json.loads(response.text)
    else:
        schema_class = SCHEMA_MAP[document_type]
        result = schema_class.model_validate_json(response.text).model_dump()

    usage = _calc_usage(response.usage_metadata)
    return result, usage


async def extract(
    file_bytes: bytes,
    mime_type: str,
    document_type: DocumentType,
    custom_schema: dict[str, Any] | None = None,
    custom_prompt: str | None = None,
) -> tuple[dict[str, Any], UsageInfo]:
    return await asyncio.to_thread(
        _extract_sync, file_bytes, mime_type, document_type, custom_schema, custom_prompt
    )

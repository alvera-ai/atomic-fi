import asyncio
import json

from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from pydantic import ValidationError

from app.config import MAX_CONCURRENT
from app.extractor import detect_mime_type, extract
from app.schemas import ExtractionResponse, ExtractionResult, FileMetadata

app = FastAPI(
    title="Document Agent",
    version="0.1.0",
    description="Extract structured data from documents (PDFs, images) using Gemini multimodal AI",
)

_semaphore = asyncio.Semaphore(MAX_CONCURRENT)


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/extract", response_model=ExtractionResponse)
async def extract_documents(
    files: list[UploadFile] = File(...),  # noqa: B008
    metadata: str = Form(
        ...,
        description='JSON array — one entry per file: [{"document_type": "passport"}, ...]',
    ),
) -> ExtractionResponse:
    try:
        meta_list = [FileMetadata(**m) for m in json.loads(metadata)]
    except (json.JSONDecodeError, ValidationError) as e:
        raise HTTPException(status_code=422, detail=f"Invalid metadata: {e}") from e

    if len(files) != len(meta_list):
        raise HTTPException(
            status_code=422,
            detail=f"File count ({len(files)}) != metadata count ({len(meta_list)})",
        )

    async def process_one(file: UploadFile, meta: FileMetadata) -> ExtractionResult:
        async with _semaphore:
            try:
                content = await file.read()
                mime = detect_mime_type(file.filename or "unknown", file.content_type)
                data, usage = await extract(
                    content, mime, meta.document_type, meta.output_schema, meta.prompt
                )
                return ExtractionResult(
                    filename=file.filename or "unknown",
                    document_type=meta.document_type,
                    success=True,
                    data=data,
                    usage=usage,
                )
            except Exception as e:
                return ExtractionResult(
                    filename=file.filename or "unknown",
                    document_type=meta.document_type,
                    success=False,
                    error=str(e),
                )

    results = await asyncio.gather(
        *[process_one(f, m) for f, m in zip(files, meta_list, strict=True)]
    )
    return ExtractionResponse(results=list(results))

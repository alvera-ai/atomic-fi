import json
from unittest.mock import MagicMock

from fastapi.testclient import TestClient

from app.schemas import DocumentType


def _fake_gemini_response(text: str) -> MagicMock:
    resp = MagicMock()
    resp.text = text
    resp.usage_metadata.prompt_token_count = 100
    resp.usage_metadata.candidates_token_count = 50
    resp.usage_metadata.total_token_count = 150
    return resp


PASSPORT_JSON = json.dumps(
    {
        "personal_info": {
            "first_name": "JOHN",
            "last_name": "DOE",
            "full_name": "JOHN DOE",
            "date_of_birth": "1990-01-15",
            "gender": "M",
            "nationality": "USA",
            "phone": None,
            "address": None,
        },
        "document_info": {
            "id_type": "passport",
            "id_number": "X12345678",
            "issue_date": "2020-01-01",
            "expiry_date": "2030-01-01",
            "issuing_authority": "US DEPT OF STATE",
            "issuing_country": "USA",
        },
    }
)


def test_extract_single_file(client: TestClient, mock_gemini: MagicMock) -> None:
    mock_gemini.models.generate_content.return_value = _fake_gemini_response(PASSPORT_JSON)

    resp = client.post(
        "/extract",
        files=[("files", ("test.jpg", b"fake-image-bytes", "image/jpeg"))],
        data={"metadata": json.dumps([{"document_type": "passport"}])},
    )

    assert resp.status_code == 200
    body = resp.json()
    assert len(body["results"]) == 1

    result = body["results"][0]
    assert result["success"] is True
    assert result["filename"] == "test.jpg"
    assert result["document_type"] == DocumentType.PASSPORT
    assert result["data"]["personal_info"]["first_name"] == "JOHN"
    assert result["usage"]["input_tokens"] == 100


def test_extract_metadata_mismatch(client: TestClient) -> None:
    resp = client.post(
        "/extract",
        files=[("files", ("a.jpg", b"bytes", "image/jpeg"))],
        data={
            "metadata": json.dumps(
                [
                    {"document_type": "passport"},
                    {"document_type": "visa"},
                ]
            )
        },
    )
    assert resp.status_code == 422
    assert "metadata count" in resp.json()["detail"]


def test_extract_invalid_metadata(client: TestClient) -> None:
    resp = client.post(
        "/extract",
        files=[("files", ("a.jpg", b"bytes", "image/jpeg"))],
        data={"metadata": "not-json"},
    )
    assert resp.status_code == 422


def test_extract_invalid_document_type(client: TestClient) -> None:
    resp = client.post(
        "/extract",
        files=[("files", ("a.jpg", b"bytes", "image/jpeg"))],
        data={"metadata": json.dumps([{"document_type": "invalid_type"}])},
    )
    assert resp.status_code == 422


def test_extract_gemini_failure_returns_error(client: TestClient, mock_gemini: MagicMock) -> None:
    mock_gemini.models.generate_content.side_effect = RuntimeError("Gemini API down")

    resp = client.post(
        "/extract",
        files=[("files", ("test.pdf", b"fake-pdf", "application/pdf"))],
        data={"metadata": json.dumps([{"document_type": "bank_statement"}])},
    )

    assert resp.status_code == 200
    result = resp.json()["results"][0]
    assert result["success"] is False
    assert "Gemini API down" in result["error"]


def test_extract_custom_schema(client: TestClient, mock_gemini: MagicMock) -> None:
    custom_response = json.dumps({"invoice_number": "INV-001", "total": 1500.00})
    mock_gemini.models.generate_content.return_value = _fake_gemini_response(custom_response)

    custom_schema = {
        "type": "object",
        "properties": {
            "invoice_number": {"type": "string"},
            "total": {"type": "number"},
        },
    }

    resp = client.post(
        "/extract",
        files=[("files", ("invoice.pdf", b"fake-pdf", "application/pdf"))],
        data={
            "metadata": json.dumps([{"document_type": "custom", "output_schema": custom_schema}])
        },
    )

    assert resp.status_code == 200
    result = resp.json()["results"][0]
    assert result["success"] is True
    assert result["data"]["invoice_number"] == "INV-001"
    assert result["data"]["total"] == 1500.00


def test_extract_custom_schema_with_prompt(client: TestClient, mock_gemini: MagicMock) -> None:
    custom_response = json.dumps({"name": "ACME", "employees": 42})
    mock_gemini.models.generate_content.return_value = _fake_gemini_response(custom_response)

    resp = client.post(
        "/extract",
        files=[("files", ("doc.pdf", b"fake-pdf", "application/pdf"))],
        data={
            "metadata": json.dumps(
                [
                    {
                        "document_type": "custom",
                        "output_schema": {
                            "type": "object",
                            "properties": {
                                "name": {"type": "string"},
                                "employees": {"type": "integer"},
                            },
                        },
                        "prompt": "Extract company info from this document.",
                    }
                ]
            )
        },
    )

    assert resp.status_code == 200
    result = resp.json()["results"][0]
    assert result["success"] is True
    assert result["data"]["name"] == "ACME"


def test_extract_custom_missing_schema(client: TestClient) -> None:
    resp = client.post(
        "/extract",
        files=[("files", ("a.pdf", b"bytes", "application/pdf"))],
        data={"metadata": json.dumps([{"document_type": "custom"}])},
    )
    assert resp.status_code == 422


def test_extract_multiple_files(client: TestClient, mock_gemini: MagicMock) -> None:
    mock_gemini.models.generate_content.return_value = _fake_gemini_response(PASSPORT_JSON)

    resp = client.post(
        "/extract",
        files=[
            ("files", ("a.jpg", b"bytes-a", "image/jpeg")),
            ("files", ("b.jpg", b"bytes-b", "image/jpeg")),
        ],
        data={
            "metadata": json.dumps(
                [
                    {"document_type": "passport"},
                    {"document_type": "passport"},
                ]
            )
        },
    )

    assert resp.status_code == 200
    assert len(resp.json()["results"]) == 2
    assert all(r["success"] for r in resp.json()["results"])

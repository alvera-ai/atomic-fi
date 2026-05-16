from collections.abc import Generator
from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient

from app.main import app


@pytest.fixture
def client() -> Generator[TestClient, None, None]:
    with TestClient(app) as c:
        yield c


@pytest.fixture
def mock_gemini() -> Generator[MagicMock, None, None]:
    with patch("app.extractor.client") as mock_client:
        yield mock_client

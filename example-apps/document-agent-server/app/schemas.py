from enum import StrEnum
from typing import Any, Self

from pydantic import BaseModel, Field, model_validator


class DocumentType(StrEnum):
    PASSPORT = "passport"
    DRIVING_LICENCE = "driving_licence"
    NATIONAL_ID = "national_id"
    VISA = "visa"
    BANK_STATEMENT = "bank_statement"
    MEMORANDUM = "memorandum"
    CUSTOM = "custom"


# ---------------------------------------------------------------------------
# Identity documents (passport, licence, national ID, visa)
# ---------------------------------------------------------------------------


class PersonalInfo(BaseModel):
    first_name: str | None = Field(None, description="First/given name")
    last_name: str | None = Field(None, description="Last/family name")
    full_name: str | None = Field(None, description="Full name as shown on document")
    date_of_birth: str | None = Field(None, description="Date of birth YYYY-MM-DD")
    gender: str | None = Field(None, description="M or F")
    nationality: str | None = Field(None, description="Nationality or citizenship")
    phone: str | None = Field(None, description="Phone number if present")
    address: str | None = Field(None, description="Residential address if present")


class DocumentInfo(BaseModel):
    id_type: str | None = Field(
        None, description="passport, driving_licence, national_id, visa, other"
    )
    id_number: str | None = Field(None, description="Document ID/number")
    issue_date: str | None = Field(None, description="Issue date YYYY-MM-DD")
    expiry_date: str | None = Field(None, description="Expiry date YYYY-MM-DD")
    issuing_authority: str | None = Field(None, description="Issuing authority")
    issuing_country: str | None = Field(None, description="Issuing country")


class IdentityDocument(BaseModel):
    personal_info: PersonalInfo
    document_info: DocumentInfo


# ---------------------------------------------------------------------------
# Bank statement
# ---------------------------------------------------------------------------


class Transaction(BaseModel):
    date: str | None = Field(None, description="Transaction date YYYY-MM-DD")
    description: str | None = Field(None, description="Transaction narration")
    reference: str | None = Field(None, description="Reference number")
    debit: float | None = Field(None, description="Debit amount (money out)")
    credit: float | None = Field(None, description="Credit amount (money in)")
    balance: float | None = Field(None, description="Running balance after transaction")


class BankAccountInfo(BaseModel):
    account_holder: str | None = Field(None, description="Account holder name")
    account_number: str | None = Field(None, description="Account number (may be masked)")
    iban: str | None = Field(None, description="IBAN if present")
    account_type: str | None = Field(None, description="savings, current, etc.")
    currency: str | None = Field(None, description="Currency code (AED, USD, etc.)")
    bank_name: str | None = Field(None, description="Bank name")
    branch: str | None = Field(None, description="Branch name or code")


class BankStatement(BaseModel):
    account: BankAccountInfo
    statement_period_start: str | None = Field(None, description="Start date YYYY-MM-DD")
    statement_period_end: str | None = Field(None, description="End date YYYY-MM-DD")
    opening_balance: float | None = Field(None, description="Opening balance")
    closing_balance: float | None = Field(None, description="Closing balance")
    total_debits: float | None = Field(None, description="Sum of all debits")
    total_credits: float | None = Field(None, description="Sum of all credits")
    transactions: list[Transaction] = Field(default_factory=list, description="All transactions")


# ---------------------------------------------------------------------------
# Memorandum of Association
# ---------------------------------------------------------------------------


class Shareholder(BaseModel):
    name: str | None = Field(None, description="Shareholder name")
    nationality: str | None = Field(None, description="Nationality")
    shares: int | None = Field(None, description="Number of shares")
    share_percentage: float | None = Field(None, description="Ownership percentage")


class Director(BaseModel):
    name: str | None = Field(None, description="Director name")
    nationality: str | None = Field(None, description="Nationality")
    role: str | None = Field(None, description="chairman, managing director, director, etc.")


class Amendment(BaseModel):
    date: str | None = Field(None, description="Amendment date YYYY-MM-DD")
    description: str | None = Field(None, description="What was amended")


class MemorandumOfAssociation(BaseModel):
    company_name: str | None = Field(None, description="Full legal company name")
    registered_address: str | None = Field(None, description="Registered office address")
    date_of_formation: str | None = Field(None, description="Date of formation YYYY-MM-DD")
    capital_amount: float | None = Field(None, description="Total capital amount")
    capital_currency: str | None = Field(None, description="Currency of capital")
    shareholders: list[Shareholder] = Field(default_factory=list)
    directors: list[Director] = Field(default_factory=list)
    business_activities: list[str] = Field(default_factory=list)
    signing_authority: str | None = Field(None, description="Signing authority and conditions")
    quorum_rules: str | None = Field(None, description="Quorum requirements")
    amendments: list[Amendment] = Field(default_factory=list)


# ---------------------------------------------------------------------------
# API request / response
# ---------------------------------------------------------------------------


class FileMetadata(BaseModel):
    document_type: DocumentType
    label: str | None = None
    output_schema: dict[str, Any] | None = None
    prompt: str | None = None

    @model_validator(mode="after")
    def custom_requires_schema(self) -> Self:
        if self.document_type == DocumentType.CUSTOM and not self.output_schema:
            msg = "'output_schema' is required when document_type is 'custom'"
            raise ValueError(msg)
        return self


class UsageInfo(BaseModel):
    input_tokens: int
    output_tokens: int
    total_tokens: int
    cost_usd: float


class ExtractionResult(BaseModel):
    filename: str
    document_type: DocumentType
    success: bool
    data: dict[str, Any] | None = None
    error: str | None = None
    usage: UsageInfo | None = None


class ExtractionResponse(BaseModel):
    results: list[ExtractionResult]

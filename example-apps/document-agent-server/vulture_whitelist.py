"""Vulture whitelist — suppress false positives for Pydantic models and FastAPI."""

from app.schemas import (
    Amendment,
    BankAccountInfo,
    BankStatement,
    Director,
    DocumentInfo,
    DocumentType,
    ExtractionResponse,
    ExtractionResult,
    FileMetadata,
    IdentityDocument,
    MemorandumOfAssociation,
    PersonalInfo,
    Shareholder,
    Transaction,
    UsageInfo,
)

# Pydantic fields are class-level declarations, not dead code
PersonalInfo.first_name
PersonalInfo.last_name
PersonalInfo.full_name
PersonalInfo.date_of_birth
PersonalInfo.gender
PersonalInfo.nationality
PersonalInfo.phone
PersonalInfo.address

DocumentInfo.id_type
DocumentInfo.id_number
DocumentInfo.issue_date
DocumentInfo.expiry_date
DocumentInfo.issuing_authority
DocumentInfo.issuing_country

IdentityDocument.personal_info
IdentityDocument.document_info

Transaction.date
Transaction.description
Transaction.reference
Transaction.debit
Transaction.credit
Transaction.balance

BankAccountInfo.account_holder
BankAccountInfo.account_number
BankAccountInfo.iban
BankAccountInfo.account_type
BankAccountInfo.currency
BankAccountInfo.bank_name
BankAccountInfo.branch

BankStatement.account
BankStatement.statement_period_start
BankStatement.statement_period_end
BankStatement.opening_balance
BankStatement.closing_balance
BankStatement.total_debits
BankStatement.total_credits
BankStatement.transactions

Shareholder.name
Shareholder.nationality
Shareholder.shares
Shareholder.share_percentage

Director.name
Director.nationality
Director.role

Amendment.date
Amendment.description

MemorandumOfAssociation.company_name
MemorandumOfAssociation.registered_address
MemorandumOfAssociation.date_of_formation
MemorandumOfAssociation.capital_amount
MemorandumOfAssociation.capital_currency
MemorandumOfAssociation.shareholders
MemorandumOfAssociation.directors
MemorandumOfAssociation.business_activities
MemorandumOfAssociation.signing_authority
MemorandumOfAssociation.quorum_rules
MemorandumOfAssociation.amendments

FileMetadata.document_type
FileMetadata.label
FileMetadata.output_schema
FileMetadata.prompt
FileMetadata.custom_requires_schema

UsageInfo.input_tokens
UsageInfo.output_tokens
UsageInfo.total_tokens
UsageInfo.cost_usd

ExtractionResult.filename
ExtractionResult.document_type
ExtractionResult.success
ExtractionResult.data
ExtractionResult.error
ExtractionResult.usage

ExtractionResponse.results

# Enum values
DocumentType.PASSPORT
DocumentType.DRIVING_LICENCE
DocumentType.NATIONAL_ID
DocumentType.VISA
DocumentType.BANK_STATEMENT
DocumentType.MEMORANDUM
DocumentType.CUSTOM

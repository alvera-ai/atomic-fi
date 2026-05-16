from app.schemas import DocumentType

_IDENTITY_PROMPT = (
    "You are a document data extractor. Extract all personal and document information "
    "from this {doc_type}. Use null for fields not found. "
    "Dates in YYYY-MM-DD format. gender: M or F. "
    "id_type should be '{id_type}'. "
    "Correct obvious OCR errors using context."
)

PROMPTS: dict[DocumentType, str] = {
    DocumentType.PASSPORT: _IDENTITY_PROMPT.format(
        doc_type="passport",
        id_type="passport",
    ),
    DocumentType.DRIVING_LICENCE: _IDENTITY_PROMPT.format(
        doc_type="driving licence",
        id_type="driving_licence",
    ),
    DocumentType.NATIONAL_ID: _IDENTITY_PROMPT.format(
        doc_type="national ID card",
        id_type="national_id",
    ),
    DocumentType.VISA: _IDENTITY_PROMPT.format(
        doc_type="visa document",
        id_type="visa",
    ),
    DocumentType.BANK_STATEMENT: (
        "You are a bank statement data extractor. "
        "Extract ALL information from this bank statement. "
        "Include every single transaction — do not skip or summarize. "
        "Dates in YYYY-MM-DD format. Amounts as numbers without currency symbols. "
        "For debit/credit: if the statement uses a single amount column with DR/CR indicators, "
        "map debits to the debit field and credits to the credit field. "
        "Calculate total_debits and total_credits as sums if not shown on the statement."
    ),
    DocumentType.MEMORANDUM: (
        "You are a legal document data extractor specializing in "
        "Memorandum and Articles of Association. "
        "Extract all fields: company name, registered address, share structure "
        "(each shareholder with name, nationality, shares, ownership %), "
        "directors (name, nationality, role), "
        "business activities, signing authority, quorum rules, capital amount/currency, "
        "date of formation, and amendment history. "
        "Dates in YYYY-MM-DD format. Amounts as numbers without currency symbols. "
        "If the document is in Arabic and English, prefer the English text. "
        "Use null for fields not found."
    ),
}

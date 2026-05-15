"""Document Agent API client — extract structured data from compliance documents."""

import json
import sys
from pathlib import Path

import httpx
from rich.console import Console
from rich.table import Table

DOCUMENT_AGENT_URL = "http://localhost:8100"

DOCUMENT_TYPES = [
    "passport",
    "driving_licence",
    "national_id",
    "visa",
    "bank_statement",
    "memorandum",
]

console = Console()


def extract(
    files: list[tuple[str, str]],
    base_url: str = DOCUMENT_AGENT_URL,
    timeout: float = 120.0,
) -> dict:
    upload_files = []
    metadata = []

    for path_str, doc_type in files:
        path = Path(path_str)
        if not path.exists():
            console.print(f"[red]File not found: {path}[/red]")
            sys.exit(1)
        if doc_type not in DOCUMENT_TYPES:
            console.print(f"[red]Unknown type '{doc_type}'. Must be one of: {DOCUMENT_TYPES}[/red]")
            sys.exit(1)

        upload_files.append(("files", (path.name, path.read_bytes())))
        metadata.append({"document_type": doc_type})

    with console.status("Extracting..."):
        resp = httpx.post(
            f"{base_url}/extract",
            files=upload_files,
            data={"metadata": json.dumps(metadata)},
            timeout=timeout,
        )
        resp.raise_for_status()

    return resp.json()


def print_results(data: dict) -> None:
    for result in data["results"]:
        filename = result["filename"]
        doc_type = result["document_type"]

        if not result["success"]:
            console.print(f"\n[red]FAILED[/red] {filename} ({doc_type}): {result['error']}")
            continue

        console.print(f"\n[green]OK[/green] [bold]{filename}[/bold] ({doc_type})")

        usage = result.get("usage", {})
        if usage:
            console.print(
                f"   tokens: {usage.get('total_tokens', '?')}  "
                f"cost: ${usage.get('cost_usd', 0):.6f}"
            )

        extracted = result["data"]

        if doc_type in ("passport", "driving_licence", "national_id", "visa"):
            _print_identity(extracted)
        elif doc_type == "bank_statement":
            _print_bank_statement(extracted)
        elif doc_type == "memorandum":
            _print_memorandum(extracted)
        else:
            console.print_json(json.dumps(extracted, indent=2))


def _print_identity(data: dict) -> None:
    pi = data.get("personal_info", {})
    di = data.get("document_info", {})

    table = Table(title="Identity Document", show_header=False, pad_edge=False)
    table.add_column("Field", style="dim")
    table.add_column("Value")

    table.add_row("Name", pi.get("full_name") or "—")
    table.add_row("DOB", pi.get("date_of_birth") or "—")
    table.add_row("Gender", pi.get("gender") or "—")
    table.add_row("Nationality", pi.get("nationality") or "—")
    table.add_row("Doc Type", di.get("id_type") or "—")
    table.add_row("Doc Number", di.get("id_number") or "—")
    table.add_row("Issued", di.get("issue_date") or "—")
    table.add_row("Expires", di.get("expiry_date") or "—")
    table.add_row("Issuer", di.get("issuing_authority") or "—")
    table.add_row("Country", di.get("issuing_country") or "—")
    console.print(table)


def _print_bank_statement(data: dict) -> None:
    acct = data.get("account", {})
    txns = data.get("transactions", [])

    console.print(
        f"   [bold]{acct.get('bank_name', '?')}[/bold] — "
        f"{acct.get('account_holder', '?')} ({acct.get('currency', '?')})"
    )
    console.print(
        f"   Period: {data.get('statement_period_start', '?')} → "
        f"{data.get('statement_period_end', '?')}"
    )
    console.print(
        f"   Opening: {data.get('opening_balance', '?')}  "
        f"Closing: {data.get('closing_balance', '?')}"
    )

    table = Table(title=f"Transactions ({len(txns)})")
    table.add_column("Date")
    table.add_column("Description")
    table.add_column("Debit", justify="right", style="red")
    table.add_column("Credit", justify="right", style="green")
    table.add_column("Balance", justify="right")

    for tx in txns:
        table.add_row(
            tx.get("date") or "",
            (tx.get("description") or "")[:50],
            f"{tx['debit']:,.2f}" if tx.get("debit") else "",
            f"{tx['credit']:,.2f}" if tx.get("credit") else "",
            f"{tx['balance']:,.2f}" if tx.get("balance") is not None else "",
        )
    console.print(table)


def _print_memorandum(data: dict) -> None:
    console.print(f"   [bold]{data.get('company_name', '?')}[/bold]")
    console.print(f"   Address: {data.get('registered_address', '?')}")
    console.print(
        f"   Capital: {data.get('capital_currency', '?')} "
        f"{data.get('capital_amount', '?'):,}"
    )

    shareholders = data.get("shareholders", [])
    if shareholders:
        table = Table(title="Shareholders")
        table.add_column("Name")
        table.add_column("Nationality")
        table.add_column("Shares", justify="right")
        table.add_column("%", justify="right")
        for s in shareholders:
            table.add_row(
                s.get("name") or "—",
                s.get("nationality") or "—",
                f"{s['shares']:,}" if s.get("shares") else "—",
                f"{s['share_percentage']}%" if s.get("share_percentage") else "—",
            )
        console.print(table)

    directors = data.get("directors", [])
    if directors:
        table = Table(title="Directors")
        table.add_column("Name")
        table.add_column("Role")
        table.add_column("Nationality")
        for d in directors:
            table.add_row(
                d.get("name") or "—",
                d.get("role") or "—",
                d.get("nationality") or "—",
            )
        console.print(table)


def main() -> None:
    if len(sys.argv) < 3 or len(sys.argv) % 2 == 0:
        console.print("[bold]Usage:[/bold] doc-extract <file> <type> [<file> <type> ...]")
        console.print(f"\n[dim]Types: {', '.join(DOCUMENT_TYPES)}[/dim]")
        console.print("\n[bold]Examples:[/bold]")
        console.print("  doc-extract passport.jpg passport")
        console.print("  doc-extract stmt.pdf bank_statement moa.pdf memorandum")
        sys.exit(1)

    args = sys.argv[1:]
    files = [(args[i], args[i + 1]) for i in range(0, len(args), 2)]

    console.print(f"[dim]Sending {len(files)} file(s) to {DOCUMENT_AGENT_URL}[/dim]")

    data = extract(files)
    print_results(data)

    console.print(f"\n[dim]Raw JSON written to stdout with --json flag[/dim]")


if __name__ == "__main__":
    main()

import { useEffect, useMemo, useState } from "react";
import {
  ColumnDef,
  flexRender,
  getCoreRowModel,
  getFilteredRowModel,
  getPaginationRowModel,
  getSortedRowModel,
  SortingState,
  useReactTable,
} from "@tanstack/react-table";
import { ArrowUpDown, ChevronLeft, ChevronRight, Play, RotateCcw, Sparkles, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { listTransactions } from "@/api";
import { getAllLiveHits } from "@/api/rules";
import { listCases, subscribeCases, type Case } from "@/api/cases";
import type { TransactionResponse, TransactionStatus, TransactionType } from "@/api/types";
import { accountHolders, counterparties } from "@/data/fixtures";
import { formatAmount, shortId } from "@/lib/money";
import { StatusPill } from "@/components/status-pill";
import { TransactionDetail } from "@/components/transactions/transaction-detail";
import { useCopilot } from "@/contexts/copilot-context";
import { cn } from "@/lib/utils";

const STATUSES: TransactionStatus[] = ["pending", "accepted", "settled", "rejected", "reversed", "cancelled"];
const TYPES: TransactionType[] = ["credit_transfer", "direct_debit", "card_payment", "refund", "reversal", "internal_transfer"];

const holderName = (id: string) => accountHolders.find((a) => a.id === id)?.display_name ?? "—";
const cpName = (id: string | null) => (id ? counterparties.find((c) => c.id === id)?.display_name ?? "—" : "—");

export default function TransactionsPage() {
  const [rows, setRows] = useState<TransactionResponse[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [search, setSearch] = useState("");
  const [statusFilter, setStatusFilter] = useState<TransactionStatus | "all">("all");
  const [typeFilter, setTypeFilter] = useState<TransactionType | "all">("all");
  const [sorting, setSorting] = useState<SortingState>([{ id: "inserted_at", desc: true }]);
  const [nlPrompt, setNlPrompt] = useState("");
  const [flaggedOnly, setFlaggedOnly] = useState(false);
  const [cases, setCases] = useState<Case[]>([]);
  const c = useCopilot();

  useEffect(() => {
    listTransactions().then(setRows);
    listCases().then(setCases);
    const unsub = subscribeCases(() => listCases().then(setCases));
    return () => { unsub(); };
  }, []);

  const flaggedTxIds = useMemo(() => {
    const ids = new Set<string>();
    for (const cs of cases) {
      if (cs.source_type === "transaction" && cs.status !== "closed") ids.add(cs.source_id);
    }
    for (const h of getAllLiveHits()) {
      if (h.scope === "transaction") ids.add(h.subject_id);
    }
    return ids;
  }, [cases, rows]);

  const sourceRows = c.appliedRows ?? rows;

  const filteredRows = useMemo(() => {
    const s = search.trim().toLowerCase();
    return sourceRows.filter((t) => {
      if (statusFilter !== "all" && t.status !== statusFilter) return false;
      if (typeFilter !== "all" && t.transaction_type !== typeFilter) return false;
      if (flaggedOnly && !flaggedTxIds.has(t.id)) return false;
      if (s) {
        const blob = [t.id, t.uetr, t.end_to_end_id, t.instruction_id, t.transaction_external_id]
          .filter(Boolean)
          .join(" ").toLowerCase();
        if (!blob.includes(s)) return false;
      }
      return true;
    });
  }, [sourceRows, search, statusFilter, typeFilter, flaggedOnly, flaggedTxIds]);

  const columns = useMemo<ColumnDef<TransactionResponse>[]>(() => [
    {
      accessorKey: "id",
      header: "ID",
      cell: ({ row }) => <span className="font-mono text-xs">{shortId(row.original.id, 10)}</span>,
    },
    {
      accessorKey: "transaction_type",
      header: "Type",
      cell: ({ row }) => <span className="text-xs capitalize">{row.original.transaction_type.replace(/_/g, " ")}</span>,
    },
    {
      accessorKey: "status",
      header: "Status",
      cell: ({ row }) => <StatusPill value={row.original.status} />,
    },
    {
      accessorKey: "amount",
      header: ({ column }) => (
        <button onClick={() => column.toggleSorting()} className="flex items-center gap-1">
          Amount <ArrowUpDown className="h-3 w-3" />
        </button>
      ),
      cell: ({ row }) => (
        <span className="font-mono text-xs">{formatAmount(row.original.amount, row.original.currency)}</span>
      ),
    },
    {
      id: "holder",
      header: "Account holder",
      cell: ({ row }) => <span className="text-xs">{holderName(row.original.account_holder_id)}</span>,
    },
    {
      id: "creditor",
      header: "Creditor counterparty",
      cell: ({ row }) => <span className="text-xs">{cpName(row.original.creditor_counterparty_id)}</span>,
    },
    {
      accessorKey: "settlement_date",
      header: ({ column }) => (
        <button onClick={() => column.toggleSorting()} className="flex items-center gap-1">
          Settlement <ArrowUpDown className="h-3 w-3" />
        </button>
      ),
      cell: ({ row }) => <span className="text-xs text-muted-foreground">{row.original.settlement_date ?? "—"}</span>,
    },
    {
      accessorKey: "uetr",
      header: "UETR",
      cell: ({ row }) => <span className="font-mono text-[11px] text-muted-foreground">{row.original.uetr ? shortId(row.original.uetr, 10) : "—"}</span>,
    },
  ], []);

  const table = useReactTable({
    data: filteredRows,
    columns,
    state: { sorting },
    onSortingChange: setSorting,
    getCoreRowModel: getCoreRowModel(),
    getSortedRowModel: getSortedRowModel(),
    getFilteredRowModel: getFilteredRowModel(),
    getPaginationRowModel: getPaginationRowModel(),
    initialState: { pagination: { pageSize: 12 } },
  });

  const selected = useMemo(() => rows.find((r) => r.id === selectedId), [rows, selectedId]);

  const handleRunNl = () => {
    if (!nlPrompt.trim()) return;
    c.setPrompt(nlPrompt);
    c.openDrawer();
    c.run(nlPrompt);
  };

  const resetFilters = () => {
    setSearch(""); setStatusFilter("all"); setTypeFilter("all"); setFlaggedOnly(false);
  };

  const handleUpdated = (next: TransactionResponse) => {
    setRows((prev) => prev.map((r) => (r.id === next.id ? next : r)));
  };

  return (
    <div className="flex h-full">
      <div className="flex min-w-0 flex-1 flex-col gap-3 p-4">
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-xl font-semibold tracking-tight">
              {flaggedOnly ? "Transactions — flagged only" : "Transactions"}
            </h1>
            <p className="text-xs text-muted-foreground">{filteredRows.length} of {sourceRows.length} transactions</p>
          </div>
        </div>

        <Card className="p-3">
          <div className="flex flex-wrap items-center gap-2">
            <Input
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search id, UETR, EndToEndId…"
              className="h-9 w-[260px]"
            />
            <Select value={statusFilter} onValueChange={(v) => setStatusFilter(v as TransactionStatus | "all")}>
              <SelectTrigger className="h-9 w-[150px]"><SelectValue placeholder="Status" /></SelectTrigger>
              <SelectContent>
                <SelectItem value="all">All statuses</SelectItem>
                {STATUSES.map((s) => <SelectItem key={s} value={s}>{s}</SelectItem>)}
              </SelectContent>
            </Select>
            <Select value={typeFilter} onValueChange={(v) => setTypeFilter(v as TransactionType | "all")}>
              <SelectTrigger className="h-9 w-[180px]"><SelectValue placeholder="Type" /></SelectTrigger>
              <SelectContent>
                <SelectItem value="all">All types</SelectItem>
                {TYPES.map((t) => <SelectItem key={t} value={t}>{t.replace(/_/g, " ")}</SelectItem>)}
              </SelectContent>
            </Select>
            <Button
              type="button"
              size="sm"
              onClick={() => setFlaggedOnly((v) => !v)}
              className={cn(
                "h-9 rounded-full border px-3 text-xs font-medium transition",
                flaggedOnly
                  ? "border-warning bg-warning text-warning-foreground hover:bg-warning/90"
                  : "border-border bg-transparent text-muted-foreground hover:bg-muted",
              )}
            >
              Flagged{flaggedOnly ? "" : ` · ${flaggedTxIds.size}`}
            </Button>
            <Button variant="ghost" size="sm" onClick={resetFilters} className="gap-1.5">
              <RotateCcw className="h-3.5 w-3.5" /> Reset
            </Button>
          </div>

          <div className="mt-3 flex items-center gap-2 rounded-md border bg-muted/40 p-2">
            <Sparkles className="h-4 w-4 shrink-0 text-primary" />
            <Input
              value={nlPrompt}
              onChange={(e) => setNlPrompt(e.target.value)}
              onKeyDown={(e) => { if (e.key === "Enter") handleRunNl(); }}
              placeholder="Ask in plain English — e.g. pending USD transactions over 10k"
              className="h-8 border-0 bg-transparent shadow-none focus-visible:ring-0"
            />
            <Button size="sm" onClick={handleRunNl} className="h-8 gap-1.5" disabled={!nlPrompt.trim()}>
              <Play className="h-3.5 w-3.5" /> Run
            </Button>
          </div>

          {c.appliedRows && (
            <div className="mt-2 flex items-center gap-2 rounded-md bg-primary/10 px-2.5 py-1.5 text-xs">
              <Sparkles className="h-3.5 w-3.5 text-primary" />
              <span className="font-medium">NL filter applied</span>
              <span className="text-muted-foreground">· {c.appliedRows.length} rows</span>
              <Button variant="ghost" size="sm" className="ml-auto h-6 gap-1 px-2 text-xs" onClick={c.clearApplied}>
                <X className="h-3 w-3" /> Clear
              </Button>
            </div>
          )}
        </Card>

        <Card className="min-h-0 flex-1 overflow-hidden">
          <div className="h-full overflow-auto">
            <table className="w-full text-sm">
              <thead className="sticky top-0 z-10 bg-card text-left text-xs text-muted-foreground">
                {table.getHeaderGroups().map((hg) => (
                  <tr key={hg.id} className="border-b">
                    {hg.headers.map((h) => (
                      <th key={h.id} className="px-3 py-2 font-medium">
                        {h.isPlaceholder ? null : flexRender(h.column.columnDef.header, h.getContext())}
                      </th>
                    ))}
                  </tr>
                ))}
              </thead>
              <tbody>
                {table.getRowModel().rows.map((row) => (
                  <tr
                    key={row.id}
                    onClick={() => setSelectedId(row.original.id)}
                    className={cn(
                      "cursor-pointer border-b transition hover:bg-muted/40",
                      selectedId === row.original.id && "bg-primary/5",
                    )}
                  >
                    {row.getVisibleCells().map((cell) => (
                      <td key={cell.id} className="px-3 py-2">
                        {flexRender(cell.column.columnDef.cell, cell.getContext())}
                      </td>
                    ))}
                  </tr>
                ))}
                {table.getRowModel().rows.length === 0 && (
                  <tr><td colSpan={columns.length} className="p-8 text-center text-sm text-muted-foreground">No transactions match.</td></tr>
                )}
              </tbody>
            </table>
          </div>
        </Card>

        <div className="flex items-center justify-between gap-2 text-xs text-muted-foreground">
          <div>Page {table.getState().pagination.pageIndex + 1} of {table.getPageCount() || 1}</div>
          <div className="flex items-center gap-1">
            <Button variant="outline" size="sm" onClick={() => table.previousPage()} disabled={!table.getCanPreviousPage()}>
              <ChevronLeft className="h-3.5 w-3.5" /> Prev
            </Button>
            <Button variant="outline" size="sm" onClick={() => table.nextPage()} disabled={!table.getCanNextPage()}>
              Next <ChevronRight className="h-3.5 w-3.5" />
            </Button>
          </div>
        </div>
      </div>

      <aside className={cn(
        "hidden w-[460px] shrink-0 border-l bg-background transition-all xl:block",
      )}>
        {selected ? (
          <TransactionDetail tx={selected} onUpdated={handleUpdated} />
        ) : (
          <div className="flex h-full flex-col items-center justify-center gap-2 p-8 text-center text-sm text-muted-foreground">
            <div className="flex h-10 w-10 items-center justify-center rounded-full bg-muted">
              <Sparkles className="h-4 w-4" />
            </div>
            Select a transaction to view its 360° detail.
          </div>
        )}
      </aside>
    </div>
  );
}

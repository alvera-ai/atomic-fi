import { Eye, Filter, MoreHorizontal, Search } from "lucide-react";
import { useState } from "react";
import { useNavigate } from "react-router-dom";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Input } from "@/components/ui/input";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import type { ApplicationStatus } from "@/features/onboarding/types";
import { useApplicationsList } from "@/features/onboarding/useApplication";
import { cn } from "@/lib/utils";

const STATUS_STYLES: Record<ApplicationStatus, { label: string; className: string }> = {
  DRAFT: { label: "Draft", className: "bg-muted text-muted-foreground" },
  SUBMITTED: {
    label: "Submitted",
    className: "bg-blue-100 text-blue-800 dark:bg-blue-900/30 dark:text-blue-400",
  },
  UNDER_REVIEW: {
    label: "Under Review",
    className: "bg-blue-100 text-blue-800 dark:bg-blue-900/30 dark:text-blue-400",
  },
  ACTION_REQUIRED: {
    label: "Action Required",
    className: "bg-amber-100 text-amber-800 dark:bg-amber-900/30 dark:text-amber-400",
  },
  APPROVED: { label: "Approved", className: "bg-primary/10 text-primary" },
  UNABLE_TO_PROCEED: {
    label: "Unable to Proceed",
    className: "bg-destructive/10 text-destructive",
  },
};

export default function OpsListPage() {
  const navigate = useNavigate();
  const { applications, loading } = useApplicationsList();
  const [searchQuery, setSearchQuery] = useState("");

  const filteredApplications = applications.filter((app) => {
    const searchLower = searchQuery.toLowerCase();
    return (
      app.application_id.toLowerCase().includes(searchLower) ||
      app.business_profile.legal_name?.toLowerCase().includes(searchLower) ||
      app.status.toLowerCase().includes(searchLower)
    );
  });

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-foreground">Applications</h1>
        <p className="text-muted-foreground mt-1">Review and manage onboarding applications</p>
      </div>

      {/* Search and filters */}
      <div className="flex items-center gap-3">
        <div className="relative flex-1 max-w-sm">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
          <Input
            placeholder="Search applications..."
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            className="pl-9"
          />
        </div>
        <Button variant="outline" size="icon">
          <Filter className="h-4 w-4" />
        </Button>
      </div>

      {/* Applications table */}
      {loading ? (
        <div className="text-center py-12 text-muted-foreground">Loading...</div>
      ) : filteredApplications.length === 0 ? (
        <div className="text-center py-12">
          <p className="text-muted-foreground mb-4">No applications found</p>
          <Button onClick={() => navigate("/start")}>Create Test Application</Button>
        </div>
      ) : (
        <div className="border rounded-lg">
          <Table>
            <TableHeader>
              <TableRow>
                <TableHead>Application ID</TableHead>
                <TableHead>Business Name</TableHead>
                <TableHead>Status</TableHead>
                <TableHead>Method</TableHead>
                <TableHead>Created</TableHead>
                <TableHead className="w-12"></TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {filteredApplications.map((app) => {
                const statusStyle = STATUS_STYLES[app.status];
                return (
                  <TableRow
                    key={app.application_id}
                    className="cursor-pointer"
                    onClick={() => navigate(`/ops/${app.application_id}`)}
                  >
                    <TableCell className="font-mono text-sm">{app.application_id}</TableCell>
                    <TableCell className="font-medium">
                      {app.business_profile.legal_name || "—"}
                    </TableCell>
                    <TableCell>
                      <Badge variant="secondary" className={cn("text-xs", statusStyle.className)}>
                        {statusStyle.label}
                      </Badge>
                    </TableCell>
                    <TableCell className="text-muted-foreground">
                      {app.onboarding_method === "UPLOAD_PREFILL" ? "Upload" : "Manual"}
                    </TableCell>
                    <TableCell className="text-muted-foreground">
                      {new Date(app.created_at).toLocaleDateString()}
                    </TableCell>
                    <TableCell>
                      <DropdownMenu>
                        <DropdownMenuTrigger asChild onClick={(e) => e.stopPropagation()}>
                          <Button variant="ghost" size="icon" className="h-8 w-8">
                            <MoreHorizontal className="h-4 w-4" />
                          </Button>
                        </DropdownMenuTrigger>
                        <DropdownMenuContent align="end">
                          <DropdownMenuItem onClick={() => navigate(`/ops/${app.application_id}`)}>
                            <Eye className="h-4 w-4 mr-2" />
                            View details
                          </DropdownMenuItem>
                        </DropdownMenuContent>
                      </DropdownMenu>
                    </TableCell>
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
        </div>
      )}
    </div>
  );
}

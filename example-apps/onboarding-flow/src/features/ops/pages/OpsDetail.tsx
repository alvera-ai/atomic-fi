import {
  AlertCircle,
  ArrowLeft,
  ArrowRightLeft,
  Briefcase,
  Building,
  CheckCircle,
  Clock,
  FileText,
  MapPin,
  Network,
  Plus,
  UserCheck,
  Users,
  XCircle,
} from "lucide-react";
import { useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { toast } from "sonner";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Separator } from "@/components/ui/separator";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { Textarea } from "@/components/ui/textarea";
import { ONBOARDING_STEPS } from "@/features/onboarding/constants";
import type { ApplicationStatus, OpsNote } from "@/features/onboarding/types";
import { useApplication } from "@/features/onboarding/useApplication";
import { cn } from "@/lib/utils";

const STATUS_OPTIONS: { value: ApplicationStatus; label: string; icon: typeof CheckCircle }[] = [
  { value: "DRAFT", label: "Draft", icon: FileText },
  { value: "SUBMITTED", label: "Submitted", icon: Clock },
  { value: "UNDER_REVIEW", label: "Under Review", icon: Clock },
  { value: "ACTION_REQUIRED", label: "Action Required", icon: AlertCircle },
  { value: "APPROVED", label: "Approved", icon: CheckCircle },
  { value: "UNABLE_TO_PROCEED", label: "Unable to Proceed", icon: XCircle },
];

const SECTION_ICONS: Record<string, typeof FileText> = {
  documents: FileText,
  identity: Building,
  addresses: MapPin,
  contacts: Users,
  activity: Briefcase,
  transfers: ArrowRightLeft,
  ownership: Network,
  directors: Users,
  ubos: UserCheck,
};

export default function OpsDetailPage() {
  const { applicationId } = useParams<{ applicationId: string }>();
  const navigate = useNavigate();
  const { application, loading, updateApplication, updateStatus } = useApplication(applicationId);
  const [newNote, setNewNote] = useState("");

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <p className="text-muted-foreground">Loading...</p>
      </div>
    );
  }

  if (!application) {
    return (
      <div className="flex flex-col items-center justify-center h-64 gap-4">
        <p className="text-muted-foreground">Application not found</p>
        <Button onClick={() => navigate("/ops")}>Back to Applications</Button>
      </div>
    );
  }

  const handleStatusChange = (newStatus: ApplicationStatus) => {
    updateStatus(newStatus);
    toast.success(`Status updated to ${newStatus.replace("_", " ")}`);
  };

  const handleAddNote = () => {
    if (!newNote.trim()) return;

    const note: OpsNote = {
      id: `note-${Date.now()}`,
      author: "Ops User",
      content: newNote.trim(),
      created_at: new Date().toISOString(),
    };

    updateApplication({
      ops_notes: [...application.ops_notes, note],
    });

    setNewNote("");
    toast.success("Note added");
  };

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-start justify-between">
        <div className="flex items-center gap-4">
          <Button variant="ghost" size="icon" onClick={() => navigate("/ops")}>
            <ArrowLeft className="h-4 w-4" />
          </Button>
          <div>
            <h1 className="text-2xl font-bold text-foreground">
              {application.business_profile.legal_name || "Untitled Application"}
            </h1>
            <p className="text-sm text-muted-foreground font-mono">{application.application_id}</p>
          </div>
        </div>

        {/* Status selector */}
        <div className="flex items-center gap-3">
          <Select
            value={application.status}
            onValueChange={(value) => handleStatusChange(value as ApplicationStatus)}
          >
            <SelectTrigger className="w-48">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {STATUS_OPTIONS.map((option) => (
                <SelectItem key={option.value} value={option.value}>
                  <div className="flex items-center gap-2">
                    <option.icon className="h-4 w-4" />
                    {option.label}
                  </div>
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
      </div>

      <Tabs defaultValue="overview" className="space-y-4">
        <TabsList>
          <TabsTrigger value="overview">Overview</TabsTrigger>
          <TabsTrigger value="documents">Documents</TabsTrigger>
          <TabsTrigger value="notes">Notes ({application.ops_notes.length})</TabsTrigger>
        </TabsList>

        <TabsContent value="overview" className="space-y-4">
          {/* Quick info */}
          <Card>
            <CardHeader>
              <CardTitle className="text-base">Application Info</CardTitle>
            </CardHeader>
            <CardContent>
              <dl className="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
                <div>
                  <dt className="text-muted-foreground">Created</dt>
                  <dd className="font-medium">
                    {new Date(application.created_at).toLocaleDateString()}
                  </dd>
                </div>
                <div>
                  <dt className="text-muted-foreground">Updated</dt>
                  <dd className="font-medium">
                    {new Date(application.updated_at).toLocaleDateString()}
                  </dd>
                </div>
                <div>
                  <dt className="text-muted-foreground">Method</dt>
                  <dd className="font-medium">
                    {application.onboarding_method === "UPLOAD_PREFILL"
                      ? "Upload & Prefill"
                      : "Manual Entry"}
                  </dd>
                </div>
                <div>
                  <dt className="text-muted-foreground">Progress</dt>
                  <dd className="font-medium">
                    {application.completed_steps.length} / {ONBOARDING_STEPS.length - 1} steps
                  </dd>
                </div>
              </dl>
            </CardContent>
          </Card>

          {/* Sections summary */}
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            {ONBOARDING_STEPS.slice(0, -1).map((step) => {
              const Icon = SECTION_ICONS[step.path] || FileText;
              const isComplete = application.completed_steps.includes(step.id);

              return (
                <Card key={step.id} className={cn(!isComplete && "opacity-60")}>
                  <CardHeader className="pb-2">
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-2">
                        <Icon className="h-4 w-4 text-muted-foreground" />
                        <CardTitle className="text-sm">{step.title}</CardTitle>
                      </div>
                      {isComplete ? (
                        <Badge variant="secondary" className="text-xs bg-primary/10 text-primary">
                          Complete
                        </Badge>
                      ) : (
                        <Badge variant="outline" className="text-xs">
                          Incomplete
                        </Badge>
                      )}
                    </div>
                  </CardHeader>
                  <CardContent>
                    <p className="text-xs text-muted-foreground">{step.description}</p>
                  </CardContent>
                </Card>
              );
            })}
          </div>
        </TabsContent>

        <TabsContent value="documents" className="space-y-4">
          <Card>
            <CardHeader>
              <CardTitle className="text-base">Uploaded Documents</CardTitle>
              <CardDescription>
                {application.documents.length} document
                {application.documents.length !== 1 ? "s" : ""} uploaded
              </CardDescription>
            </CardHeader>
            <CardContent>
              {application.documents.length === 0 ? (
                <p className="text-sm text-muted-foreground py-4 text-center">
                  No documents uploaded yet
                </p>
              ) : (
                <div className="space-y-2">
                  {application.documents.map((doc) => (
                    <div
                      key={doc.file_id}
                      className="flex items-center justify-between p-3 bg-muted/50 rounded-lg"
                    >
                      <div className="flex items-center gap-3">
                        <FileText className="h-4 w-4 text-muted-foreground" />
                        <div>
                          <p className="text-sm font-medium">{doc.filename}</p>
                          <p className="text-xs text-muted-foreground">{doc.doc_type}</p>
                        </div>
                      </div>
                      <Badge variant="secondary" className="text-xs">
                        {doc.status}
                      </Badge>
                    </div>
                  ))}
                </div>
              )}
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="notes" className="space-y-4">
          <Card>
            <CardHeader>
              <CardTitle className="text-base">Ops Notes</CardTitle>
              <CardDescription>Internal notes and comments</CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              {/* Add note */}
              <div className="space-y-2">
                <Textarea
                  placeholder="Add a note..."
                  value={newNote}
                  onChange={(e) => setNewNote(e.target.value)}
                  rows={3}
                />
                <Button
                  onClick={handleAddNote}
                  disabled={!newNote.trim()}
                  size="sm"
                  className="gap-2"
                >
                  <Plus className="h-4 w-4" />
                  Add Note
                </Button>
              </div>

              <Separator />

              {/* Notes list */}
              {application.ops_notes.length === 0 ? (
                <p className="text-sm text-muted-foreground py-4 text-center">No notes yet</p>
              ) : (
                <div className="space-y-3">
                  {[...application.ops_notes].reverse().map((note) => (
                    <div key={note.id} className="p-3 bg-muted/50 rounded-lg">
                      <div className="flex items-center justify-between mb-2">
                        <span className="text-sm font-medium">{note.author}</span>
                        <span className="text-xs text-muted-foreground">
                          {new Date(note.created_at).toLocaleString()}
                        </span>
                      </div>
                      <p className="text-sm text-foreground">{note.content}</p>
                    </div>
                  ))}
                </div>
              )}
            </CardContent>
          </Card>
        </TabsContent>
      </Tabs>
    </div>
  );
}

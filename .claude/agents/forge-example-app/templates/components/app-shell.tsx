import { type ReactNode } from "react";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";

// Three-tab shell every generated app inherits. The Demo tab content
// is bespoke per use case; Rule and Audit panels are baseline.
//
// Tabs are a uniform UX across the demo fleet: an operator who's seen
// one app knows where to find the rule editor and audit view in any
// other.
export function AppShell({
  appName,
  demo,
  ruleEditor,
  audit,
}: {
  appName: string;
  demo: ReactNode;
  ruleEditor: ReactNode;
  audit: ReactNode;
}) {
  return (
    <div className="min-h-screen bg-background">
      <header className="border-b">
        <div className="mx-auto flex max-w-7xl items-center justify-between px-6 py-4">
          <h1 className="text-lg font-semibold tracking-tight">{appName}</h1>
          <span className="text-xs text-muted-foreground">atomic-fi demo</span>
        </div>
      </header>

      <main className="mx-auto max-w-7xl px-6 py-6">
        <Tabs defaultValue="demo" className="w-full">
          <TabsList>
            <TabsTrigger value="demo">Demo</TabsTrigger>
            <TabsTrigger value="rule">Rule</TabsTrigger>
            <TabsTrigger value="audit">Audit</TabsTrigger>
          </TabsList>

          <TabsContent value="demo" className="mt-6 space-y-6">
            {demo}
          </TabsContent>

          <TabsContent value="rule" className="mt-6">
            {ruleEditor}
          </TabsContent>

          <TabsContent value="audit" className="mt-6">
            {audit}
          </TabsContent>
        </Tabs>
      </main>
    </div>
  );
}

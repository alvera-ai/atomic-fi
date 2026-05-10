import { lazy, Suspense } from "react";
import type { JdmGraph } from "@/api/types";
import "@gorules/jdm-editor/dist/style.css";

// Lazy-loaded so the heavy antd/monaco/reactflow deps don't bloat the main bundle.
const Inner = lazy(async () => {
  const mod = await import("@gorules/jdm-editor");
  const { DecisionGraph, JdmConfigProvider } = mod;
  return {
    default: ({ value, onChange, disabled }: {
      value: JdmGraph;
      onChange: (g: JdmGraph) => void;
      disabled?: boolean;
    }) => (
      <JdmConfigProvider>
        <DecisionGraph
          value={value as never}
          onChange={(v) => onChange(v as unknown as JdmGraph)}
          disabled={disabled}
        />
      </JdmConfigProvider>
    ),
  };
});

export function JdmGraphEditor({
  value, onChange, disabled, className,
}: {
  value: JdmGraph;
  onChange: (g: JdmGraph) => void;
  disabled?: boolean;
  className?: string;
}) {
  return (
    <div className={className} style={{ height: "60vh", minHeight: 480 }}>
      <Suspense
        fallback={
          <div className="grid h-full place-items-center text-xs text-muted-foreground">
            Loading JDM editor…
          </div>
        }
      >
        <Inner value={value} onChange={onChange} disabled={disabled} />
      </Suspense>
    </div>
  );
}

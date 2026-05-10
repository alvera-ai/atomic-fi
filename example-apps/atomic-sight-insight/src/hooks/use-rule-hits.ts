import { useEffect, useState } from "react";
import type { RuleHit, RuleScope } from "@/api/types";
import { getLiveHits, subscribe } from "@/lib/rules/store";

export function useRuleHits(scope: RuleScope, subjectId: string | undefined): RuleHit[] {
  const [hits, setHits] = useState<RuleHit[]>(() => (subjectId ? getLiveHits(scope, subjectId) : []));
  useEffect(() => {
    if (!subjectId) { setHits([]); return; }
    setHits(getLiveHits(scope, subjectId));
    return subscribe(() => setHits(getLiveHits(scope, subjectId)));
  }, [scope, subjectId]);
  return hits;
}

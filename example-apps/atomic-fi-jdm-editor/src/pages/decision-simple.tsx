import React, { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Button, Dropdown, message, theme as antTheme } from 'antd';
import {
  ArrowLeftOutlined,
  BulbOutlined,
  CheckOutlined,
  CloseOutlined,
  MessageOutlined,
  PlayCircleOutlined,
  SaveOutlined,
} from '@ant-design/icons';
import { DecisionGraph, DecisionGraphRef, DecisionGraphType, GraphSimulator, Simulation } from '@gorules/jdm-editor';
import { DirectedGraph } from 'graphology';
import { hasCycle } from 'graphology-dag';
import { useBlocker, useNavigate, useParams, useSearchParams } from 'react-router-dom';

import { CopilotChat } from '@copilotkit/react-ui';

import { ApplyAllFooter } from '../copilot/cards/apply-all-footer';
import { displayError, errorMessage } from '../helpers/error-message';
import { getRule, listRules, RULE_TYPES, RULE_TYPE_LABELS, type RuleType, saveRule } from '../helpers/rules-api';
import { runSimulation } from '../helpers/simulator';
import { ThemePreference, useTheme } from '../context/theme.provider';
import { useEditorReadables } from '../copilot/use-editor-readables';
import { useGraphActions } from '../copilot/actions/use-graph-actions';
import { usePersistActions } from '../copilot/actions/use-persist-actions';
import { useSimulateAction } from '../copilot/actions/use-simulate-action';

const DECISION_CONTENT_TYPE = 'application/vnd.gorules.decision';

const isRuleType = (s: string | undefined): s is RuleType =>
  s !== undefined && (RULE_TYPES as string[]).includes(s);

const emptyGraph: DecisionGraphType = { nodes: [], edges: [] };

const checkCyclic = (graph: DecisionGraphType): void => {
  const diGraph = new DirectedGraph();
  graph.edges.forEach((edge) => {
    if (edge.sourceId && edge.targetId) diGraph.mergeEdge(edge.sourceId, edge.targetId);
  });
  if (hasCycle(diGraph)) {
    throw new Error('Circular dependencies detected');
  }
};

export const DecisionSimplePage: React.FC = () => {
  const navigate = useNavigate();
  const { ruleType: ruleTypeParam, name: nameParam } = useParams<{ ruleType: string; name: string }>();
  const [searchParams] = useSearchParams();
  const { themePreference, setThemePreference } = useTheme();
  const { token } = antTheme.useToken();
  const graphRef = useRef<DecisionGraphRef>(null);
  // Always-current graph snapshot the agent's action hooks can read at JSX
  // render time without baking a stale graph into closures.
  const currentGraphRef = useRef<DecisionGraphType>(emptyGraph);

  const ruleType: RuleType = isRuleType(ruleTypeParam) ? ruleTypeParam : 'onboarding';
  const name = useMemo(() => (nameParam ? decodeURIComponent(nameParam) : ''), [nameParam]);
  const isNew = searchParams.get('new') === '1';

  const [graph, setGraph] = useState<DecisionGraphType>(emptyGraph);
  const [graphTrace, setGraphTrace] = useState<Simulation>();
  const [lastSimulation, setLastSimulation] = useState<Simulation | null>(null);
  const [revision, setRevision] = useState(0);
  const [savedRevision, setSavedRevision] = useState(0);
  const [loading, setLoading] = useState(!isNew);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);
  const [copilotOpen, setCopilotOpen] = useState(false);

  const dirty = revision !== savedRevision;

  // Keep currentGraphRef in sync with the latest graph state (every render).
  // useEffect would be a render late; assignment during render is fine for refs.
  currentGraphRef.current = graph;
  // Same pattern for revision — onSaved needs to set savedRevision to whatever
  // revision is CURRENT at save time, not what was captured at hook-registration
  // time. (Without this, the agent's save would mark a stale revision as saved
  // and the dirty indicator would never clear.)
  const revisionRef = useRef(revision);
  revisionRef.current = revision;

  // Mark the rule dirty when the agent mutates the graph via an action. The
  // canvas-driven `handleChange` already bumps revision for human edits — this
  // is the analogous hook for agent edits so the Save button reflects reality.
  const markAgentMutation = useCallback(() => {
    setRevision((r) => r + 1);
  }, []);

  const [existingRules, setExistingRules] = useState<Record<RuleType, string[] | undefined>>({
    onboarding: undefined,
    'transaction-screening': undefined,
  });

  const refreshExistingRules = useCallback(async () => {
    const results = await Promise.all(RULE_TYPES.map((t) => listRules(t).then((r) => [t, r] as const)));
    setExistingRules(Object.fromEntries(results) as Record<RuleType, string[]>);
  }, []);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- mount-time seed of existing rule names list
    refreshExistingRules();
  }, [refreshExistingRules]);

  useEffect(() => {
    if (isNew || !name) {
      // eslint-disable-next-line react-hooks/set-state-in-effect -- mount-time load gate for new/empty rule
      setLoading(false);
      return;
    }
    let cancelled = false;
    (async () => {
      setLoading(true);
      setLoadError(null);
      try {
        const data = await getRule(ruleType, name);
        if (cancelled) return;
        setGraph({ nodes: data.nodes ?? [], edges: data.edges ?? [] });
        setRevision(0);
        setSavedRevision(0);
      } catch (e) {
        if (!cancelled) setLoadError(errorMessage(e));
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [ruleType, name, isNew]);

  const handleChange = useCallback((value: DecisionGraphType) => {
    setGraph(value);
    setRevision((r) => r + 1);
  }, []);

  const handleSave = useCallback(async () => {
    if (!name) {
      message.error('Missing rule name.');
      return;
    }
    try {
      checkCyclic(graph);
    } catch (e) {
      displayError(e);
      return;
    }
    setSaving(true);
    try {
      await saveRule(ruleType, name, { contentType: DECISION_CONTENT_TYPE, ...graph });
      setSavedRevision(revision);
      message.success(`Saved ${name}`);
    } catch (e) {
      displayError(e);
    } finally {
      setSaving(false);
    }
  }, [ruleType, name, graph, revision]);

  // Warn on in-app navigation while dirty (route changes).
  const blocker = useBlocker(dirty);
  useEffect(() => {
    if (blocker.state === 'blocked') {
      const proceed = window.confirm('You have unsaved changes. Leave without saving?');
      if (proceed) blocker.proceed();
      else blocker.reset();
    }
  }, [blocker]);

  // Warn on tab close / hard reload while dirty.
  useEffect(() => {
    if (!dirty) return;
    const handler = (e: BeforeUnloadEvent) => {
      e.preventDefault();
    };
    window.addEventListener('beforeunload', handler);
    return () => window.removeEventListener('beforeunload', handler);
  }, [dirty]);

  useEditorReadables({
    ruleType,
    filename: name,
    isNew,
    dirty,
    savedRevision,
    graph,
    lastSimulation,
    existingRules,
  });
  useGraphActions({ setGraph, graphRef: currentGraphRef, onMutated: markAgentMutation });
  usePersistActions({
    ruleType,
    filename: name,
    dirty,
    graph,
    onSaved: () => setSavedRevision(revisionRef.current),
    refreshExistingRules,
  });
  useSimulateAction({
    ruleType,
    filename: name,
    dirty,
    graph,
    setLastSimulation,
  });

  return (
    <div className="flex flex-col h-screen bg-surface text-ink">
      <header
        className="flex items-center justify-between px-6 py-3 border-b border-rule"
        style={{ background: token.colorBgLayout }}
      >
        <div className="flex items-center gap-3 min-w-0">
          <Button
            type="text"
            icon={<ArrowLeftOutlined />}
            onClick={() => navigate(`/rules/${ruleType}`)}
            aria-label="Back to rules"
          />
          <nav className="flex items-center gap-2 min-w-0 text-sm">
            <span className="font-display italic text-ink-muted">Rules</span>
            <span className="text-ink-muted">/</span>
            <span className="font-display italic text-ink-muted">{RULE_TYPE_LABELS[ruleType]}</span>
            <span className="text-ink-muted">/</span>
            <span className="font-mono text-ink truncate">{name || 'untitled'}</span>
            {dirty && (
              <span
                className="inline-block w-1.5 h-1.5 rounded-full bg-accent ml-1 shrink-0"
                aria-label="unsaved changes"
                title="Unsaved changes"
              />
            )}
          </nav>
        </div>
        <div className="flex items-center gap-2 shrink-0">
          <Button
            type={dirty ? 'primary' : 'default'}
            icon={<SaveOutlined />}
            onClick={handleSave}
            loading={saving}
            disabled={!name || (!dirty && !isNew)}
          >
            Save
          </Button>
          <Button
            type={copilotOpen ? 'primary' : 'text'}
            icon={<MessageOutlined />}
            onClick={() => setCopilotOpen((open) => !open)}
            aria-label={copilotOpen ? 'Close rule copilot' : 'Open rule copilot'}
            aria-pressed={copilotOpen}
          />
          <Dropdown
            menu={{
              onClick: ({ key }) => setThemePreference(key as ThemePreference),
              items: [
                { label: 'Automatic', key: ThemePreference.Automatic, icon: <ThemeCheck active={themePreference === ThemePreference.Automatic} /> },
                { label: 'Dark', key: ThemePreference.Dark, icon: <ThemeCheck active={themePreference === ThemePreference.Dark} /> },
                { label: 'Light', key: ThemePreference.Light, icon: <ThemeCheck active={themePreference === ThemePreference.Light} /> },
              ],
            }}
          >
            <Button type="text" icon={<BulbOutlined />} />
          </Dropdown>
        </div>
      </header>

      <div className="flex-1 flex overflow-hidden min-h-0">
        <div className="flex-1 overflow-hidden min-w-0">
          {loadError ? (
            <div className="h-full flex flex-col items-center justify-center gap-3 text-ink-muted">
              <p className="text-sm">Could not load rule. {loadError}</p>
              <Button type="link" onClick={() => navigate(`/rules/${ruleType}`)}>
                Back to rules
              </Button>
            </div>
          ) : loading ? (
            <div className="h-full flex items-center justify-center text-ink-muted text-sm">loading…</div>
          ) : (
            <DecisionGraph
              ref={graphRef}
              value={graph}
              onChange={handleChange}
              reactFlowProOptions={{ hideAttribution: true }}
              simulate={graphTrace}
              panels={[
                {
                  id: 'simulator',
                  title: 'Simulator',
                  icon: <PlayCircleOutlined />,
                  renderPanel: () => (
                    <GraphSimulator
                      onClear={() => setGraphTrace(undefined)}
                      onRun={async ({ graph: simGraph, context }) => {
                        if (!name) {
                          message.error('Save the rule before simulating.');
                          return;
                        }
                        if (dirty) {
                          message.warning('Simulator evaluates the last saved version. Save your changes first.');
                        }
                        const sim = await runSimulation({
                          ruleType,
                          name,
                          input: { graph: simGraph, context },
                        });
                        setGraphTrace(sim);
                        setLastSimulation(sim);
                        if (sim.error?.message) message.error(sim.error.message);
                      }}
                    />
                  ),
                },
              ]}
            />
          )}
        </div>

        {copilotOpen && (
          <aside
            className="w-[420px] shrink-0 border-l border-rule flex flex-col min-h-0"
            style={{ background: token.colorBgContainer }}
            aria-label="Rule copilot"
          >
            <div
              className="flex items-center justify-between px-3 py-2 border-b border-rule shrink-0"
              style={{ background: token.colorBgLayout }}
            >
              <span className="font-display text-sm">Rule copilot</span>
              <Button
                type="text"
                size="small"
                icon={<CloseOutlined />}
                onClick={() => setCopilotOpen(false)}
                aria-label="Close rule copilot"
              />
            </div>
            <div className="flex-1 min-h-0 overflow-hidden">
              <CopilotChat
                labels={{
                  title: 'Rule copilot',
                  initial:
                    "Describe a rule in plain English and I'll draft, save, and simulate it for you. Each step surfaces a card you can Apply or Reject.",
                }}
                instructions=""
                className="h-full"
              />
            </div>
          </aside>
        )}
      </div>

      <ApplyAllFooter />
    </div>
  );
};

const ThemeCheck: React.FC<{ active: boolean }> = ({ active }) => (
  <CheckOutlined style={{ visibility: active ? 'visible' : 'hidden' }} />
);

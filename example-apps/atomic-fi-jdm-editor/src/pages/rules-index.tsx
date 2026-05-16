import React, { useEffect, useMemo, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { Button, Dropdown, Input, message, Popconfirm } from 'antd';
import { BulbOutlined, CheckOutlined, DeleteOutlined, PlusOutlined } from '@ant-design/icons';
import { deleteRule, listRules, RULE_TYPES, RULE_TYPE_LABELS, type RuleType } from '../helpers/rules-api';
import { errorMessage } from '../helpers/error-message';
import { ThemePreference, useTheme } from '../context/theme.provider';

const isRuleType = (s: string | undefined): s is RuleType =>
  s !== undefined && (RULE_TYPES as string[]).includes(s);

export const RulesIndexPage: React.FC = () => {
  const navigate = useNavigate();
  const { ruleType: ruleTypeParam } = useParams<{ ruleType: string }>();
  const ruleType: RuleType = isRuleType(ruleTypeParam) ? ruleTypeParam : 'onboarding';

  const { themePreference, setThemePreference } = useTheme();

  const [rulesByType, setRulesByType] = useState<Record<RuleType, string[] | undefined>>({
    onboarding: undefined,
    'transaction-screening': undefined,
  });
  const [filter, setFilter] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const refresh = async () => {
    setLoading(true);
    setError(null);
    try {
      const results = await Promise.all(RULE_TYPES.map((t) => listRules(t).then((r) => [t, r] as const)));
      setRulesByType(Object.fromEntries(results) as Record<RuleType, string[]>);
    } catch (e) {
      setError(errorMessage(e));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    refresh();
  }, []);

  const visibleRules = useMemo(() => {
    const all = rulesByType[ruleType] ?? [];
    const q = filter.trim().toLowerCase();
    return q ? all.filter((n) => n.toLowerCase().includes(q)) : all;
  }, [rulesByType, ruleType, filter]);

  const handleNewRule = () => {
    const raw = window.prompt('New rule filename (must end in .json):', 'new_rule.json');
    if (!raw) return;
    const name = raw.trim();
    if (!name.endsWith('.json') || name.includes('/') || name.includes('\\')) {
      message.error('Filename must end in .json and contain no path separators.');
      return;
    }
    navigate(`/rules/${ruleType}/${encodeURIComponent(name)}?new=1`);
  };

  const handleDelete = async (name: string) => {
    try {
      await deleteRule(ruleType, name);
      message.success(`Deleted ${name}`);
      await refresh();
    } catch (e) {
      message.error(errorMessage(e));
    }
  };

  return (
    <div className="min-h-screen bg-surface text-ink">
      <header className="flex items-center justify-between px-8 py-5 border-b border-rule">
        <h1 className="font-display text-2xl tracking-tight">Rules</h1>
        <div className="flex items-center gap-2">
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
          <Button type="primary" icon={<PlusOutlined />} onClick={handleNewRule}>
            New rule
          </Button>
        </div>
      </header>

      <nav className="flex gap-6 px-8 border-b border-rule">
        {RULE_TYPES.map((t) => {
          const count = rulesByType[t]?.length;
          const active = t === ruleType;
          return (
            <Link
              key={t}
              to={`/rules/${t}`}
              className={[
                'py-3 text-sm transition-colors',
                active ? 'text-ink border-b-2 border-accent -mb-px' : 'text-ink-muted hover:text-ink border-b-2 border-transparent -mb-px',
              ].join(' ')}
            >
              {RULE_TYPE_LABELS[t]}
              {typeof count === 'number' && <span className="ml-2 text-ink-muted tabular-nums">{count}</span>}
            </Link>
          );
        })}
      </nav>

      <section className="px-8 py-6 max-w-5xl">
        <div className="flex items-center justify-between mb-4">
          <Input
            placeholder="filter rules"
            value={filter}
            onChange={(e) => setFilter(e.target.value)}
            allowClear
            className="max-w-xs"
          />
          <span className="text-sm text-ink-muted tabular-nums">
            {loading ? 'loading…' : `${visibleRules.length} ${visibleRules.length === 1 ? 'rule' : 'rules'}`}
          </span>
        </div>

        {error ? (
          <ErrorBlock message={error} onRetry={refresh} />
        ) : !loading && visibleRules.length === 0 ? (
          <EmptyBlock ruleType={ruleType} hasFilter={filter.trim().length > 0} onNew={handleNewRule} />
        ) : (
          <ul className="divide-y divide-rule border-y border-rule">
            {visibleRules.map((name) => (
              <li key={name} className="group flex items-center justify-between py-2.5">
                <Link
                  to={`/rules/${ruleType}/${encodeURIComponent(name)}`}
                  className="flex-1 font-mono text-sm text-ink hover:text-accent hover:underline underline-offset-4 decoration-1"
                >
                  {name}
                </Link>
                <Popconfirm
                  title="Delete rule?"
                  description={`This will remove ${name} from the rules directory.`}
                  okText="Delete"
                  okButtonProps={{ danger: true }}
                  cancelText="Cancel"
                  onConfirm={() => handleDelete(name)}
                >
                  <Button
                    type="text"
                    size="small"
                    icon={<DeleteOutlined />}
                    className="opacity-0 group-hover:opacity-100 focus-visible:opacity-100 transition-opacity"
                  />
                </Popconfirm>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
};

const ThemeCheck: React.FC<{ active: boolean }> = ({ active }) => (
  <CheckOutlined style={{ visibility: active ? 'visible' : 'hidden' }} />
);

const EmptyBlock: React.FC<{ ruleType: RuleType; hasFilter: boolean; onNew: () => void }> = ({
  ruleType,
  hasFilter,
  onNew,
}) => (
  <div className="py-12 text-center">
    <p className="text-sm text-ink-muted">
      {hasFilter
        ? 'No rules match this filter.'
        : `No ${RULE_TYPE_LABELS[ruleType].toLowerCase()} rules yet.`}
    </p>
    {!hasFilter && (
      <Button type="link" onClick={onNew} className="mt-2">
        Create the first one
      </Button>
    )}
  </div>
);

const ErrorBlock: React.FC<{ message: string; onRetry: () => void }> = ({ message, onRetry }) => (
  <div className="py-12 text-center">
    <p className="text-sm text-ink-muted">Could not load rules. {message}</p>
    <Button type="link" onClick={onRetry} className="mt-2">
      Retry
    </Button>
  </div>
);

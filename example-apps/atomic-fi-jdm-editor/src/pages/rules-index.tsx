import React, { useEffect, useMemo, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { Button, Dropdown, Empty, Input, message, Popconfirm, Tabs, theme as antTheme } from 'antd';
import { BulbOutlined, CheckOutlined, DeleteOutlined, FileTextOutlined, PlusOutlined, ReloadOutlined, SearchOutlined } from '@ant-design/icons';
import { deleteRule, listRules, RULE_TYPES, RULE_TYPE_LABELS, type RuleType } from '../helpers/rules-api';
import { errorMessage } from '../helpers/error-message';
import { ThemePreference, useTheme } from '../context/theme.provider';

const isRuleType = (s: string | undefined): s is RuleType =>
  s !== undefined && (RULE_TYPES as string[]).includes(s);

export const RulesIndexPage: React.FC = () => {
  const navigate = useNavigate();
  const { ruleType: ruleTypeParam } = useParams<{ ruleType: string }>();
  const ruleType: RuleType = isRuleType(ruleTypeParam) ? ruleTypeParam : 'onboarding';
  const { token } = antTheme.useToken();

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

  const total = rulesByType[ruleType]?.length;
  const countLabel = loading
    ? 'loading…'
    : typeof total === 'number'
      ? `${visibleRules.length} of ${total}`
      : '—';

  return (
    <div className="flex flex-col h-screen bg-surface text-ink">
      <header
        className="flex items-center justify-between px-6 py-3 border-b border-rule shrink-0"
        style={{ background: token.colorBgLayout }}
      >
        <div className="flex items-baseline gap-3 min-w-0">
          <span className="font-display italic text-ink-muted text-sm">atomic-fi</span>
          <span className="text-ink-muted text-sm">/</span>
          <h1 className="font-display text-lg tracking-tight m-0">Rules</h1>
        </div>
        <div className="flex items-center gap-2 shrink-0">
          <Button id="new-rule-button" type="primary" icon={<PlusOutlined />} onClick={handleNewRule}>
            New rule
          </Button>
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

      <div className="px-6 border-b border-rule shrink-0" style={{ background: token.colorBgLayout }}>
        <Tabs
          activeKey={ruleType}
          onChange={(key) => navigate(`/rules/${key}`)}
          size="small"
          tabBarStyle={{ margin: 0 }}
          items={RULE_TYPES.map((t) => ({
            key: t,
            label: (
              <span className="inline-flex items-center gap-2">
                <span>{RULE_TYPE_LABELS[t]}</span>
                <span
                  className="inline-flex items-center justify-center min-w-[1.25rem] h-[1.25rem] px-1.5 rounded-full text-[11px] tabular-nums"
                  style={{
                    background: t === ruleType ? token.colorPrimaryBg : token.colorFillTertiary,
                    color: t === ruleType ? token.colorPrimary : token.colorTextSecondary,
                  }}
                >
                  {rulesByType[t]?.length ?? '·'}
                </span>
              </span>
            ),
          }))}
        />
      </div>

      <main className="flex-1 overflow-auto">
        <section className="mx-auto max-w-3xl px-6 py-8">
          <div className="flex items-center justify-between gap-4 mb-3">
            <Input
              placeholder="Filter rules"
              value={filter}
              onChange={(e) => setFilter(e.target.value)}
              allowClear
              prefix={<SearchOutlined style={{ color: token.colorTextTertiary }} />}
              className="max-w-sm"
            />
            <div className="flex items-center gap-3 text-xs text-ink-muted tabular-nums">
              <span>{countLabel}</span>
              <Button
                type="text"
                size="small"
                icon={<ReloadOutlined />}
                onClick={refresh}
                loading={loading}
                aria-label="Refresh"
              />
            </div>
          </div>

          {error ? (
            <ErrorBlock message={error} onRetry={refresh} />
          ) : !loading && visibleRules.length === 0 ? (
            <EmptyBlock ruleType={ruleType} hasFilter={filter.trim().length > 0} onNew={handleNewRule} />
          ) : (
            <ul
              className="rounded-md overflow-hidden divide-y"
              style={{
                background: token.colorBgContainer,
                borderColor: token.colorBorderSecondary,
                borderWidth: 1,
                borderStyle: 'solid',
              }}
            >
              {visibleRules.map((name) => (
                <RuleRow
                  key={name}
                  name={name}
                  href={`/rules/${ruleType}/${encodeURIComponent(name)}`}
                  onDelete={() => handleDelete(name)}
                />
              ))}
            </ul>
          )}
        </section>
      </main>
    </div>
  );
};

const RuleRow: React.FC<{ name: string; href: string; onDelete: () => void }> = ({ name, href, onDelete }) => {
  const { token } = antTheme.useToken();
  return (
    <li
      className="group flex items-center justify-between gap-3 px-4 py-2.5 transition-colors"
      onMouseEnter={(e) => (e.currentTarget.style.background = token.colorFillQuaternary)}
      onMouseLeave={(e) => (e.currentTarget.style.background = 'transparent')}
    >
      <Link to={href} className="flex items-center gap-3 flex-1 min-w-0 no-underline">
        <FileTextOutlined style={{ color: token.colorTextTertiary, fontSize: 14 }} />
        <span className="font-mono text-[13px] text-ink truncate">{name}</span>
      </Link>
      <Popconfirm
        title="Delete rule?"
        description={`This will remove ${name} from the rules directory.`}
        okText="Delete"
        okButtonProps={{ danger: true }}
        cancelText="Cancel"
        onConfirm={onDelete}
      >
        <Button
          type="text"
          size="small"
          icon={<DeleteOutlined />}
          aria-label={`Delete ${name}`}
          className="opacity-0 group-hover:opacity-100 focus-visible:opacity-100 transition-opacity"
        />
      </Popconfirm>
    </li>
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
  <div className="py-16">
    <Empty
      image={Empty.PRESENTED_IMAGE_SIMPLE}
      description={
        <span className="text-sm text-ink-muted">
          {hasFilter
            ? 'No rules match this filter.'
            : `No ${RULE_TYPE_LABELS[ruleType].toLowerCase()} rules yet.`}
        </span>
      }
    >
      {!hasFilter && (
        <Button type="primary" size="small" icon={<PlusOutlined />} onClick={onNew}>
          Create your first rule
        </Button>
      )}
    </Empty>
  </div>
);

const ErrorBlock: React.FC<{ message: string; onRetry: () => void }> = ({ message, onRetry }) => (
  <div className="py-16 text-center">
    <p className="text-sm text-ink-muted m-0">Could not load rules. {message}</p>
    <Button type="link" size="small" onClick={onRetry} className="mt-1">
      Retry
    </Button>
  </div>
);

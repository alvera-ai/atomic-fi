import type { NodeData } from '../types'

type Props = {
  data: NodeData
  onChange: (patch: Partial<NodeData>) => void
}

type Column = {
  id: string
  type: 'expression'
  name: string
  field: string
}

type Rule = {
  _id: string
  _description?: string
  [columnId: string]: string | undefined
}

type DecisionTableContent = {
  hitPolicy: 'first' | 'collect'
  inputs: Column[]
  outputs: Column[]
  rules: Rule[]
}

const EMPTY: DecisionTableContent = { hitPolicy: 'first', inputs: [], outputs: [], rules: [] }

const newId = (prefix: string) =>
  `${prefix}_${Date.now().toString(36)}_${Math.floor(Math.random() * 1000)}`

const stripKey = <T extends Record<string, unknown>>(obj: T, key: string): T => {
  const next = { ...obj }
  delete next[key]
  return next
}

export function DecisionTableEditor({ data, onChange }: Props) {
  const content: DecisionTableContent = {
    ...EMPTY,
    ...(data.content as DecisionTableContent | undefined),
  }

  const patch = (next: Partial<DecisionTableContent>) =>
    onChange({ content: { ...content, ...next } })

  const addColumn = (kind: 'inputs' | 'outputs') => {
    const id = newId(kind === 'inputs' ? 'in' : 'out')
    patch({
      [kind]: [
        ...content[kind],
        { id, type: 'expression', name: kind === 'inputs' ? 'Input' : 'Output', field: '' },
      ],
    })
  }

  const updateColumn = (kind: 'inputs' | 'outputs', id: string, partial: Partial<Column>) =>
    patch({ [kind]: content[kind].map((c) => (c.id === id ? { ...c, ...partial } : c)) })

  const removeColumn = (kind: 'inputs' | 'outputs', id: string) =>
    patch({
      [kind]: content[kind].filter((c) => c.id !== id),
      rules: content.rules.map((r) => stripKey(r, id) as Rule),
    })

  const addRule = () =>
    patch({ rules: [...content.rules, { _id: newId('rule'), _description: '' }] })

  const updateRule = (_id: string, partial: Partial<Rule>) =>
    patch({ rules: content.rules.map((r) => (r._id === _id ? { ...r, ...partial } : r)) })

  const removeRule = (_id: string) =>
    patch({ rules: content.rules.filter((r) => r._id !== _id) })

  return (
    <div className="flex flex-col gap-6">
      <section className="flex items-center justify-between">
        <span className="eyebrow">Hit Policy</span>
        <select
          value={content.hitPolicy}
          onChange={(e) =>
            patch({ hitPolicy: e.target.value as DecisionTableContent['hitPolicy'] })
          }
          className="rounded-md border border-rule bg-paper px-2.5 py-1 font-mono text-[12px] text-ink focus:border-accent focus:outline-none focus:ring-1 focus:ring-accent"
        >
          <option value="first">first match</option>
          <option value="collect">collect all</option>
        </select>
      </section>

      <ColumnList
        kind="inputs"
        title="Inputs"
        columns={content.inputs}
        onAdd={() => addColumn('inputs')}
        onUpdate={(id, p) => updateColumn('inputs', id, p)}
        onRemove={(id) => removeColumn('inputs', id)}
      />

      <ColumnList
        kind="outputs"
        title="Outputs"
        columns={content.outputs}
        onAdd={() => addColumn('outputs')}
        onUpdate={(id, p) => updateColumn('outputs', id, p)}
        onRemove={(id) => removeColumn('outputs', id)}
      />

      <section>
        <SectionHeader title="Rules" count={content.rules.length}>
          <AddButton onClick={addRule}>Add rule</AddButton>
        </SectionHeader>

        {content.rules.length === 0 ? (
          <p className="rounded-md border border-dashed border-rule bg-paper-2 px-3 py-4 text-center text-[12px] text-ink-3">
            No rules yet. Add one to begin authoring the table.
          </p>
        ) : (
          <div className="overflow-x-auto rounded-lg border border-rule bg-paper">
            <table className="min-w-full text-[12px]">
              <thead>
                <tr className="bg-paper-2">
                  <th className="border-b border-rule px-2.5 py-2 text-left">
                    <span className="eyebrow">Reason</span>
                  </th>
                  {content.inputs.map((c) => (
                    <th
                      key={c.id}
                      className="border-b border-l border-rule px-2.5 py-2 text-left"
                    >
                      <div className="flex items-center gap-1.5">
                        <span className="h-1 w-1 rounded-full bg-violet" />
                        <span className="eyebrow">{c.name}</span>
                      </div>
                    </th>
                  ))}
                  {content.outputs.map((c) => (
                    <th
                      key={c.id}
                      className="border-b border-l border-rule px-2.5 py-2 text-left"
                    >
                      <div className="flex items-center gap-1.5">
                        <span className="h-1 w-1 rounded-full bg-sage" />
                        <span className="eyebrow">{c.name}</span>
                      </div>
                    </th>
                  ))}
                  <th className="w-8 border-b border-rule" />
                </tr>
              </thead>
              <tbody>
                {content.rules.map((rule) => (
                  <tr key={rule._id} className="border-t border-rule">
                    <td className="px-2 py-1">
                      <CellInput
                        value={rule._description ?? ''}
                        placeholder="why"
                        onChange={(v) => updateRule(rule._id, { _description: v })}
                        mono={false}
                      />
                    </td>
                    {content.inputs.map((c) => (
                      <td key={c.id} className="border-l border-rule px-2 py-1">
                        <CellInput
                          value={rule[c.id] ?? ''}
                          placeholder='"value"'
                          onChange={(v) => updateRule(rule._id, { [c.id]: v })}
                        />
                      </td>
                    ))}
                    {content.outputs.map((c) => (
                      <td key={c.id} className="border-l border-rule px-2 py-1">
                        <CellInput
                          value={rule[c.id] ?? ''}
                          placeholder="expr"
                          onChange={(v) => updateRule(rule._id, { [c.id]: v })}
                        />
                      </td>
                    ))}
                    <td className="px-1 py-1 text-right">
                      <button
                        type="button"
                        onClick={() => removeRule(rule._id)}
                        className="rounded p-1 text-ink-4 transition hover:bg-terracotta-soft hover:text-terracotta"
                        aria-label="Remove rule"
                      >
                        ×
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </div>
  )
}

function SectionHeader({
  title,
  count,
  children,
}: {
  title: string
  count?: number
  children?: React.ReactNode
}) {
  return (
    <div className="mb-2 flex items-baseline justify-between">
      <div className="flex items-baseline gap-2">
        <span className="eyebrow">{title}</span>
        {typeof count === 'number' && (
          <span className="font-mono text-[11px] text-ink-4">{count}</span>
        )}
      </div>
      {children}
    </div>
  )
}

function AddButton({
  onClick,
  children,
}: {
  onClick: () => void
  children: React.ReactNode
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="rounded-md border border-rule bg-paper px-2.5 py-1 text-[11.5px] font-medium text-ink-2 transition hover:border-rule-strong hover:bg-paper-2"
    >
      + {children}
    </button>
  )
}

function ColumnList({
  title,
  kind,
  columns,
  onAdd,
  onUpdate,
  onRemove,
}: {
  title: string
  kind: 'inputs' | 'outputs'
  columns: Column[]
  onAdd: () => void
  onUpdate: (id: string, partial: Partial<Column>) => void
  onRemove: (id: string) => void
}) {
  const dot = kind === 'inputs' ? 'bg-violet' : 'bg-sage'
  return (
    <section>
      <SectionHeader title={title} count={columns.length}>
        <AddButton onClick={onAdd}>Column</AddButton>
      </SectionHeader>
      {columns.length === 0 ? (
        <p className="text-[12px] text-ink-3">None.</p>
      ) : (
        <ul className="flex flex-col divide-y divide-rule rounded-lg border border-rule bg-paper">
          {columns.map((col) => (
            <li key={col.id} className="flex items-center gap-2 px-3 py-2">
              <span className={`h-1.5 w-1.5 shrink-0 rounded-full ${dot}`} />
              <input
                type="text"
                value={col.name}
                onChange={(e) => onUpdate(col.id, { name: e.target.value })}
                placeholder="Name"
                className="w-32 border-0 border-b border-transparent bg-transparent px-0 py-0.5 text-[12.5px] font-medium text-ink placeholder:text-ink-4 focus:border-accent focus:outline-none focus:ring-0"
              />
              <input
                type="text"
                value={col.field}
                onChange={(e) => onUpdate(col.id, { field: e.target.value })}
                placeholder="input.path"
                className="flex-1 border-0 border-b border-transparent bg-transparent px-0 py-0.5 font-mono text-[11.5px] text-ink-2 placeholder:text-ink-4 focus:border-accent focus:outline-none focus:ring-0"
              />
              <button
                type="button"
                onClick={() => onRemove(col.id)}
                className="rounded p-1 text-ink-4 transition hover:bg-terracotta-soft hover:text-terracotta"
                aria-label="Remove column"
              >
                ×
              </button>
            </li>
          ))}
        </ul>
      )}
    </section>
  )
}

function CellInput({
  value,
  placeholder,
  onChange,
  mono = true,
}: {
  value: string
  placeholder: string
  onChange: (next: string) => void
  mono?: boolean
}) {
  return (
    <input
      type="text"
      value={value}
      onChange={(e) => onChange(e.target.value)}
      placeholder={placeholder}
      className={`w-full rounded border border-transparent bg-transparent px-1.5 py-1 text-[11.5px] text-ink placeholder:text-ink-4 hover:border-rule focus:border-accent focus:bg-paper-2 focus:outline-none ${
        mono ? 'font-mono' : ''
      }`}
    />
  )
}

import { useEffect, useState } from 'react'
import type { NodeData } from '../types'
import { CodeEditor } from './CodeEditor'

type Props = {
  data: NodeData
  onChange: (patch: Partial<NodeData>) => void
}

export function SchemaEditor({ data, onChange }: Props) {
  const initial = data.content === undefined ? '' : JSON.stringify(data.content, null, 2)
  const [text, setText] = useState(initial)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    setText(data.content === undefined ? '' : JSON.stringify(data.content, null, 2))
    setError(null)
  }, [data.content])

  const commit = () => {
    if (text.trim() === '') {
      onChange({ content: undefined })
      setError(null)
      return
    }
    try {
      onChange({ content: JSON.parse(text) })
      setError(null)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Invalid JSON')
    }
  }

  return (
    <div className="flex h-full flex-col gap-3">
      <div className="flex items-baseline justify-between">
        <span className="eyebrow">Schema</span>
        <span className="text-[11px] text-ink-3">commits on blur</span>
      </div>
      <div onBlur={commit} className="flex-1">
        <CodeEditor
          value={text}
          onChange={setText}
          language="json"
          placeholder={'{\n  "type": "object",\n  "properties": {}\n}'}
          minHeight={280}
        />
      </div>
      {error && (
        <p className="rounded-md bg-terracotta-soft px-3 py-2 font-mono text-[11px] text-terracotta">
          {error}
        </p>
      )}
      <p className="text-[11px] text-ink-3">
        Leave empty for nodes without a declared schema.
      </p>
    </div>
  )
}

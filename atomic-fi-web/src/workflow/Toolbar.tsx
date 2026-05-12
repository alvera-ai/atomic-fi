import type { ChangeEvent } from 'react'

type Props = {
  name: string
  onNameChange: (name: string) => void
  onLoad: (file: File) => void
  onSave: () => void
  onReset: () => void
}

export function Toolbar({ name, onNameChange, onLoad, onSave, onReset }: Props) {
  const handleFile = (event: ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0]
    if (file) onLoad(file)
    event.target.value = ''
  }

  return (
    <header className="flex items-center gap-5 border-b border-rule bg-paper px-6 py-3">
      <div className="flex items-baseline gap-2">
        <span className="text-[15px] font-semibold tracking-tight text-ink">
          AtomicFi
        </span>
        <span className="eyebrow">Workflows</span>
      </div>

      <div className="h-5 w-px bg-rule" />

      <label className="flex items-baseline gap-2.5 text-sm">
        <span className="eyebrow">Name</span>
        <input
          type="text"
          value={name}
          onChange={(e) => onNameChange(e.target.value)}
          placeholder="untitled-workflow"
          className="w-64 border-0 border-b border-transparent bg-transparent px-0 py-1 font-mono text-[13px] text-ink placeholder:text-ink-4 focus:border-accent focus:outline-none focus:ring-0"
        />
      </label>

      <div className="ml-auto flex items-center gap-2">
        <label
          className="cursor-pointer rounded-md border border-rule bg-paper px-3 py-1.5 text-[12.5px] font-medium text-ink-2 transition hover:border-rule-strong hover:bg-paper-2"
        >
          Load
          <input
            type="file"
            accept="application/json,.json"
            className="hidden"
            onChange={handleFile}
          />
        </label>
        <button
          type="button"
          onClick={onReset}
          className="rounded-md border border-rule bg-paper px-3 py-1.5 text-[12.5px] font-medium text-ink-2 transition hover:border-rule-strong hover:bg-paper-2"
        >
          Reset
        </button>
        <button
          type="button"
          onClick={onSave}
          className="rounded-md bg-ink px-3.5 py-1.5 text-[12.5px] font-medium text-paper transition hover:bg-accent"
        >
          Save
        </button>
      </div>
    </header>
  )
}

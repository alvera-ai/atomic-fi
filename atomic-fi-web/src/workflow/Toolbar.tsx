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
    <header className="flex items-center gap-3 border-b border-slate-200 bg-white px-4 py-3">
      <h1 className="text-base font-semibold text-slate-900">AtomicFi Web</h1>
      <div className="mx-4 h-6 w-px bg-slate-200" />
      <label className="flex items-center gap-2 text-sm">
        <span className="text-slate-500">Name</span>
        <input
          type="text"
          value={name}
          onChange={(e) => onNameChange(e.target.value)}
          placeholder="my-workflow"
          className="w-56 rounded-md border border-slate-300 px-2 py-1 text-sm focus:border-indigo-500 focus:outline-none focus:ring-1 focus:ring-indigo-500"
        />
      </label>
      <div className="ml-auto flex items-center gap-2">
        <label className="cursor-pointer rounded-md border border-slate-300 bg-white px-3 py-1.5 text-sm font-medium text-slate-700 transition hover:bg-slate-50">
          Load JSON
          <input type="file" accept="application/json,.json" className="hidden" onChange={handleFile} />
        </label>
        <button
          type="button"
          onClick={onReset}
          className="rounded-md border border-slate-300 bg-white px-3 py-1.5 text-sm font-medium text-slate-700 transition hover:bg-slate-50"
        >
          Reset
        </button>
        <button
          type="button"
          onClick={onSave}
          className="rounded-md bg-indigo-600 px-3 py-1.5 text-sm font-medium text-white shadow-sm transition hover:bg-indigo-700"
        >
          Save
        </button>
      </div>
    </header>
  )
}

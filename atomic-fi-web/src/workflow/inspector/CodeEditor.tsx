import CodeMirror from '@uiw/react-codemirror'
import { json } from '@codemirror/lang-json'
import { javascript } from '@codemirror/lang-javascript'
import { EditorView } from '@codemirror/view'
import type { Extension } from '@codemirror/state'

type Language = 'json' | 'javascript'

type Props = {
  value: string
  onChange: (next: string) => void
  language: Language
  placeholder?: string
  variant?: 'paper' | 'ink'
  minHeight?: number
}

const langs: Record<Language, () => Extension> = {
  json,
  javascript: () => javascript({ jsx: false, typescript: false }),
}

const paperTheme = EditorView.theme(
  {
    '&': {
      color: 'var(--color-ink)',
      background: 'var(--color-paper-2)',
      borderRadius: '8px',
    },
    '.cm-content': { padding: '10px 0', caretColor: 'var(--color-accent)' },
    '.cm-line': { padding: '0 12px' },
    '.cm-cursor': { borderLeftColor: 'var(--color-accent)' },
    '.cm-selectionBackground, ::selection': {
      backgroundColor: 'oklch(0.42 0.16 280 / 0.18) !important',
    },
    '.cm-gutters': { backgroundColor: 'var(--color-paper-2)' },
  },
  { dark: false },
)

const inkTheme = EditorView.theme(
  {
    '&': {
      color: 'var(--color-code-ink)',
      background: 'var(--color-code-bg)',
      borderRadius: '8px',
    },
    '.cm-content': { padding: '12px 0', caretColor: 'oklch(0.85 0.12 70)' },
    '.cm-line': { padding: '0 14px' },
    '.cm-cursor': { borderLeftColor: 'oklch(0.85 0.12 70)' },
    '.cm-selectionBackground, ::selection': {
      backgroundColor: 'oklch(0.65 0.14 70 / 0.25) !important',
    },
    '.cm-gutters': {
      backgroundColor: 'var(--color-code-bg)',
      color: 'oklch(0.5 0.01 280)',
      borderRight: '1px solid oklch(0.28 0.012 280)',
    },
    '.cm-activeLineGutter': { backgroundColor: 'transparent' },
  },
  { dark: true },
)

export function CodeEditor({
  value,
  onChange,
  language,
  placeholder,
  variant = 'paper',
  minHeight = 240,
}: Props) {
  return (
    <div
      className={`overflow-hidden rounded-lg border ${
        variant === 'ink' ? 'border-transparent' : 'border-rule'
      }`}
    >
      <CodeMirror
        value={value}
        onChange={onChange}
        extensions={[langs[language](), EditorView.lineWrapping]}
        theme={variant === 'ink' ? inkTheme : paperTheme}
        placeholder={placeholder}
        basicSetup={{
          lineNumbers: true,
          foldGutter: language === 'json',
          highlightActiveLine: false,
          highlightActiveLineGutter: false,
          autocompletion: false,
          dropCursor: false,
          allowMultipleSelections: false,
          searchKeymap: false,
        }}
        minHeight={`${minHeight}px`}
      />
    </div>
  )
}

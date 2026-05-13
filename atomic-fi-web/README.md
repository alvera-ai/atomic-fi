# AtomicFi Web

A visual editor for decision-graph rule files. Load a JSON rules file,
arrange Input / Output / Decision Table / Function nodes on a React Flow
canvas, edit each node in a right-side inspector, and save the result
back to disk.

This package lives inside the `atomic-fi` pnpm workspace at `atomic-fi-web/`.

## Stack

- Vite + React 19 + TypeScript
- React Flow 11 for the graph canvas
- CodeMirror 6 (`@uiw/react-codemirror`) for JSON / JavaScript editing
- Tailwind CSS v4 via `@tailwindcss/vite`
- Geist + Geist Mono (loaded from Google Fonts)

## Setup

From the repository root:

```bash
pnpm install
```

That installs every workspace package, including this one. No extra
step is needed — the dependency list below is already pinned in
`atomic-fi-web/package.json`.

For reference, the runtime and dev dependencies the app adds on top of
the Vite scaffold are:

```bash
# already declared in package.json — listed only for context
pnpm --filter atomic-fi-web add reactflow zustand \
  @uiw/react-codemirror @codemirror/lang-json @codemirror/lang-javascript \
  @codemirror/state @codemirror/view
pnpm --filter atomic-fi-web add -D tailwindcss @tailwindcss/vite
```

## Run

```bash
pnpm --filter atomic-fi-web dev
```

Vite prints a local URL (typically `http://localhost:5173`). Open it in
a browser. The sample rules file in `public/example-rules.json` is
auto-loaded on first paint so the canvas isn't empty.

Other scripts:

```bash
pnpm --filter atomic-fi-web build      # production build
pnpm --filter atomic-fi-web preview    # preview the production build
pnpm --filter atomic-fi-web lint       # eslint
```

## Using the editor

**Add a node.** Drag any item from the left palette onto the canvas.

**Connect nodes.** Drag from a node's right-edge handle to another
node's left-edge handle.

**Edit a node.** Hover over the node and click the pencil icon in the
top-right corner. A right-side inspector opens with a type-specific
editor:

- **Input / Output** — name and an optional JSON schema (CodeMirror).
- **Decision Table** — hit policy, editable input/output columns, and
  a rules grid where each cell is an expression keyed by column ID.
- **Function** — name and a JavaScript expression evaluated against
  `input` (CodeMirror, dark variant).

Press `Esc` or click the inspector's `×` to close it.

**Save.** Type a filename in the toolbar (next to "Name"), then click
**Save**. The browser downloads `<name>.json`.

**Load.** Click **Load** in the toolbar and pick a JSON file. The
inspector closes; the canvas re-renders with the loaded graph and the
name field updates to the file's basename.

**Reset.** Click **Reset** to clear the canvas.

## File format

Saved files are plain JSON:

```json
{
  "contentType": "application/vnd.gorules.decision",
  "nodes": [
    {
      "id": "request",
      "type": "inputNode",
      "name": "Request",
      "position": { "x": 100, "y": 160 }
    }
  ],
  "edges": [
    {
      "id": "edge_a",
      "type": "edge",
      "sourceId": "request",
      "targetId": "table"
    }
  ]
}
```

`type` on a node is one of `inputNode`, `outputNode`, `decisionTableNode`,
`functionNode`. `content` (optional) carries type-specific data —
`{ expression: string }` for function nodes, the full decision-table
structure for table nodes, an arbitrary schema for I/O nodes.

The sample at `public/example-rules.json` is a realistic example —
a de-minimis transaction-limits decision table with three rules.

## Project layout

```text
atomic-fi-web/
├── public/
│   └── example-rules.json     # sample, auto-loaded
└── src/
    ├── main.tsx, index.css    # entry + design tokens
    ├── App.tsx                # state shell
    └── workflow/
        ├── types.ts           # graph + on-disk types
        ├── serialize.ts       # load / save / parseWorkflow
        ├── Toolbar.tsx
        ├── NodePalette.tsx
        ├── Canvas.tsx         # React Flow host
        ├── nodes/             # canvas node components
        └── inspector/         # right-side editor + per-type forms
```

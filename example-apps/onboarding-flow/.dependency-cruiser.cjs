/** @type {import('dependency-cruiser').IConfiguration} */
module.exports = {
  forbidden: [
    {
      name: "no-circular",
      severity: "error",
      comment: "Circular dependencies cause bundle bloat and init-order bugs",
      from: { pathNot: ["packages/sdk/"] },
      to: { circular: true },
    },
    {
      name: "no-orphans",
      severity: "warn",
      comment: "Files not reachable from entry points are dead code",
      from: { orphan: true, pathNot: ["\\.(test|spec)\\.", "__tests__", "vite-env\\.d\\.ts"] },
      to: {},
    },
    {
      name: "ui-no-import-pages",
      severity: "error",
      comment: "UI components must not import from pages (inversion of control)",
      from: { path: "^src/components/ui/" },
      to: { path: "^src/pages/" },
    },
    {
      name: "ui-no-import-onboarding",
      severity: "error",
      comment: "Base UI must not depend on feature components",
      from: { path: "^src/components/ui/" },
      to: { path: "^src/components/onboarding/" },
    },
  ],
  options: {
    doNotFollow: { path: "node_modules" },
    tsPreCompilationDeps: true,
    tsConfig: { fileName: "tsconfig.app.json" },
    enhancedResolveOptions: {
      exportsFields: ["exports"],
      conditionNames: ["import", "require", "node", "default"],
    },
    reporterOptions: {
      text: { highlightFocused: true },
    },
  },
};

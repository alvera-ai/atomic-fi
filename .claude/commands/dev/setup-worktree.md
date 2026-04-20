---
name: setup-worktree
description: Set up a git worktree with dedicated DB names, ports, and .env for test isolation
when_to_use:
  - Setting up a new git worktree for parallel development
  - Preparing a worktree for running tests without colliding with main repo
  - After creating a worktree with EnterWorktree or `git worktree add`
related_guides:
  - guides/cheatsheet/developer_guide.cheatmd
  - guides/cheatsheet/quality_gates.cheatmd
related_commands:
  - /qa:quality-checks (run once the worktree is bootstrapped)
---

> **Naming conventions live in user memory**, not a guide file —
> DB suffix / Erlang node / port-prefix formula are established by
> precedent across worktrees. The procedure below is self-contained;
> no external guide lookup required.

# Set Up Git Worktree with Isolated DB and Ports

This skill bootstraps a git worktree with dedicated database names, ports, and `.env` so it can run tests and dev server without colliding with the main repo or other worktrees.

## Prerequisites

- You must be inside a git worktree (not the main repo)
- The main repo's `config/test.secret.exs` must exist as the reference template

## Procedure

### Step 1: Detect worktree name and compute naming

1. Get the worktree name from the basename of the current working directory
2. Compute the DB suffix: replace hyphens with underscores, prefix with `_`
   - Example: `quirky-hawking` → `_quirky_hawking`
3. Compute the port prefix:
   - Run `git worktree list | wc -l` to count all worktrees (including main)
   - Subtract 1 (main) to get the non-main worktree count
   - Port prefix = `4 + count`
   - Example: 2 total worktrees → 1 non-main → prefix `5` → dev: 5001, test: 5003, debugger: 5007
4. Compute the Erlang node suffix: same as DB suffix (e.g. `_quirky_hawking`)

### Step 2: Read the main repo's `config/test.secret.exs`

Read the file from the main repo (find it via `git worktree list` — the bare/main entry). This is the reference template containing pool sizes, timeouts, and all repo configurations.

### Step 3: Generate `config/test.secret.exs`

Create `config/test.secret.exs` in the worktree by copying the main repo's version with these modifications:

**Database name changes** — append the DB suffix to every database name. The pattern is to insert the suffix BEFORE any `MIX_TEST_PARTITION` interpolation:
- `"platform_test#{...}"` → `"platform_test{{suffix}}#{...}"`
- `"platform_regulated_test#{...}"` → `"platform_regulated_test{{suffix}}#{...}"`
- `"platform_datalake_test#{...}"` → `"platform_datalake_test{{suffix}}#{...}"`
- `"platform_regulated_datalake_test#{...}"` → `"platform_regulated_datalake_test{{suffix}}#{...}"`
- And all industry-specific variants: healthcare, core_banking, alvera, payment_risk, service_commerce, subscription, trading, accounts_receivable (both public and regulated)

**Endpoint port change** — update the default port in the `PaymentCompliancePlatformWeb.Endpoint` config:
- `System.get_env("PORT") || "4003"` → `System.get_env("PORT") || "{{test_port}}"`
- Where `{{test_port}}` = `N003` (e.g. `5003` for prefix 5)

**Everything else stays identical** — pool sizes, timeouts, max_overflow, bcrypt rounds, billing config, etc.

### Step 4: Generate `config/dev.secret.exs`

Read the main repo's `config/dev.secret.exs` and create a copy with:
- `"alvera_dev"` → `"alvera_dev{{suffix}}"`
- `"alvera_regulated_dev"` → `"alvera_regulated_dev{{suffix}}"`

### Step 5: Generate `.env`

Create `.env` in the worktree root:
```
PORT={{dev_port}}
NODE_NAME=platform{{suffix}}@localhost
CONSOLE_NODE=console{{suffix}}@localhost
LIVE_DEBUGGER_PORT={{debugger_port}}
```

Where:
- `{{dev_port}}` = `N001` (e.g. `5001`)
- `{{debugger_port}}` = `N007` (e.g. `5007`)

### Step 6: Build and DB setup

Run the following commands (NOT in background — these must complete before tests):

```bash
zsh -l -c 'source ~/.zshrc && mix deps.clean platform --build && MIX_ENV=test mix ecto.reset' 2>&1 | tee /tmp/{{worktree_name}}-db-setup.txt
```

Wait for this to complete successfully. Check the output for errors.

### Step 7: Run baseline tests

Run in two separate passes — never `mix test` in one shot:

**Pass 1 — core tests** (fast, parallel):
```bash
zsh -l -c 'source ~/.zshrc && MIX_ENV=test mix test.core' 2>&1 | tee /tmp/{{worktree_name}}-baseline-core.txt
```

**Pass 2 — DDL/heavy tests** (max-cases 4 to avoid PG lock contention):
```bash
zsh -l -c 'source ~/.zshrc && MIX_ENV=test mix test.ddls --max-cases 4' 2>&1 | tee /tmp/{{worktree_name}}-baseline-ddls.txt
```

Report the test results (pass/fail/excluded counts) for each pass separately.

## Important Notes

- **Pool settings must match the main repo** — never modify pool sizes, timeouts, or max_overflow. The worktree uses the same machine resources.
- **PORT override is preserved** — `PORT=x mix test` always works because the endpoint reads from `System.get_env("PORT")`.
- **All 3 files are gitignored** — `test.secret.exs`, `dev.secret.exs`, and `.env` are in `.gitignore` and will not be committed.
- **NEVER run mix ecto.reset in background/async mode** — it must complete synchronously.
- **Always use `zsh -l -c 'source ~/.zshrc && ...'`** for shell commands (sandbox PATH doesn't include asdf).

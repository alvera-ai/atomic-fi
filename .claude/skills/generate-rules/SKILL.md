---
name: generate-rules
description: Turns a list of regulation URLs into per-rule proofs (JDM rule + NDJSON corpus + proof.md) and combines them into a single regulator-readable master.md. Use whenever the user wants to "prove these regulations", "generate rules from URLs", "build proofs for CFR/USC/PDF links", or any phrasing that maps multiple regulation sources to end-to-end deterministic proofs. Orchestrates scenario-author and corpus-from-rule per URL, then concatenates all proofs into benchmarks/correctness/master.md. Never auto-commits.
---

# generate-rules

Turn a list of regulation URLs into per-rule proofs — one vertical slice per URL — then combine all proofs into a single regulator-readable `benchmarks/correctness/master.md`.

You are the orchestrator. For each URL you delegate to `scenario-author`. Your job is sequencing, progress tracking, and the final concatenation. **The human reviews and commits — never auto-commit.**

---

## Invocation

```
/generate-rules --urls <comma-separated URLs>
/generate-rules --file <path to file with one URL per line>
```

URLs may be eCFR links, USC links, PDF links (HTTP or local), or local file paths.

---

## Workflow

```
1. PARSE       →  Extract URL list. Validate. Deduplicate. Print and confirm with user.
2. LOOP        →  For each URL, sequentially:
                   a. FETCH    — Use the source-specific strategy below
                   b. VALIDATE — Confirm fetched content is regulatory text
                   c. DERIVE   — /scenario-author --regulation <url-or-path>
                                 (produces rule + corpus + proof.md)
                   d. REPORT   — "✓ [N/M] <slug> — proof green" or surface failure
3. COMBINE     →  Concatenate all proof.md files into master.md
4. HANDOFF     →  Surface file list + suggested commit message. DO NOT commit.
```

Sequential — one URL at a time. If a URL's proof fails or scenario-author hits a lockstep guard, **STOP THE ENTIRE LOOP IMMEDIATELY**. Do not proceed to the next URL. Do not attempt to work around the failure. Print the failure reason and ask the user: "Fix/retry this URL, skip it, or abort?"

---

## Step 1 — PARSE

### File-based input (`--file`)
- Strip blank lines
- Strip comment lines (lines starting with `#`)
- Treat remaining lines as URLs or local file paths

### URL normalization and dedup
- Strip trailing slashes before comparison
- Exact string match after normalization — two URLs that differ only by trailing slash are duplicates
- Log which duplicates were removed and why

### URL validation (pre-flight)

Before fetching, do a lightweight check on each URL:

1. **Domain heuristic:** If the domain is NOT in `[ecfr.gov, uscode.house.gov, fincen.gov, ofac.treasury.gov, treasury.gov, congress.gov, law.cornell.edu]` AND the path doesn't end in `.pdf`, **warn the user** that this doesn't look like a regulation source. Still include it if the user confirms.

2. **eCFR path structure:** If domain is `ecfr.gov`, verify the path matches the expected pattern (`/current/title-NN/...`). Flag obvious typos (e.g., `cuitle` instead of `current/title`) and suggest corrections.

3. **Section existence (eCFR only):** Query the eCFR versioner API to confirm the section exists before attempting content fetch:
   ```
   GET https://www.ecfr.gov/api/versioner/v1/versions/title-{N}?part={P}&section={P}.{S}
   ```
   If `result_count: 0`, the section doesn't exist — fail loud immediately with the structure API's table of contents for the part so the user can pick the right section.

Print the final URL list with source types and ask the user to confirm before proceeding.

---

## Step 2a — FETCH (source-specific strategies)

The key insight: most government regulation sites block automated browser-style requests (Cloudflare, CAPTCHAs, timeouts). Each source type has a reliable API or fallback path.

### eCFR (ecfr.gov)

**Do NOT use WebFetch on eCFR HTML URLs — Cloudflare blocks automated access with a 302 redirect to a CAPTCHA page.**

Use the eCFR APIs instead (no CAPTCHA, no Cloudflare):

1. **Renderer API** (preferred — returns full formatted HTML of the section):
   ```
   GET https://www.ecfr.gov/api/renderer/v1/content/enhanced/current/title-{N}/chapter-{C}/part-{P}/section-{P}.{S}
   ```

2. **Versioner XML API** (alternative — returns raw XML with full regulatory text):
   ```
   GET https://www.ecfr.gov/api/versioner/v1/full/{DATE}/title-{N}.xml?part={P}&section={P}.{S}
   ```
   Use today's date or `current` for the latest version.

3. **Search API** (last resort — returns excerpts only, not full text):
   ```
   GET https://www.ecfr.gov/api/search/v1/results?query="{P}.{S}"&per_page=20
   ```

Extract the part number, section number, and chapter from the URL path segments. The URL structure is: `/current/title-{N}/subtitle-{X}/chapter-{C}/part-{P}/subpart-{S}/section-{P}.{SEC}`

### USC (uscode.house.gov)

**uscode.house.gov consistently times out on automated requests.**

Use Cornell Law Institute as the primary source:
```
https://www.law.cornell.edu/uscode/text/{title}/{section}
```

Extract title and section from the House.gov URL's `granuleid` parameter (e.g., `USC-prelim-title31-section5324` → title 31, section 5324).

### PDF links (fincen.gov, ofac.treasury.gov, etc.)

**WebFetch times out on government PDF downloads.** Use curl instead:

```bash
curl -L -o /tmp/{slug}.pdf --max-time 120 "{url}"
file /tmp/{slug}.pdf  # Verify it's actually a PDF, not an HTML error page
```

Then use the `Read` tool on the downloaded PDF (with page ranges for large documents).

If curl also times out or returns a non-PDF (e.g., a 404 HTML page), fail loud — do not attempt to reconstruct content from web search.

### Local file paths

Use the `Read` tool directly. Resolve relative paths against the project root (`/Users/aniketsingh/work/orza/atomic-fi/`). If the file doesn't exist, fail loud.

---

## Step 2b — VALIDATE

After fetching, confirm the content is actually regulatory text before delegating:

- Does it contain legal citations (CFR, USC, FR references)?
- Does it contain regulatory language (shall, must, required, prohibited)?
- Does it reference statutory authority?

If the content is clearly non-regulatory (e.g., a search engine homepage, a CAPTCHA page, a 404 error page), classify it as `content_not_regulation` and fail loud:

> **ERROR: URL N (https://...) fetched successfully but contains no regulatory content. Cannot derive slug, rule_type, or regulatory cite. Halting for this URL.**

This is distinct from a fetch failure — the HTTP request succeeded but the content is unusable. The user needs to provide a correct URL.

---

## Step 2c — Delegation

Invoke `scenario-author` in `--regulation` mode. It handles:
1. Deriving slug and rule_type
2. Grounding against `references/payload-schema.md` and `payload.ex`
3. Drafting JDM rule + corpus
4. Proof loop (`mix corpus.validate`) + stability check

**Do not duplicate scenario-author's logic.** Delegate entirely.

---

## Step 3 — Combine

Concatenate proofs into `benchmarks/correctness/master.md`.

See: `references/master-md-format.md`

---

## Error categories

| Category | Trigger | Action |
|----------|---------|--------|
| `fetch_failed` | HTTP error, timeout, CAPTCHA redirect | Fail loud. Surface to user. |
| `section_not_found` | eCFR versioner API returns 0 results | Fail loud. Show part's TOC for user to pick correct section. |
| `content_not_regulation` | Fetched content has no regulatory text | Fail loud. Tell user this isn't a regulation source. |
| `file_not_found` | Local path doesn't exist | Fail loud. |
| `proof_failed` | scenario-author proof loop doesn't converge | Surface to user: fix/retry or skip. |

**Never silently skip, never silently substitute, never reconstruct from web search.** Compliance rules must trace to authoritative sources — a regulator cannot trust rules built from search snippets or substituted sections.

**"STOP" means STOP.** When any step says STOP (lockstep guard, missing payload field, schema drift), you must immediately cease all work, print the exact failure reason, and wait for user input. Do not attempt workarounds, do not try alternative field names, do not continue to the next URL. The user decides what happens next.

---

## Hard rules

- **Sequential URL processing.** Never parallelize — corpus collisions produce non-deterministic results.
- **Delegate to scenario-author.** This skill orchestrates; it does not draft rules or write corpus files.
- **Never auto-commit.**
- **Never skip a failed proof silently.**
- **Never edit proof.md files.** Master.md concatenates them verbatim.
- **No graceful fallbacks.** If a URL can't be fetched or content isn't regulatory, fail loud.
- **No silent substitution.** If a section doesn't exist, do NOT generate a rule from a "nearby" section. Fail and ask the user.
- **No web-search reconstruction.** If a PDF can't be downloaded, do NOT reconstruct its content from search results. Fail and ask the user for a local copy.

---

## Reference files

- **`references/master-md-format.md`** — the master.md output structure

## Related

- [scenario-author](../scenario-author/SKILL.md) — authors the vertical slice per regulation
- [corpus-from-rule](../corpus-from-rule/SKILL.md) — generates corpus from an existing rule
- [guides/verifying_correctness.md](../../../guides/verifying_correctness.md) — the why and where

defmodule AtomicFi.RulesContext do
  @moduledoc """
  Thin filesystem wrapper over the JDM rules directory mounted into the
  ZenRule docker container.

  ZenRule loads every JDM file at boot, watches the directory, and
  hot-reloads on change. atomic-fi never talks to ZenRule about the file
  layout — it just reads / writes JSON files in the mounted volume and
  ZenRule notices.

  Layout (one project per `rule_type`):

      <:code.priv_dir(:atomic_fi)>/zenrule/
        onboarding/                ← project "onboarding"
        transaction-screening/     ← project "transaction-screening"
          de_minimis.json

  Root dir resolves via `:code.priv_dir(:atomic_fi)` so releases see the
  packaged priv dir, not the source-tree path.

  ## Rule-type enum

  `rule_type :: :onboarding | :transaction_screening`. Internal Elixir
  snake_case; the on-disk folder name is the kebab-case slug ZenRule
  exposes as the project key.
  """

  use AtomicFi.LoggerMacro

  alias AtomicFi.SessionContext.Session

  @type rule_type :: :onboarding | :transaction_screening
  @type name :: String.t()
  @type body :: binary()

  @rule_types [:onboarding, :transaction_screening]

  @rules_subdir "zenrule"

  @doc """
  Returns the list of rule filenames for `rule_type` (sorted, just filenames
  — not absolute paths). Non-`.json` entries and dotfiles are skipped.
  """
  @spec list_rules(Session.t(), rule_type()) :: {:ok, [name()]} | {:error, term()}
  def_with_rls_and_logging list_rules(_session, rule_type), log_fields: [:rule_type] do
    rule_type = validate_rule_type!(rule_type)
    dir = type_dir(rule_type)

    case File.ls(dir) do
      {:ok, entries} ->
        names =
          entries
          |> Enum.filter(&json_file?/1)
          |> Enum.sort()

        {:ok, names}

      {:error, :enoent} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Reads the JDM file at `<root>/<rule_type>/<name>` and returns its raw
  bytes. Validates that `name` is a plain filename (no path separators)
  to prevent traversal.
  """
  @spec get_rule(Session.t(), rule_type(), name()) :: {:ok, body()} | {:error, term()}
  def_with_rls_and_logging get_rule(_session, rule_type, name),
    log_fields: [:rule_type, :name] do
    rule_type = validate_rule_type!(rule_type)

    with :ok <- validate_name(name) do
      File.read(Path.join(type_dir(rule_type), name))
    end
  end

  @doc """
  Writes `base64_body` (decoded) to `<root>/<rule_type>/<name>`. Refuses
  to overwrite an existing file — use `update_rule/4` for that.

  Inputs:
    * `session`     — caller session (logged for audit)
    * `rule_type`   — `:onboarding | :transaction_screening`
    * `name`        — bare filename (e.g. `"de_minimis.json"`); no path separators
    * `base64_body` — Base64-encoded raw JDM JSON
  """
  @spec write_rule(Session.t(), rule_type(), name(), binary()) :: :ok | {:error, term()}
  def_with_rls_and_logging write_rule(_session, rule_type, name, base64_body),
    log_fields: [:rule_type, :name] do
    rule_type = validate_rule_type!(rule_type)
    path = Path.join(type_dir(rule_type), name)

    with :ok <- validate_name(name),
         :ok <- refuse_if_exists(path),
         {:ok, bytes} <- decode_base64(base64_body),
         :ok <- File.mkdir_p(Path.dirname(path)) do
      File.write(path, bytes)
    end
  end

  @doc """
  Overwrites `<root>/<rule_type>/<name>` with the decoded `base64_body`.
  Fails with `{:error, :enoent}` if the rule does not exist.
  """
  @spec update_rule(Session.t(), rule_type(), name(), binary()) :: :ok | {:error, term()}
  def_with_rls_and_logging update_rule(_session, rule_type, name, base64_body),
    log_fields: [:rule_type, :name] do
    rule_type = validate_rule_type!(rule_type)
    path = Path.join(type_dir(rule_type), name)

    with :ok <- validate_name(name),
         :ok <- require_exists(path),
         {:ok, bytes} <- decode_base64(base64_body) do
      File.write(path, bytes)
    end
  end

  @doc """
  Deletes `<root>/<rule_type>/<name>`. No-ops when the file is already
  absent (returns `:ok`).
  """
  @spec delete_rule(Session.t(), rule_type(), name()) :: :ok | {:error, term()}
  def_with_rls_and_logging delete_rule(_session, rule_type, name),
    log_fields: [:rule_type, :name] do
    rule_type = validate_rule_type!(rule_type)

    with :ok <- validate_name(name) do
      case File.rm(Path.join(type_dir(rule_type), name)) do
        :ok -> :ok
        {:error, :enoent} -> :ok
        {:error, _} = err -> err
      end
    end
  end

  @doc """
  Returns the on-disk project name (kebab-case slug ZenRule exposes) for a
  rule_type atom.
  """
  @spec project_name(rule_type()) :: String.t()
  def project_name(:onboarding), do: "onboarding"
  def project_name(:transaction_screening), do: "transaction-screening"

  # ── private helpers ────────────────────────────────────────────────────

  defp validate_rule_type!(rule_type) when rule_type in @rule_types, do: rule_type

  defp validate_rule_type!(rule_type),
    do: raise(ArgumentError, "invalid rule_type: #{inspect(rule_type)}")

  defp type_dir(rule_type),
    do: Path.join([:code.priv_dir(:atomic_fi), @rules_subdir, project_name(rule_type)])

  defp validate_name(name) when is_binary(name) do
    if String.contains?(name, ["/", "\\", ".."]) or name == "" do
      {:error, :invalid_name}
    else
      :ok
    end
  end

  defp validate_name(_), do: {:error, :invalid_name}

  defp json_file?(name),
    do: not String.starts_with?(name, ".") and String.ends_with?(name, ".json")

  defp refuse_if_exists(path) do
    if File.exists?(path), do: {:error, :already_exists}, else: :ok
  end

  defp require_exists(path) do
    if File.exists?(path), do: :ok, else: {:error, :enoent}
  end

  defp decode_base64(b64) when is_binary(b64) do
    case Base.decode64(b64) do
      {:ok, bytes} -> {:ok, bytes}
      :error -> {:error, :invalid_base64}
    end
  end

  defp decode_base64(_), do: {:error, :invalid_base64}
end

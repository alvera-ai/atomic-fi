defmodule AtomicFi.EnabledRegimes do
  @moduledoc """
  Hierarchy of `enabled_regimes` resolution.

      config :atomic_fi, :enabled_regimes, [...]
        └─ Tenant         (override ⊆ config)
            └─ AccountHolder  (override ⊆ Tenant)
                ├─ Counterparty    (override ⊆ AH)
                │   └─ PaymentAccount (when pa.counterparty_id IS NOT NULL,
                │                      override ⊆ CP)
                └─ PaymentAccount  (when pa.counterparty_id IS NULL,
                                    override ⊆ AH)

  Each schema declares a private `cast_and_validate_enabled_regimes/1` that
  knows its parent and uses `Ecto.Changeset.prepare_changes/2` to defer the
  parent lookup to insert/update time. The shared logic in this module is:

    * `default/0` — global root, read from config
    * `cast_and_validate/2` — inherit if empty, validate subset if set,
      `add_error/3` on exceed
  """

  import Ecto.Changeset

  @doc """
  Returns the global default regime list, configured via
  `config :atomic_fi, :enabled_regimes, [...]`. Root of the hierarchy.
  """
  @spec default() :: [String.t()]
  def default, do: Application.fetch_env!(:atomic_fi, :enabled_regimes)

  @doc """
  Cast-and-validate the `enabled_regimes` field on `changeset`.

  Explicit signature — caller resolves both the child's intended regimes
  (typically `Ecto.Changeset.get_field(changeset, :enabled_regimes)`) and the
  parent's effective regimes, and passes both in. No hidden `get_field`
  inside the helper.

  - `regimes` is `nil` or `[]`           → put `parent_regimes` on changeset.
  - `regimes` is set and ⊆ `parent_regimes` → keep changeset unchanged.
  - `regimes` exceeds `parent_regimes`   → `add_error/3` with "exceeds parent".
  """
  @spec cast_and_validate(
          Ecto.Changeset.t(),
          [String.t()] | nil,
          [String.t()]
        ) :: Ecto.Changeset.t()
  def cast_and_validate(changeset, regimes, parent_regimes) when is_list(parent_regimes) do
    case regimes do
      empty when empty in [nil, []] ->
        put_change(changeset, :enabled_regimes, parent_regimes)

      override when is_list(override) ->
        if MapSet.subset?(MapSet.new(override), MapSet.new(parent_regimes)) do
          changeset
        else
          add_error(
            changeset,
            :enabled_regimes,
            "exceeds parent",
            extras: Enum.uniq(override -- parent_regimes),
            allowed: parent_regimes
          )
        end
    end
  end
end

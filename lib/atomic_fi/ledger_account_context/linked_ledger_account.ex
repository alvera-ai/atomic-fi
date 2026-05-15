defmodule AtomicFi.LedgerAccountContext.LinkedLedgerAccount do
  @moduledoc """
  Edge in the LedgerAccount tree — one row per `(from, to, type)` triple
  where `type ∈ {:ancestor, :descendant}`. Maintained by the
  `ledger_accounts_propagate_descendant_id` trigger on `ledger_accounts`
  AFTER INSERT, alongside the denormalised `ancestor_ids` /
  `descendant_ids` columns (used by the balance-propagation trigger).

  Purpose is **read-side ergonomics only** — enables idiomatic
  `has_many :linked_ledger_accounts, ...` + `preload([linked_ledger_accounts: :to])`
  traversal from a LedgerAccount to every related LedgerAccount in either
  direction. Application code never writes here.
  """

  use AtomicFi.Schema

  alias AtomicFi.LedgerAccountContext.LedgerAccount

  open_api_property(
    schema: %Schema{type: :string, format: :uuid, readOnly: true},
    key: :from_ledger_account_id
  )

  open_api_property(
    schema: %Schema{type: :string, format: :uuid, readOnly: true},
    key: :to_ledger_account_id
  )

  open_api_property(
    schema: %Schema{
      type: :string,
      enum: ["ancestor", "descendant"],
      readOnly: true,
      description: "Direction of the edge: `from` LA's ancestor / descendant is `to` LA."
    },
    key: :type
  )

  open_api_schema(
    title: "LinkedLedgerAccount",
    description:
      "Edge in the LedgerAccount tree. Read-only — populated by a database trigger " <>
        "on LedgerAccount insert. Application code never writes to this table.",
    required: [],
    properties: [:from_ledger_account_id, :to_ledger_account_id, :type]
  )

  @primary_key false
  @foreign_key_type :binary_id

  typed_schema "linked_ledger_accounts" do
    belongs_to :from, LedgerAccount,
      foreign_key: :from_ledger_account_id,
      primary_key: true

    belongs_to :to, LedgerAccount,
      foreign_key: :to_ledger_account_id,
      primary_key: true

    field :type, Ecto.Enum, values: [:ancestor, :descendant]
  end
end

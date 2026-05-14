defmodule AtomicFi.RuleEngine.Payload do
  @moduledoc """
  Builds the rule engine evaluation context from domain entities.

  Each entity is shaped like its API response (via `ExOpenApiUtils.Mapper`), so
  the rules engine — whether reached over HTTP (`AtomicFi.RuleEngine` today)
  or via an in-process NIF later — sees the same structure clients do. The
  conversion never lives in a context or in the transport.

  For a transaction the context also carries the entity tree (account holder,
  debtor/creditor payment accounts and counterparties) so the rules can resolve
  the ledger accounts in play (a PaymentAccount has one LedgerAccount per payment
  instrument) and key their response by `ledger_account_id`.
  """

  alias AtomicFi.TransactionContext.Transaction

  @typedoc "Plain, JSON-serialisable map handed to the rule engine."
  @type t :: %{optional(atom() | String.t()) => term()}

  @doc "Build the evaluation context for any supported entity."
  @spec from_entity(struct()) :: t()
  def from_entity(%Transaction{} = transaction), do: from_transaction(transaction)
  def from_entity(other) when is_struct(other), do: ExOpenApiUtils.Mapper.to_map(other)

  @doc """
  Context for a transaction evaluation.

  Expects the transaction's debtor/creditor payment accounts, debtor/creditor
  counterparties, and account holder to be preloaded; unloaded or absent
  associations are emitted as `nil`.
  """
  @spec from_transaction(Transaction.t()) :: t()
  def from_transaction(%Transaction{} = transaction) do
    %{
      transaction: map_entity(transaction),
      account_holder: map_entity(transaction.account_holder),
      debtor_payment_account: map_entity(transaction.debtor_payment_account),
      creditor_payment_account: map_entity(transaction.creditor_payment_account),
      debtor_counterparty: map_entity(transaction.debtor_counterparty),
      creditor_counterparty: map_entity(transaction.creditor_counterparty)
    }
  end

  defp map_entity(%Ecto.Association.NotLoaded{}), do: nil
  defp map_entity(nil), do: nil
  defp map_entity(struct), do: ExOpenApiUtils.Mapper.to_map(struct)
end

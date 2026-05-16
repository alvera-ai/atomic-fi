defmodule AtomicFi.Identifier do
  @moduledoc """
  Stripe-style prefixed identifiers for atomic-fi domain entities.

      iex> AtomicFi.Identifier.for(:ah)
      "ah_aBc3def…"

  Backed by [Puid](https://github.com/dingosky/puid_elixir) with collision
  risk of 1 in 10^12 in a population of 10^8 entities (≈14 alphanum chars).

  Used by AH / CP / PA / LE / BO / Txn schemas to fill their `<resource>_number`
  column on insert. The column is the atomic-fi-internal handle; `external_id`
  remains the caller-supplied SoE upsert key.
  """

  use Puid, chars: :alphanum, total: 1.0e8, risk: 1.0e12

  @valid_prefixes ~w(ah cp pa le bo txn)a

  @spec for(atom()) :: String.t()
  def for(prefix) when prefix in @valid_prefixes do
    "#{prefix}_" <> generate()
  end

  @doc """
  Fills `field` on `changeset` with a new prefixed identifier on **insert**
  only — when the underlying record has no id yet. Updates against an
  existing record leave the field alone, even if it's nil there (no spurious
  change-event churn).
  """
  @spec put_default(Ecto.Changeset.t(), atom(), atom()) :: Ecto.Changeset.t()
  def put_default(%Ecto.Changeset{data: %{id: nil}} = changeset, field, prefix)
      when prefix in @valid_prefixes do
    if Ecto.Changeset.get_field(changeset, field) do
      changeset
    else
      Ecto.Changeset.put_change(changeset, field, __MODULE__.for(prefix))
    end
  end

  def put_default(%Ecto.Changeset{} = changeset, _field, _prefix), do: changeset
end

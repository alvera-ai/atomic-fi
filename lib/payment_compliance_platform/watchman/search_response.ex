defmodule PaymentCompliancePlatform.Watchman.SearchResponse do
  @moduledoc """
  Provides struct and type for a SearchResponse
  """

  @type t :: %__MODULE__{
          entities: [PaymentCompliancePlatform.Watchman.Entity.t()] | nil,
          query: PaymentCompliancePlatform.Watchman.Entity.t() | nil
        }

  defstruct [:entities, :query]

  @doc false
  @spec __fields__(atom) :: keyword
  def __fields__(type \\ :t)

  def __fields__(:t) do
    [
      entities: [{PaymentCompliancePlatform.Watchman.Entity, :t}],
      query: {PaymentCompliancePlatform.Watchman.Entity, :t}
    ]
  end
end

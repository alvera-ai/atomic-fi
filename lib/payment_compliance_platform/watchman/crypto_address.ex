defmodule PaymentCompliancePlatform.Watchman.CryptoAddress do
  @moduledoc """
  Provides struct and type for a CryptoAddress
  """

  @type t :: %__MODULE__{address: String.t() | nil, currency: String.t() | nil}

  defstruct [:address, :currency]

  @doc false
  @spec __fields__(atom) :: keyword
  def __fields__(type \\ :t)

  def __fields__(:t) do
    [address: :string, currency: :string]
  end
end

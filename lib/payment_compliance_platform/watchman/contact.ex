defmodule PaymentCompliancePlatform.Watchman.Contact do
  @moduledoc """
  Provides struct and type for a Contact
  """

  @type t :: %__MODULE__{
          emailAddresses: [String.t()] | nil,
          faxNumbers: [String.t()] | nil,
          phoneNumbers: [String.t()] | nil,
          websites: [String.t()] | nil
        }

  defstruct [:emailAddresses, :faxNumbers, :phoneNumbers, :websites]

  @doc false
  @spec __fields__(atom) :: keyword
  def __fields__(type \\ :t)

  def __fields__(:t) do
    [
      emailAddresses: [:string],
      faxNumbers: [:string],
      phoneNumbers: [:string],
      websites: [:string]
    ]
  end
end

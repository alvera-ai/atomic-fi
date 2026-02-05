defmodule PaymentCompliancePlatform.Watchman.Person do
  @moduledoc """
  Provides struct and type for a Person
  """

  @type t :: %__MODULE__{
          altNames: [String.t()] | nil,
          birthDate: Date.t() | nil,
          deathDate: Date.t() | nil,
          gender: String.t() | nil,
          name: String.t() | nil,
          titles: [String.t()] | nil
        }

  defstruct [:altNames, :birthDate, :deathDate, :gender, :name, :titles]

  @doc false
  @spec __fields__(atom) :: keyword
  def __fields__(type \\ :t)

  def __fields__(:t) do
    [
      altNames: [:string],
      birthDate: {:string, "date"},
      deathDate: {:string, "date"},
      gender: :string,
      name: :string,
      titles: [:string]
    ]
  end
end

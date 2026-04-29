defmodule AtomicFi.Watchman.Organization do
  @moduledoc """
  Provides struct and type for a Organization
  """

  @type t :: %__MODULE__{
          altNames: [String.t()] | nil,
          created: Date.t() | nil,
          dissolved: Date.t() | nil,
          name: String.t() | nil
        }

  defstruct [:altNames, :created, :dissolved, :name]

  @doc false
  @spec __fields__(atom) :: keyword
  def __fields__(type \\ :t)

  def __fields__(:t) do
    [altNames: [:string], created: {:string, "date"}, dissolved: {:string, "date"}, name: :string]
  end
end

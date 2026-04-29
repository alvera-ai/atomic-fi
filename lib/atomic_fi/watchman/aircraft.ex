defmodule AtomicFi.Watchman.Aircraft do
  @moduledoc """
  Provides struct and type for a Aircraft
  """

  @type t :: %__MODULE__{
          altNames: [String.t()] | nil,
          built: Date.t() | nil,
          flag: String.t() | nil,
          icaoCode: String.t() | nil,
          model: String.t() | nil,
          name: String.t() | nil,
          serialNumber: String.t() | nil,
          type: String.t() | nil
        }

  defstruct [:altNames, :built, :flag, :icaoCode, :model, :name, :serialNumber, :type]

  @doc false
  @spec __fields__(atom) :: keyword
  def __fields__(type \\ :t)

  def __fields__(:t) do
    [
      altNames: [:string],
      built: {:string, "date"},
      flag: :string,
      icaoCode: :string,
      model: :string,
      name: :string,
      serialNumber: :string,
      type: :string
    ]
  end
end

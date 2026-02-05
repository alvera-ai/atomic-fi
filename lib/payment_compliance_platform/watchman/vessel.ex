defmodule PaymentCompliancePlatform.Watchman.Vessel do
  @moduledoc """
  Provides struct and type for a Vessel
  """

  @type t :: %__MODULE__{
          altNames: [String.t()] | nil,
          built: Date.t() | nil,
          callSign: String.t() | nil,
          flag: String.t() | nil,
          grossRegisteredTonnage: integer | nil,
          imoNumber: String.t() | nil,
          mmsi: String.t() | nil,
          model: String.t() | nil,
          name: String.t() | nil,
          owner: String.t() | nil,
          tonnage: integer | nil,
          type: String.t() | nil
        }

  defstruct [
    :altNames,
    :built,
    :callSign,
    :flag,
    :grossRegisteredTonnage,
    :imoNumber,
    :mmsi,
    :model,
    :name,
    :owner,
    :tonnage,
    :type
  ]

  @doc false
  @spec __fields__(atom) :: keyword
  def __fields__(type \\ :t)

  def __fields__(:t) do
    [
      altNames: [:string],
      built: {:string, "date"},
      callSign: :string,
      flag: :string,
      grossRegisteredTonnage: :integer,
      imoNumber: :string,
      mmsi: :string,
      model: :string,
      name: :string,
      owner: :string,
      tonnage: :integer,
      type: :string
    ]
  end
end

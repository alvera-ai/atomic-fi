defmodule PaymentCompliancePlatform.Watchman.IngestFileResponse do
  @moduledoc """
  Provides struct and type for a IngestFileResponse
  """

  @type t :: %__MODULE__{
          entities: [PaymentCompliancePlatform.Watchman.Entity.t()] | nil,
          fileType: String.t() | nil
        }

  defstruct [:entities, :fileType]

  @doc false
  @spec __fields__(atom) :: keyword
  def __fields__(type \\ :t)

  def __fields__(:t) do
    [entities: [{PaymentCompliancePlatform.Watchman.Entity, :t}], fileType: :string]
  end
end

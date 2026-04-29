defmodule AtomicFi.Watchman.ListInfoResponse do
  @moduledoc """
  Provides struct and type for a ListInfoResponse
  """

  @type t :: %__MODULE__{
          endedAt: Date.t() | nil,
          listHashes: map | nil,
          lists: map | nil,
          startedAt: Date.t() | nil,
          version: String.t() | nil
        }

  defstruct [:endedAt, :listHashes, :lists, :startedAt, :version]

  @doc false
  @spec __fields__(atom) :: keyword
  def __fields__(type \\ :t)

  def __fields__(:t) do
    [
      endedAt: {:string, "date"},
      listHashes: :map,
      lists: :map,
      startedAt: {:string, "date"},
      version: :string
    ]
  end
end

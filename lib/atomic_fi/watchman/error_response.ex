defmodule AtomicFi.Watchman.ErrorResponse do
  @moduledoc """
  Provides struct and type for a ErrorResponse
  """

  @type t :: %__MODULE__{error: String.t() | nil}

  defstruct [:error]

  @doc false
  @spec __fields__(atom) :: keyword
  def __fields__(type \\ :t)

  def __fields__(:t) do
    [error: :string]
  end
end

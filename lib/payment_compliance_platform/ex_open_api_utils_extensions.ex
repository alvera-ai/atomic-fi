defmodule PaymentCompliancePlatform.ExOpenApiUtilsExtensions do
  @moduledoc """
  Protocol implementations extending ExOpenApiUtils for our codebase.

  ## Atom to String Conversion

  The default ExOpenApiUtils.Mapper protocol doesn't convert atoms to strings,
  which causes OpenAPI validation failures when Ecto.Enum fields (like :platform, :customer)
  are returned in API responses.

  This module adds implementations to convert atoms and DateTime structs for JSON serialization.
  """
end

# Convert atoms to strings for JSON serialization
# This is needed because Ecto.Enum fields return atoms, but OpenAPI expects strings
defimpl ExOpenApiUtils.Mapper, for: Atom do
  def to_map(nil), do: nil
  def to_map(true), do: true
  def to_map(false), do: false
  def to_map(atom), do: Atom.to_string(atom)
end

# Convert DateTime structs to ISO8601 string format for OpenAPI validation
defimpl ExOpenApiUtils.Mapper, for: DateTime do
  def to_map(datetime), do: DateTime.to_iso8601(datetime)
end

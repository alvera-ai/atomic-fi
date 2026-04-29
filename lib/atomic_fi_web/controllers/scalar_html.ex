defmodule AtomicFiWeb.ScalarHTML do
  @moduledoc """
  Renders Scalar API documentation templates.
  """
  use AtomicFiWeb, :html

  embed_templates "scalar_html/*"
end

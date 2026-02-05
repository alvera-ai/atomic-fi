defmodule AlveraPhoenixTemplateServerWeb.ScalarHTML do
  @moduledoc """
  Renders Scalar API documentation templates.
  """
  use AlveraPhoenixTemplateServerWeb, :html

  embed_templates "scalar_html/*"
end

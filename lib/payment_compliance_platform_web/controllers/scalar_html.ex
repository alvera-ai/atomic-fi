defmodule PaymentCompliancePlatformWeb.ScalarHTML do
  @moduledoc """
  Renders Scalar API documentation templates.
  """
  use PaymentCompliancePlatformWeb, :html

  embed_templates "scalar_html/*"
end

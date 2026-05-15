defmodule AtomicFiApi.RuleController do
  @moduledoc """
  REST surface over `AtomicFi.RulesContext` — manages JDM rule files
  on the shared volume that the ZenRule docker container reads.

    * `GET    /rules/:rule_type`           — list rule names
    * `GET    /rules/:rule_type/:name`     — read one rule (raw JDM)
    * `PUT    /rules/:rule_type/:name`     — upsert one rule (raw JDM body)
    * `DELETE /rules/:rule_type/:name`     — delete one rule

  `rule_type` is the kebab-case folder slug (`"onboarding"` /
  `"transaction-screening"`) — the same name ZenRule exposes as its
  project key.
  """

  use AtomicFiApi.Controller

  alias AtomicFi.RulesContext

  action_fallback AtomicFiApi.FallbackController

  @rule_types %{
    "onboarding" => :onboarding,
    "transaction-screening" => :transaction_screening
  }

  def index(conn, %{"rule_type" => rule_type_str}) do
    with {:ok, rule_type} <- parse_rule_type(rule_type_str),
         {:ok, names} <- RulesContext.list_rules(conn.assigns.api_session, rule_type) do
      json(conn, %{rules: names})
    end
  end

  def show(conn, %{"rule_type" => rule_type_str, "name" => name}) do
    with {:ok, rule_type} <- parse_rule_type(rule_type_str),
         {:ok, bytes} <- RulesContext.get_rule(conn.assigns.api_session, rule_type, name) do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(200, bytes)
    end
  end

  # PUT takes the raw JDM JSON as the request body. CastAndValidate isn't in
  # this controller's plug chain (no OpenApiSpex schema) so Phoenix has
  # already JSON-decoded the body into `conn.body_params` — re-serialise
  # before writing.
  def update(conn, %{"rule_type" => rule_type_str, "name" => name}) do
    with {:ok, rule_type} <- parse_rule_type(rule_type_str),
         {:ok, bytes} <- encode_body(conn.body_params),
         :ok <- RulesContext.upsert_rule(conn.assigns.api_session, rule_type, name, bytes) do
      send_resp(conn, :no_content, "")
    end
  end

  def delete(conn, %{"rule_type" => rule_type_str, "name" => name}) do
    with {:ok, rule_type} <- parse_rule_type(rule_type_str),
         :ok <- RulesContext.delete_rule(conn.assigns.api_session, rule_type, name) do
      send_resp(conn, :no_content, "")
    end
  end

  defp parse_rule_type(str) when is_map_key(@rule_types, str), do: {:ok, @rule_types[str]}
  defp parse_rule_type(_), do: {:error, :invalid_rule_type}

  defp encode_body(%{} = body), do: Jason.encode(body)
  defp encode_body(_), do: {:error, :invalid_body}
end

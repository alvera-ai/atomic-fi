defmodule AtomicFiWeb.CopilotkitController do
  @moduledoc """
  `POST /api/copilotkit` — CopilotKit Runtime Protocol passthrough.

  The CopilotKit React client (`@copilotkit/runtime-client-gql@1.10.5`)
  fires exactly three GraphQL operations against this endpoint —
  `availableAgents`, `loadAgentState`, `generateCopilotResponse`.
  This controller pattern-matches on `operationName` and dispatches:

    * The two queries return constant JSON (no agents in atomic-fi).
    * The mutation streams `multipart/mixed` chunks per GraphQL
      Incremental Delivery, driven by `AtomicFiWeb.Copilotkit`.

  This endpoint is **not** modeled in atomic-fi's OpenApiSpec — the
  body shape is governed by CopilotKit's GraphQL schema, not by
  atomic-fi. Per the industry convention for protocol passthroughs
  (GitHub /graphql, Stripe webhook receivers, AWS Lambda Proxy,
  Apollo, Hasura) it lives in the web layer (`atomic_fi_web`)
  alongside Page / Scalar / Lotus-embed controllers, NOT in
  `atomic_fi_api` (the REST resource layer). The `/api/docs` page
  renders a one-line description pointing at CopilotKit's docs.

  See `docs/local-dev-architecture.md` §A.4 for the request-path
  trace and the link to the schema source at
  `node_modules/@copilotkit/runtime/__snapshots__/schema/schema.graphql`.
  """

  use AtomicFiWeb, :controller

  def create(conn, %{"operationName" => "availableAgents"}) do
    json(conn, %{"data" => %{"availableAgents" => %{"agents" => []}}})
  end

  def create(
        conn,
        %{
          "operationName" => "loadAgentState",
          "variables" => %{"data" => %{"threadId" => thread_id}}
        }
      ) do
    json(conn, %{
      "data" => %{
        "loadAgentState" => %{
          "threadId" => thread_id,
          "threadExists" => false,
          "state" => "{}",
          "messages" => []
        }
      }
    })
  end

  def create(conn, %{
        "operationName" => "generateCopilotResponse",
        "variables" => %{"data" => data}
      })
      when is_map(data) do
    conn
    |> put_resp_content_type("multipart/mixed; boundary=\"-\"")
    |> send_chunked(200)
    |> AtomicFiWeb.Copilotkit.stream_response(data)
  end

  def create(conn, %{"operationName" => op}) do
    conn
    |> put_status(400)
    |> json(%{"errors" => [%{"message" => "Unknown CopilotKit operation: #{op}"}]})
  end

  def create(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{"errors" => [%{"message" => "Missing operationName"}]})
  end
end

defmodule PaymentCompliancePlatformApi.OnboardingController do
  use PaymentCompliancePlatformApi.Controller
  use OpenApiSpex.ControllerSpecs

  alias PaymentCompliancePlatform.OpenApiSchema.AccountHolderRequest
  alias PaymentCompliancePlatform.OpenApiSchema.DecisionResponse
  alias PaymentCompliancePlatform.DecisionContext
  alias PaymentCompliancePlatformApi.Helpers.ApiHelpers
  alias OpenApiSpex.Reference

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true
  action_fallback PaymentCompliancePlatformApi.FallbackController

  tags(["Onboarding"])

  operation(:screen,
    summary: "Screen account holder for onboarding",
    description: """
    Screens an account holder and all interested individuals/companies against sanctions lists.
    Returns a decision with screening results for each entity.
    """,
    request_body: {
      "Account holder to screen",
      "application/json",
      AccountHolderRequest.schema(),
      required: true
    },
    responses: [
      ok: {
        "Decision created",
        "application/json",
        %Reference{"$ref": "#/components/schemas/DecisionResponse"}
      },
      unprocessable_entity: {
        "Validation errors",
        "application/json",
        %Reference{"$ref": "#/components/schemas/ChangesetErrors"}
      },
      service_unavailable: {
        "Watchman service unavailable",
        "application/json",
        %Reference{"$ref": "#/components/schemas/ErrorResponse"}
      }
    ]
  )

  def screen(%{body_params: body_params} = conn, _params) do
    session = conn.assigns.api_session

    case DecisionContext.screen_account_holder(session, body_params) do
      {:ok, decision} ->
        conn
        |> put_status(:ok)
        |> ApiHelpers.json_response(decision, DecisionResponse)

      {:error, :watchman_listinfo_unavailable} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{
          error: "Watchman service unavailable",
          detail: "Unable to retrieve sanctions list information"
        })

      {:error, :watchman_search_unavailable} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{
          error: "Watchman service unavailable",
          detail: "Unable to perform sanctions screening"
        })

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, changeset}
    end
  end
end

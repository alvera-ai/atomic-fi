defmodule PaymentCompliancePlatform.ComplianceScreeningContext.ScreeningWorker do
  @moduledoc """
  Oban worker for asynchronous compliance screening.

  Enqueued automatically when an account holder, beneficial owner, or counterparty
  is created with `chain_screening: true` (the default). Dispatches to the appropriate
  `ComplianceScreeningContext.screen_*/2` function based on the `subject` arg.

  ## Job args

  Account holder screening:
      %{"subject" => "account_holder", "account_holder_id" => uuid, "tenant_id" => uuid}

  Beneficial owner screening:
      %{"subject" => "beneficial_owner", "account_holder_id" => uuid, "beneficial_owner_id" => uuid, "tenant_id" => uuid}

  Counterparty screening:
      %{"subject" => "counterparty", "account_holder_id" => uuid, "counterparty_id" => uuid, "tenant_id" => uuid}
  """

  use Oban.Worker, queue: :compliance_screening, max_attempts: 3

  alias PaymentCompliancePlatform.ComplianceScreeningContext
  alias PaymentCompliancePlatform.Repo
  alias PaymentCompliancePlatform.TenantContext.Tenant

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "subject" => "account_holder",
          "account_holder_id" => account_holder_id,
          "tenant_id" => tenant_id
        }
      }) do
    session = build_session(tenant_id)

    request = %{
      account_holder_id: account_holder_id,
      interested_individuals: [],
      interested_companies: []
    }

    case ComplianceScreeningContext.screen_account_holder(session, request) do
      {:ok, _screenings} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def perform(%Oban.Job{
        args: %{
          "subject" => "beneficial_owner",
          "account_holder_id" => account_holder_id,
          "beneficial_owner_id" => beneficial_owner_id,
          "tenant_id" => tenant_id
        }
      }) do
    session = build_session(tenant_id)

    request = %{
      account_holder_id: account_holder_id,
      beneficial_owner_id: beneficial_owner_id,
      interested_individuals: [],
      interested_companies: []
    }

    case ComplianceScreeningContext.screen_beneficial_owner(session, request) do
      {:ok, _screenings} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def perform(%Oban.Job{
        args: %{
          "subject" => "counterparty",
          "account_holder_id" => account_holder_id,
          "counterparty_id" => counterparty_id,
          "tenant_id" => tenant_id
        }
      }) do
    session = build_session(tenant_id)

    request = %{
      account_holder_id: account_holder_id,
      counterparty_id: counterparty_id,
      interested_individuals: [],
      interested_companies: []
    }

    case ComplianceScreeningContext.screen_counterparty(session, request) do
      {:ok, _screenings} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_session(tenant_id) do
    tenant = Repo.get!(Tenant, tenant_id)
    %{tenant_id: tenant_id, tenant: tenant}
  end
end

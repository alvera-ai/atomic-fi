defmodule AtomicFi.ComplianceScreeningContext.ScreeningWorker do
  @moduledoc """
  Oban worker for asynchronous compliance screening.

  Enqueued automatically when an account holder, beneficial owner, or counterparty
  is created with `chain_screening: true` (the default). Dispatches to the appropriate
  `ComplianceScreeningContext.screen_*/2` function based on the `subject` arg.

  The context is responsible for loading the entity and its linked LegalEntity from
  the database and constructing the Watchman screening input from those records.

  ## Job args

  Account holder screening:
      %{"subject" => "account_holder", "account_holder_id" => uuid, "tenant_id" => uuid}

  Beneficial owner screening:
      %{"subject" => "beneficial_owner", "account_holder_id" => uuid, "beneficial_owner_id" => uuid, "tenant_id" => uuid}

  Counterparty screening:
      %{"subject" => "counterparty", "account_holder_id" => uuid, "counterparty_id" => uuid, "tenant_id" => uuid}
  """

  use Oban.Worker, queue: :compliance_screening, max_attempts: 3

  alias AtomicFi.ComplianceScreeningContext
  alias AtomicFi.Repo
  alias AtomicFi.TenantContext.Tenant

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "subject" => "account_holder",
          "account_holder_id" => account_holder_id,
          "tenant_id" => tenant_id
        }
      }) do
    session = build_session(tenant_id)

    case ComplianceScreeningContext.screen_account_holder(session, %{
           account_holder_id: account_holder_id
         }) do
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

    case ComplianceScreeningContext.screen_beneficial_owner(session, %{
           account_holder_id: account_holder_id,
           beneficial_owner_id: beneficial_owner_id
         }) do
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

    case ComplianceScreeningContext.screen_counterparty(session, %{
           account_holder_id: account_holder_id,
           counterparty_id: counterparty_id
         }) do
      {:ok, _screenings} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_session(tenant_id) do
    # Oban worker runs outside any HTTP session, so explicitly bypass the
    # multi-tenancy guard when loading the tenant by id.
    tenant = Repo.get!(Tenant, tenant_id, skip_multi_tenancy_check: true)
    %{tenant_id: tenant_id, tenant: tenant}
  end
end

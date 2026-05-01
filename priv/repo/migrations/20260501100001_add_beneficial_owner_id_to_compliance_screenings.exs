defmodule AtomicFi.Repo.Migrations.AddBeneficialOwnerIdToComplianceScreenings do
  @moduledoc """
  Adds `beneficial_owner_id` to `compliance_screenings` so screenings produced
  by `POST /api/compliance-screenings/screen-beneficial-owner` can be linked
  back to the beneficial_owner that was screened (and persisted with
  `scope: :beneficial_owner`).

  Soft ref — same shape as the existing `counterparty_id` / `payment_account_id`
  columns. Indexed for the typical "screenings for this BO" query.

  Refs #18.
  """

  use Ecto.Migration

  def change do
    alter table(:compliance_screenings) do
      add :beneficial_owner_id, :binary_id
    end

    create index(:compliance_screenings, [:beneficial_owner_id])
  end
end

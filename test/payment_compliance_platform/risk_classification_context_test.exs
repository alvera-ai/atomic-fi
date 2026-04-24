defmodule PaymentCompliancePlatform.RiskClassificationContextTest do
  use PaymentCompliancePlatform.DataCase

  alias PaymentCompliancePlatform.OpenApiSchema.RiskClassificationRequest
  alias PaymentCompliancePlatform.RiskClassificationContext
  alias PaymentCompliancePlatform.RiskClassificationContext.RiskClassification

  describe "risk_classifications" do
    setup %{tenant: tenant} do
      account_holder = insert(:account_holder, tenant_id: tenant.id)
      %{account_holder: account_holder}
    end

    defp valid_request(account_holder, tenant, overrides \\ %{}) do
      base = %RiskClassificationRequest{
        account_holder_id: account_holder.id,
        risk_level: :medium,
        classification_reason: "Medium complexity KYC",
        effective_from: Date.utc_today(),
        effective_until: nil,
        is_active: true,
        classified_by_user_id: nil,
        compliance_screening_id: nil,
        notes: nil,
        tenant_id: tenant.id
      }

      struct!(base, overrides)
    end

    test "list_risk_classifications/2 returns classifications for the tenant", %{
      session: session,
      account_holder: holder,
      tenant: tenant
    } do
      classification =
        insert(:risk_classification, tenant_id: tenant.id, account_holder_id: holder.id)

      {:ok, {[result], _meta}} = RiskClassificationContext.list_risk_classifications(session)
      assert result.id == classification.id
    end

    test "get_risk_classification!/2 returns classification by id", %{
      session: session,
      account_holder: holder,
      tenant: tenant
    } do
      classification =
        insert(:risk_classification, tenant_id: tenant.id, account_holder_id: holder.id)

      result = RiskClassificationContext.get_risk_classification!(session, classification.id)
      assert result.id == classification.id
    end

    test "create_risk_classification/2 with valid data creates an active classification", %{
      session: session,
      account_holder: holder,
      tenant: tenant
    } do
      request = valid_request(holder, tenant)

      assert {:ok, %RiskClassification{} = classification} =
               RiskClassificationContext.create_risk_classification(session, request)

      assert classification.risk_level == :medium
      assert classification.is_active == true
      assert classification.account_holder_id == holder.id
    end

    test "create_risk_classification/2 deactivates previous active record for same holder", %{
      session: session,
      account_holder: holder,
      tenant: tenant
    } do
      previous =
        insert(:risk_classification,
          tenant_id: tenant.id,
          account_holder_id: holder.id,
          risk_level: :low,
          is_active: true
        )

      request = valid_request(holder, tenant, %{risk_level: :high})

      assert {:ok, new_classification} =
               RiskClassificationContext.create_risk_classification(session, request)

      # New record is active
      assert new_classification.is_active == true
      assert new_classification.risk_level == :high

      # Previous record is now inactive
      reloaded = RiskClassificationContext.get_risk_classification!(session, previous.id)
      assert reloaded.is_active == false
    end

    test "create_risk_classification/2 with is_active: false does not touch other records", %{
      session: session,
      account_holder: holder,
      tenant: tenant
    } do
      existing_active =
        insert(:risk_classification,
          tenant_id: tenant.id,
          account_holder_id: holder.id,
          risk_level: :low,
          is_active: true
        )

      request = valid_request(holder, tenant, %{is_active: false, risk_level: :high})

      assert {:ok, new_classification} =
               RiskClassificationContext.create_risk_classification(session, request)

      assert new_classification.is_active == false

      still_active =
        RiskClassificationContext.get_risk_classification!(session, existing_active.id)

      assert still_active.is_active == true
    end

    test "create_risk_classification/2 rejects effective_until before effective_from", %{
      session: session,
      account_holder: holder,
      tenant: tenant
    } do
      today = Date.utc_today()

      request =
        valid_request(holder, tenant, %{
          effective_from: today,
          effective_until: Date.add(today, -1)
        })

      assert {:error, changeset} =
               RiskClassificationContext.create_risk_classification(session, request)

      assert errors_on(changeset)[:effective_until]
    end

    test "get_active_classification_for_account_holder/2 returns the active row", %{
      session: session,
      account_holder: holder,
      tenant: tenant
    } do
      insert(:risk_classification,
        tenant_id: tenant.id,
        account_holder_id: holder.id,
        is_active: false
      )

      active =
        insert(:risk_classification,
          tenant_id: tenant.id,
          account_holder_id: holder.id,
          is_active: true
        )

      result =
        RiskClassificationContext.get_active_classification_for_account_holder(
          session,
          holder.id
        )

      assert result.id == active.id
    end

    test "update_risk_classification/3 can change fields on an active record", %{
      session: session,
      account_holder: holder,
      tenant: tenant
    } do
      classification =
        insert(:risk_classification,
          tenant_id: tenant.id,
          account_holder_id: holder.id,
          risk_level: :low,
          is_active: true
        )

      request = valid_request(holder, tenant, %{risk_level: :high, is_active: true})

      assert {:ok, updated} =
               RiskClassificationContext.update_risk_classification(
                 session,
                 classification,
                 request
               )

      assert updated.risk_level == :high
      assert updated.is_active == true
    end

    test "update_risk_classification/3 activating an inactive record deactivates the previous active",
         %{session: session, account_holder: holder, tenant: tenant} do
      previous_active =
        insert(:risk_classification,
          tenant_id: tenant.id,
          account_holder_id: holder.id,
          risk_level: :low,
          is_active: true
        )

      inactive =
        insert(:risk_classification,
          tenant_id: tenant.id,
          account_holder_id: holder.id,
          risk_level: :very_high,
          is_active: false
        )

      request = valid_request(holder, tenant, %{risk_level: :very_high, is_active: true})

      assert {:ok, activated} =
               RiskClassificationContext.update_risk_classification(session, inactive, request)

      assert activated.id == inactive.id
      assert activated.is_active == true

      reloaded =
        RiskClassificationContext.get_risk_classification!(session, previous_active.id)

      assert reloaded.is_active == false
    end

    test "delete_risk_classification/2 deletes the record", %{
      session: session,
      account_holder: holder,
      tenant: tenant
    } do
      classification =
        insert(:risk_classification, tenant_id: tenant.id, account_holder_id: holder.id)

      assert {:ok, %RiskClassification{}} =
               RiskClassificationContext.delete_risk_classification(session, classification)

      assert_raise Ecto.NoResultsError, fn ->
        RiskClassificationContext.get_risk_classification!(session, classification.id)
      end
    end

    test "change_risk_classification/2 returns a changeset", %{
      account_holder: holder,
      tenant: tenant
    } do
      classification =
        insert(:risk_classification, tenant_id: tenant.id, account_holder_id: holder.id)

      assert %Ecto.Changeset{} =
               RiskClassificationContext.change_risk_classification(classification)
    end
  end
end

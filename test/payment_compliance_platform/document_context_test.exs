defmodule PaymentCompliancePlatform.DocumentContextTest do
  use PaymentCompliancePlatform.DataCase

  alias PaymentCompliancePlatform.DocumentContext
  alias PaymentCompliancePlatform.DocumentContext.Document
  alias PaymentCompliancePlatform.OpenApiSchema.DocumentRequest
  import PaymentCompliancePlatform.Factory

  describe "documents" do
    test "list_documents/1 returns all documents for tenant", %{session: session} do
      insert(:document, tenant_id: session.tenant_id)
      {:ok, {documents, _meta}} = DocumentContext.list_documents(session)
      assert documents != []
    end

    test "list_documents/1 returns own tenant records", %{session: session} do
      own = insert(:document, tenant_id: session.tenant_id)

      {:ok, {documents, _meta}} = DocumentContext.list_documents(session)
      ids = Enum.map(documents, & &1.id)
      assert own.id in ids
    end

    test "get_document!/2 returns the document with given id", %{session: session} do
      document = insert(:document, tenant_id: session.tenant_id)

      assert %Document{id: id} = DocumentContext.get_document!(session, document.id)
      assert id == document.id
    end

    test "create_document/2 with valid data creates a document", %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      request = %DocumentRequest{
        document_type: :identity_document,
        name: "kyc_passport",
        primary: true,
        account_holder_id: account_holder.id,
        tenant_id: session.tenant_id
      }

      assert {:ok, %Document{} = document} = DocumentContext.create_document(session, request)
      assert document.document_type == :identity_document
      assert document.name == "kyc_passport"
      assert document.primary == true
      assert document.status == :draft
      assert document.account_holder_id == account_holder.id
      assert document.tenant_id == session.tenant_id
    end

    test "create_document/2 with optional fields", %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      request = %DocumentRequest{
        document_type: :proof_of_address,
        name: "utility_bill",
        description: "Recent utility bill",
        status: :submitted,
        primary: true,
        file_key: "uploads/tenants/123/utility_bill.pdf",
        file_name: "utility_bill.pdf",
        file_size: 204_800,
        content_type: "application/pdf",
        document_number: "DOC-2026-001",
        account_holder_id: account_holder.id,
        tenant_id: session.tenant_id
      }

      assert {:ok, %Document{} = document} = DocumentContext.create_document(session, request)
      assert document.document_type == :proof_of_address
      assert document.status == :submitted
      assert document.file_key == "uploads/tenants/123/utility_bill.pdf"
      assert document.file_name == "utility_bill.pdf"
      assert document.file_size == 204_800
      assert document.content_type == "application/pdf"
      assert document.document_number == "DOC-2026-001"
    end

    test "create_document/2 defaults status to :draft when not provided", %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      request = %DocumentRequest{
        document_type: :identity_document,
        name: "kyc_passport",
        primary: true,
        account_holder_id: account_holder.id,
        tenant_id: session.tenant_id
      }

      assert {:ok, %Document{} = document} = DocumentContext.create_document(session, request)
      assert document.status == :draft
    end

    test "create_document/2 with invalid data returns error changeset", %{session: session} do
      request = %DocumentRequest{
        document_type: nil,
        name: nil,
        primary: nil,
        account_holder_id: nil,
        tenant_id: session.tenant_id
      }

      assert {:error, %Ecto.Changeset{}} = DocumentContext.create_document(session, request)
    end

    test "create_document/2 enforces primary uniqueness per (account_holder_id, name)", %{
      session: session
    } do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      request = %DocumentRequest{
        document_type: :identity_document,
        name: "kyc_passport",
        primary: true,
        account_holder_id: account_holder.id,
        tenant_id: session.tenant_id
      }

      assert {:ok, _} = DocumentContext.create_document(session, request)
      assert {:error, changeset} = DocumentContext.create_document(session, request)

      errors = errors_on(changeset)

      assert Map.get(errors, :account_holder_id) ==
               ["a primary document already exists for this account holder and name"] or
               Map.get(errors, :name) ==
                 ["a primary document already exists for this account holder and name"]
    end

    test "create_document/2 allows primary for different names on same account_holder", %{
      session: session
    } do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      req1 = %DocumentRequest{
        document_type: :identity_document,
        name: "kyc_passport",
        primary: true,
        account_holder_id: account_holder.id,
        tenant_id: session.tenant_id
      }

      req2 = %DocumentRequest{
        document_type: :proof_of_address,
        name: "utility_bill",
        primary: true,
        account_holder_id: account_holder.id,
        tenant_id: session.tenant_id
      }

      assert {:ok, _} = DocumentContext.create_document(session, req1)
      assert {:ok, _} = DocumentContext.create_document(session, req2)
    end

    test "create_document/2 rejects secondary without primary", %{session: session} do
      account_holder = insert(:account_holder, tenant_id: session.tenant_id)

      request = %DocumentRequest{
        document_type: :identity_document,
        name: "kyc_passport",
        primary: false,
        account_holder_id: account_holder.id,
        tenant_id: session.tenant_id
      }

      # The trigger uses RAISE EXCEPTION with ERRCODE P0001 — Ecto surfaces this as Postgrex.Error
      # (not Ecto.ConstraintError, which requires a named DB constraint, not a trigger exception)
      assert_raise Postgrex.Error,
                   ~r/documents_primary_required_before_secondary/,
                   fn ->
                     DocumentContext.create_document(session, request)
                   end
    end

    test "update_document/3 with valid data updates the document", %{session: session} do
      document = insert(:document, tenant_id: session.tenant_id)

      request = %DocumentRequest{
        document_type: document.document_type,
        name: document.name,
        status: :submitted,
        primary: document.primary,
        account_holder_id: document.account_holder_id,
        tenant_id: session.tenant_id
      }

      assert {:ok, %Document{} = updated} =
               DocumentContext.update_document(session, document, request)

      assert updated.status == :submitted
    end

    test "update_document/3 with invalid data returns error changeset", %{session: session} do
      document = insert(:document, tenant_id: session.tenant_id)

      request = %DocumentRequest{
        document_type: nil,
        name: nil,
        primary: nil,
        account_holder_id: nil,
        tenant_id: nil
      }

      assert {:error, %Ecto.Changeset{}} =
               DocumentContext.update_document(session, document, request)
    end

    test "delete_document/2 deletes the document", %{session: session} do
      document = insert(:document, tenant_id: session.tenant_id)

      assert {:ok, %Document{}} = DocumentContext.delete_document(session, document)

      assert_raise Ecto.NoResultsError, fn ->
        DocumentContext.get_document!(session, document.id)
      end
    end

    test "change_document/1 returns a document changeset", %{session: session} do
      document = insert(:document, tenant_id: session.tenant_id)

      assert %Ecto.Changeset{} = DocumentContext.change_document(document)
    end
  end
end

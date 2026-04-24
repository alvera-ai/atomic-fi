defmodule PaymentCompliancePlatform.DocumentContext do
  @moduledoc """
  Document context — manages compliance supporting documents for AccountHolders.

  One row per document, linked to an AccountHolder as the MDM subject. Maps to
  ISO 20022 `acmt:007 SupportingDocument` — identity documents, proof of address,
  UBO declarations, and other KYC artefacts submitted during account opening or
  in response to an `acmt:008` Additional Info Request.

  ## Primary Document Rule

  At most one document may be `primary = true` per `(account_holder_id, name)` combination.
  A secondary (`primary = false`) may not be inserted until a primary exists for the same
  combination — enforced at the DB level by a BEFORE INSERT/UPDATE trigger.

  ## File Storage

  Physical files are stored out-of-band (S3/R2 or equivalent). This context stores only
  the storage reference (`file_key`, `file_name`, `content_type`, `file_size`).
  """

  import Ecto.Query, warn: false
  use PaymentCompliancePlatform.LoggerMacro

  alias PaymentCompliancePlatform.DocumentContext.Document
  alias PaymentCompliancePlatform.OpenApiSchema.DocumentRequest
  alias PaymentCompliancePlatform.Repo
  alias PaymentCompliancePlatform.SessionContext.Session

  @doc """
  Returns the list of documents with pagination and filtering.

  Uses Flop for idiomatic filtering, sorting, and pagination.

  ## Examples

      iex> list_documents(session, %{page: 1, page_size: 20})
      {:ok, {[%Document{}, ...], %Flop.Meta{}}}

  """
  @spec list_documents(Session.t(), map()) ::
          {:ok, {list(Document.t()), Flop.Meta.t()}} | {:error, Flop.Meta.t()}
  def_with_rls_and_logging list_documents(session, flop_params \\ %{}),
    log_fields: [:flop_params] do
    Document
    |> Flop.validate_and_run(flop_params,
      for: Document,
      repo: Repo,
      query_opts: [session: session]
    )
  end

  @doc """
  Gets a single document.

  Raises `Ecto.NoResultsError` if the Document does not exist.

  ## Examples

      iex> get_document!(session, "123")
      %Document{}

      iex> get_document!(session, "456")
      ** (Ecto.NoResultsError)

  """
  @spec get_document!(Session.t(), Ecto.UUID.t()) :: Document.t()
  def_with_rls_and_logging get_document!(session, id), log_fields: [:id] do
    Repo.get!(Document, id, session: session)
  end

  @doc """
  Creates a document.

  ## Examples

      iex> create_document(session, %{field: value})
      {:ok, %Document{}}

      iex> create_document(session, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec create_document(Session.t(), DocumentRequest.t()) ::
          {:ok, Document.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging create_document(session, %DocumentRequest{} = request),
    log_fields: [] do
    %Document{}
    |> Document.changeset(request)
    |> Repo.insert(session: session)
  end

  @doc """
  Updates a document.

  ## Examples

      iex> update_document(session, document, %{field: new_value})
      {:ok, %Document{}}

      iex> update_document(session, document, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_document(Session.t(), Document.t(), DocumentRequest.t()) ::
          {:ok, Document.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging update_document(
                             session,
                             %Document{} = document,
                             %DocumentRequest{} = request
                           ),
                           log_fields: [:document] do
    document
    |> Document.changeset(request)
    |> Repo.update(session: session)
  end

  @doc """
  Deletes a document.

  ## Examples

      iex> delete_document(session, document)
      {:ok, %Document{}}

      iex> delete_document(session, document)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete_document(Session.t(), Document.t()) ::
          {:ok, Document.t()} | {:error, Ecto.Changeset.t()}
  def_with_rls_and_logging delete_document(session, %Document{} = document),
    log_fields: [:document] do
    Repo.delete(document, session: session)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking document changes.

  ## Examples

      iex> change_document(document)
      %Ecto.Changeset{data: %Document{}}

  """
  def change_document(%Document{} = document, attrs \\ %{}) do
    Document.changeset(document, attrs)
  end
end

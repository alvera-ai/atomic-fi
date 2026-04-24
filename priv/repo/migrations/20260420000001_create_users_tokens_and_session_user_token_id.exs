defmodule PaymentCompliancePlatform.Repo.Migrations.CreateUsersTokensAndSessionUserTokenId do
  use Ecto.Migration

  def change do
    create table(:users_tokens,
             primary_key: false,
             comment:
               "Hashed Bearer session API tokens (phx.gen.auth pattern). " <>
                 "SHA-256 hash of plaintext token; plaintext is returned to the caller once."
           ) do
      add :id, :binary_id, primary_key: true

      add :token, :binary,
        null: false,
        comment: "SHA-256 hash of the plaintext Bearer token (plaintext never stored)"

      add :context, :string,
        null: false,
        comment: "Token context, e.g. 'user-session-api-token'"

      add :sent_to, :string,
        null: false,
        comment: "Email the token was issued for — token is invalidated if user.email diverges"

      add :user_id, references(:users, on_delete: :delete_all, type: :binary_id),
        null: false,
        comment: "FK to the user this token authenticates"

      # Only inserted_at is tracked — tokens are immutable after creation.
      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create index(:users_tokens, [:user_id])
    create unique_index(:users_tokens, [:context, :token])

    alter table(:sessions) do
      add :user_token_id, references(:users_tokens, on_delete: :delete_all, type: :binary_id),
        comment:
          "FK to the linked UserToken for Bearer sessions. NULL for X-API-Key and cookie sessions."
    end

    create index(:sessions, [:user_token_id])
  end
end

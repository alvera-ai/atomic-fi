defmodule AlveraPhoenixTemplateServer.Repo.Migrations.CreateSessions do
  use Ecto.Migration

  def change do
    create table(:sessions,
             primary_key: false,
             comment:
               "Active authentication sessions for users and API keys with role-based access"
           ) do
      add :id, :binary_id, primary_key: true

      add :type, :string,
        null: false,
        comment: "Session type: 'user' for user sessions or 'api' for API key sessions"

      add :active, :boolean,
        default: true,
        null: false,
        comment: "Whether this session is currently active and valid"

      add :session_token, :binary,
        null: false,
        comment: "Cryptographic session token hash for authentication"

      add :expires_at, :utc_datetime,
        comment: "Expiration timestamp for the session (null for non-expiring sessions)"

      add :metadata, :map,
        default: "{}",
        comment: "Additional session data (IP address, user agent, device info)"

      add :user_id, references(:users, on_delete: :delete_all, type: :binary_id),
        comment: "FK to user (required when type='user', null when type='api')"

      add :api_key_id, references(:api_keys, on_delete: :delete_all, type: :binary_id),
        comment: "FK to API key (required when type='api', null when type='user')"

      add :role_id, references(:roles, on_delete: :delete_all, type: :binary_id),
        null: false,
        comment: "FK to role determining permissions for this session"

      add :tenant_id, references(:tenants, on_delete: :delete_all, type: :binary_id),
        null: false,
        comment: "FK to tenant for multi-tenancy isolation (RLS)"

      timestamps(type: :utc_datetime_usec)
    end

    # Indexes for foreign keys
    create index(:sessions, [:user_id])
    create index(:sessions, [:api_key_id])
    create index(:sessions, [:role_id])
    create index(:sessions, [:tenant_id])

    # Index for session lookup
    create unique_index(:sessions, [:session_token])

    # Index for active sessions
    create index(:sessions, [:active, :expires_at])

    # Check constraint: type must be 'user' or 'api'
    create constraint(:sessions, :valid_type, check: "type IN ('user', 'api')")

    # Check constraint: ensure type matches foreign key
    # If type = 'user', user_id must be NOT NULL and api_key_id must be NULL
    # If type = 'api', api_key_id must be NOT NULL and user_id must be NULL
    create constraint(:sessions, :type_foreign_key_match,
             check:
               "(type = 'user' AND user_id IS NOT NULL AND api_key_id IS NULL) OR " <>
                 "(type = 'api' AND api_key_id IS NOT NULL AND user_id IS NULL)"
           )
  end
end

defmodule AtomicFi.LotusRepo do
  @moduledoc """
  Thin repo wrapper for Lotus dashboard queries.

  Delegates to AtomicFi.Repo with `skip_multi_tenancy_check: true`
  since Lotus needs unscoped access to read schema metadata and
  run ad-hoc SQL queries.
  """

  use Ecto.Repo,
    otp_app: :atomic_fi,
    adapter: Ecto.Adapters.Postgres

  @impl Ecto.Repo
  def default_options(_operation) do
    [skip_multi_tenancy_check: true]
  end
end

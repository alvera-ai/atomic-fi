defmodule AtomicFi.Watchman.Behaviour do
  @moduledoc """
  Behaviour describing the Watchman HTTP client surface used by
  `AtomicFi.DecisionContext.ScreeningEngine`.

  Implemented by `AtomicFi.Watchman.Operations` (real client) and swapped to a
  Mox mock in tests via `Application.compile_env(:atomic_fi, :watchman_client, ...)`.

  See `lib/platform/duck_db_behaviour.ex` in the platform repo for the precedent.
  """

  alias AtomicFi.Watchman.{IngestFileResponse, ListInfoResponse, SearchResponse}

  @callback v2_search_get(opts :: keyword()) ::
              {:ok, SearchResponse.t()}
              | {:error, AtomicFi.Watchman.ErrorResponse.t()}
              | :error

  @callback v2_listinfo_get(opts :: keyword()) ::
              {:ok, ListInfoResponse.t()} | :error

  @callback v2_ingest_file_type_post(
              fileType :: String.t(),
              body :: String.t(),
              opts :: keyword()
            ) :: {:ok, IngestFileResponse.t()} | :error
end

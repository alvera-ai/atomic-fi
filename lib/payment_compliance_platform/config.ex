defmodule PaymentCompliancePlatform.Config do
  @moduledoc """
  Configuration module for PaymentCompliancePlatform.

  This module provides a unified interface for fetching and setting configuration values.
  It supports nested configuration keys and provides default values.
  """

  defmodule Error do
    @moduledoc false
    defexception [:message]
  end

  @app :payment_compliance_platform

  def get(key), do: get(key, nil)

  def get([key], default), do: get(key, default)

  def get([_ | _] = path, default) do
    case fetch(path) do
      {:ok, value} -> value
      :error -> default
    end
  end

  def get(key, default) do
    Application.get_env(@app, key, default)
  end

  def fetch!(key) do
    case fetch(key) do
      {:ok, value} ->
        value

      :error ->
        raise(Error, message: "Missing configuration value: #{inspect(key)}")
    end
  end

  def fetch(key) when is_atom(key), do: fetch([key])

  def fetch([root_key | keys]) do
    Enum.reduce_while(keys, Application.fetch_env(@app, root_key), fn
      key, {:ok, config} when is_map(config) or is_list(config) ->
        case Access.fetch(config, key) do
          :error ->
            {:halt, :error}

          value ->
            {:cont, value}
        end

      _key, _config ->
        {:halt, :error}
    end)
  end

  def put([key], value), do: put(key, value)

  def put([parent_key | keys], value) do
    parent =
      @app
      |> Application.get_env(parent_key, [])
      |> put_in(keys, value)

    Application.put_env(@app, parent_key, parent)
  end

  def put(key, value) do
    Application.put_env(@app, key, value)
  end

  def delete([key]), do: delete(key)

  def delete([parent_key | keys] = path) do
    with {:ok, _} <- fetch(path) do
      {_, parent} =
        parent_key
        |> get()
        |> get_and_update_in(keys, fn _ -> :pop end)

      Application.put_env(@app, parent_key, parent)
    end
  end

  def delete(key) do
    Application.delete_env(@app, key)
  end
end

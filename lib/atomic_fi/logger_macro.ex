defmodule AtomicFi.LoggerMacro do
  @moduledoc """
  Provides logging macros for context functions.

  This module defines macros that wrap function definitions with automatic
  entry/exit logging, trace ID tracking, and exception handling.

  ## Usage

  Use this module in your context:

      use AtomicFi.LoggerMacro

  Then use it to define logged functions:

      def_with_rls_and_logging list_users(session, flop \\\\ %Flop{}), log_fields: [:flop] do
        # function body
      end
  """

  defmacro __using__(_opts) do
    quote do
      require Logger
      import AtomicFi.LoggerMacro, only: [def_with_rls_and_logging: 3]
    end
  end

  @doc """
  Macro for defining public context functions with RLS validation and logging.

  Automatically logs function entry and exit with trace ID for debugging and audit.

  ## Parameters

    * `call` - The function definition (name and arguments)
    * `opts` - Keyword list of options (required):
      * `:log_fields` - List of parameter names to include in logs (required, use [] for no params)
    * `do: block` - The function body

  ## Usage

      def_with_rls_and_logging list_users(session, flop \\\\ %Flop{}), log_fields: [:flop] do
        # function body
      end

  ## Logging

  - Entry: Logs function call with module, function name, trace_id, and specified fields
  - Exit: Logs function return with status (:success/:failure) and trace_id
  - Exception: Logs exception details before rethrowing

  ## Trace ID

  Reads `trace_id` from Logger metadata (set at plug/LiveView mount/Oban job).
  Falls back to generated UUID if not set.

  ## Examples

      # Log with specific fields
      def_with_rls_and_logging list_users(session, flop), log_fields: [:flop] do
        Repo.all(User, session: session)
      end

      # No field logging (explicitly specify empty list)
      def_with_rls_and_logging get_user!(session, id), log_fields: [] do
        Repo.get!(User, id, session: session)
      end
  """
  defmacro def_with_rls_and_logging(call, opts, do: body) do
    {name, _meta, args} = call

    # log_fields is required - will raise if not provided
    log_fields = Keyword.fetch!(opts, :log_fields)

    # Build logging metadata for specified fields
    log_metadata =
      if log_fields == [] do
        []
      else
        Enum.map(log_fields, fn field ->
          # Find the arg that matches this field name
          # Handle both regular args and args with default values
          arg_var =
            Enum.find(args || [], fn
              # Match default parameter: params \\ %{}
              {:\\, _, [{^field, _, _}, _default]} -> true
              # Match regular parameter: params
              {^field, _, _} -> true
              _ -> false
            end)

          case arg_var do
            # Extract variable from default parameter
            {:\\, _, [var, _default]} -> {field, var}
            # Use variable directly
            var when var != nil -> {field, var}
            # No matching argument found
            nil -> {field, nil}
          end
        end)
        |> Enum.filter(fn {_field, var} -> var != nil end)
      end

    quote do
      def unquote(call) do
        # Set trace_id in Logger metadata (generate if not present)
        trace_id = Logger.metadata()[:trace_id] || Ecto.UUID.generate()
        Logger.metadata(trace_id: trace_id)

        function_name = unquote(name)

        # Build params list from log_fields, extracting IDs from Ecto schemas
        params =
          unquote(
            if log_metadata != [] do
              quote do
                [
                  unquote_splicing(
                    for {field, var} <- log_metadata do
                      quote do
                        {unquote(field),
                         AtomicFi.LoggerMacro.extract_loggable_value(unquote(var))}
                      end
                    end
                  )
                ]
              end
            else
              quote do: []
            end
          )

        # Log entry
        Logger.info(msg: "#{function_name}_start", params: params)

        try do
          # Execute function body
          result = unquote(body)

          # Log exit with status and target object ID if applicable
          status =
            AtomicFi.LoggerMacro.extract_result_status(result)

          target_object_id =
            AtomicFi.LoggerMacro.extract_target_object_id(result)

          log_data =
            if target_object_id do
              [msg: "#{function_name}_end", status: status, target_object_id: target_object_id]
            else
              [msg: "#{function_name}_end", status: status]
            end

          Logger.info(log_data)

          result
        rescue
          exception ->
            # Log the exception before rethrowing
            Logger.error(
              msg: "#{function_name}_exception",
              status: :exception,
              exception: Exception.message(exception),
              exception_type: inspect(exception.__struct__)
            )

            # Reraise the exception with original stacktrace
            reraise exception, __STACKTRACE__
        end
      end
    end
  end

  @doc """
  Extracts status from function result for logging.

  Returns :success for {:ok, _} tuples, :failure for {:error, _} tuples,
  or the first element for other tuples. Non-tuple values return :success.

  ## Examples

      iex> extract_result_status({:ok, %User{}})
      :success

      iex> extract_result_status({:error, %Ecto.Changeset{}})
      :failure

      iex> extract_result_status(%User{})
      :success
  """
  def extract_result_status(result) when is_tuple(result) and tuple_size(result) > 0 do
    case elem(result, 0) do
      :ok -> :success
      :error -> :failure
      status -> status
    end
  end

  def extract_result_status(_result), do: :success

  @doc """
  Extracts a loggable value from a parameter.

  If the value is an Ecto schema with an :id field, returns just the ID.
  Otherwise returns the value as-is.

  ## Examples

      iex> extract_loggable_value(%User{id: "123"})
      "123"

      iex> extract_loggable_value("plain_value")
      "plain_value"

  """
  def extract_loggable_value(value) when is_struct(value) do
    if function_exported?(value.__struct__, :__schema__, 1) and
         :id in value.__struct__.__schema__(:fields) do
      Map.get(value, :id)
    else
      value
    end
  end

  def extract_loggable_value(value), do: value

  @doc """
  Extracts target object ID from function result for audit logging.

  If the result is a tuple like {:ok, struct} or {:error, struct} where
  struct is an Ecto schema with an :id field, returns the ID.
  Otherwise returns nil.

  ## Examples

      iex> extract_target_object_id({:ok, %User{id: "123"}})
      "123"

      iex> extract_target_object_id({:error, %Ecto.Changeset{}})
      nil

      iex> extract_target_object_id({:ok, "plain_value"})
      nil

  """
  def extract_target_object_id(result)
      when is_tuple(result) and tuple_size(result) == 2 do
    case elem(result, 1) do
      value when is_struct(value) ->
        if function_exported?(value.__struct__, :__schema__, 1) and
             :id in value.__struct__.__schema__(:fields) do
          Map.get(value, :id)
        else
          nil
        end

      _ ->
        nil
    end
  end

  def extract_target_object_id(_result), do: nil
end

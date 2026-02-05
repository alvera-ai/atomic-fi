defmodule Mix.Tasks.Ecto.Create.Enhanced do
  @shortdoc "Creates the repository storage (enhanced)"

  @moduledoc """
  Enhanced version of mix ecto.create.

  This task is a simple wrapper around the original ecto.create task.
  It provides a consistent interface with ecto.migrate.enhanced.

  Usage:
      $ mix ecto.create.enhanced
      $ MIX_ENV=test mix ecto.create.enhanced
  """

  use Mix.Task

  @impl true
  def run(args) do
    # Clear the task cache to allow running ecto.create
    Mix.Task.clear()

    # Call the original ecto.create task
    Mix.Task.run("ecto.create", args)
  end
end

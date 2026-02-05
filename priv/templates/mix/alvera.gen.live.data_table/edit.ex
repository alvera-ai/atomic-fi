defmodule <%= inspect context.web_module %>.<%= inspect Module.concat(schema.web_namespace, schema.alias) %>Live.Edit do
  use <%= inspect context.web_module %>, :live_view

  alias <%= inspect context.module %>
  alias <%= inspect schema.module %>

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    owner_id = get_owner_id(socket)

    socket
    |> assign(:page_title, "Edit <%= schema.human_singular %>")
    |> assign(:<%= schema.singular %>, <%= inspect context.alias %>.get_<%= schema.singular %>!(id, owner_id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New <%= schema.human_singular %>")
    |> assign(:<%= schema.singular %>, %<%= inspect schema.alias %>{})
  end

  defp get_owner_id(socket) do
    # TODO: Extract owner_id from current_user or current_tenant
    # socket.assigns.current_user.owner_id
    raise "get_owner_id/1 not implemented. Extract from socket.assigns.current_user.owner_id"
  end
end

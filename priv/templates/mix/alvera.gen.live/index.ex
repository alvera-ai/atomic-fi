defmodule <%= inspect context.web_module %>.<%= inspect Module.concat(schema.web_namespace, schema.alias) %>Live.Index do
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

  defp apply_action(socket, :index, _params) do
    owner_id = get_owner_id(socket)

    socket
    |> assign(:page_title, "Listing <%= schema.human_plural %>")
    |> assign(:<%= schema.plural %>, <%= inspect context.alias %>.list_<%= schema.plural %>(owner_id))
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    owner_id = get_owner_id(socket)
    <%= schema.singular %> = <%= inspect context.alias %>.get_<%= schema.singular %>!(id, owner_id)
    {:ok, _} = <%= inspect context.alias %>.delete_<%= schema.singular %>(<%= schema.singular %>)

    socket =
      socket
      |> assign(:<%= schema.plural %>, <%= inspect context.alias %>.list_<%= schema.plural %>(owner_id))
      |> put_flash(:info, "<%= schema.human_singular %> deleted successfully")

    {:noreply, socket}
  end

  defp get_owner_id(socket) do
    # TODO: Extract owner_id from current_user or current_tenant
    # socket.assigns.current_user.owner_id
    # For now, you need to implement this based on your auth setup
    raise "get_owner_id/1 not implemented. Extract from socket.assigns.current_user.owner_id"
  end
end

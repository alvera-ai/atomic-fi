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

  @impl true
  def handle_event("save", %{"<%= schema.singular %>" => <%= schema.singular %>_params}, socket) do
    save_<%= schema.singular %>(socket, socket.assigns.live_action, <%= schema.singular %>_params)
  end

  defp save_<%= schema.singular %>(socket, :edit, <%= schema.singular %>_params) do
    case <%= inspect context.alias %>.update_<%= schema.singular %>(socket.assigns.<%= schema.singular %>, <%= schema.singular %>_params) do
      {:ok, <%= schema.singular %>} ->
        {:noreply,
         socket
         |> put_flash(:info, "<%= schema.human_singular %> updated successfully")
         |> push_navigate(to: ~p"<%= schema.route_prefix %>")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp save_<%= schema.singular %>(socket, :new, <%= schema.singular %>_params) do
    owner_id = get_owner_id(socket)
    <%= schema.singular %>_params = Map.put(<%= schema.singular %>_params, "owner_id", owner_id)

    case <%= inspect context.alias %>.create_<%= schema.singular %>(<%= schema.singular %>_params) do
      {:ok, <%= schema.singular %>} ->
        {:noreply,
         socket
         |> put_flash(:info, "<%= schema.human_singular %> created successfully")
         |> push_navigate(to: ~p"<%= schema.route_prefix %>")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp get_owner_id(socket) do
    # TODO: Extract owner_id from current_user or current_tenant
    # socket.assigns.current_user.owner_id
    # For now, you need to implement this based on your auth setup
    raise "get_owner_id/1 not implemented. Extract from socket.assigns.current_user.owner_id"
  end
end

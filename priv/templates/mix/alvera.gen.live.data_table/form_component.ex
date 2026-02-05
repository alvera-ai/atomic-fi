defmodule <%= inspect context.web_module %>.<%= inspect Module.concat(schema.web_namespace, schema.alias) %>Live.FormComponent do
  use <%= inspect context.web_module %>, :live_component

  alias <%= inspect context.module %>

  @impl true
  def update(%{<%= schema.singular %>: <%= schema.singular %>} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:form, fn ->
       to_form(<%= inspect context.alias %>.change_<%= schema.singular %>(<%= schema.singular %>))
     end)}
  end

  @impl true
  def handle_event("validate", %{"<%= schema.singular %>" => <%= schema.singular %>_params}, socket) do
    changeset =
      socket.assigns.<%= schema.singular %>
      |> <%= inspect context.alias %>.change_<%= schema.singular %>(<%= schema.singular %>_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("save", %{"<%= schema.singular %>" => <%= schema.singular %>_params}, socket) do
    save_<%= schema.singular %>(socket, socket.assigns.action, <%= schema.singular %>_params)
  end

  defp save_<%= schema.singular %>(socket, :edit, <%= schema.singular %>_params) do
    case <%= inspect context.alias %>.update_<%= schema.singular %>(socket.assigns.<%= schema.singular %>, <%= schema.singular %>_params) do
      {:ok, _<%= schema.singular %>} ->
        {:noreply,
         socket
         |> put_flash(:info, "<%= schema.human_singular %> updated successfully")
         |> push_navigate(to: socket.assigns.navigate)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_<%= schema.singular %>(socket, :new, <%= schema.singular %>_params) do
    owner_id = get_owner_id(socket)
    <%= schema.singular %>_params = Map.put(<%= schema.singular %>_params, "owner_id", owner_id)

    case <%= inspect context.alias %>.create_<%= schema.singular %>(<%= schema.singular %>_params) do
      {:ok, _<%= schema.singular %>} ->
        {:noreply,
         socket
         |> put_flash(:info, "<%= schema.human_singular %> created successfully")
         |> push_navigate(to: socket.assigns.navigate)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp get_owner_id(socket) do
    # TODO: Extract owner_id from current_user or current_tenant
    # socket.assigns.current_user.owner_id
    raise "get_owner_id/1 not implemented. Extract from socket.assigns.current_user.owner_id"
  end
end

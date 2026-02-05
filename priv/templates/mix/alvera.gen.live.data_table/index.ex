defmodule <%= inspect context.web_module %>.<%= inspect Module.concat(schema.web_namespace, schema.alias) %>Live.Index do
  use <%= inspect context.web_module %>, :live_view

  alias <%= inspect context.module %>
  alias <%= inspect schema.module %>

  @data_table_opts [
    default_limit: 10,
    default_order: %{
      order_by: [:id, :inserted_at],
      order_directions: [:asc, :asc]
    },
    sortable: [:id, :inserted_at<%= if length(schema.attrs) > 0 do %>, <%= schema.attrs |> Enum.map(fn {k, _v} -> inspect(k) end) |> Enum.join(", ") %><% end %>],
    filterable: [:id, :inserted_at<%= if length(schema.attrs) > 0 do %>, <%= schema.attrs |> Enum.map(fn {k, _v} -> inspect(k) end) |> Enum.join(", ") %><% end %>]
  ]

  @visible_list [
    :inserted_at,
    :action<%= if length(schema.attrs) > 0 do %>,
    <%= schema.attrs |> Enum.map(fn {k, _v} -> inspect(k) end) |> Enum.join(", ") %><% end %>
  ]

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:index_params, nil)
      |> assign(:ai_search_open?, false)
      |> assign(:sql_from_prompt, nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _url, socket) do
    socket =
      socket
      |> assign(:sql_from_prompt, nil)
      |> assign(:ai_search_open?, false)

    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, params) do
    owner_id = get_owner_id(socket)

    socket
    |> assign(:page_title, "Listing <%= schema.human_plural %>")
    |> assign_<%= schema.plural %>(owner_id, params)
    |> assign(:index_params, params)
    |> assign(:visible_list, @visible_list)
  end

  @impl true
  def handle_event("update_filters", %{"filters" => filter_params}, socket) do
    # TODO: Implement DataTable.build_filter_params/2
    # query_params = <%= inspect context.web_module %>.DataTable.build_filter_params(socket.assigns.meta, filter_params)
    {:noreply, push_patch(socket, to: ~p"<%= schema.route_prefix %>?#{filter_params}")}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    owner_id = get_owner_id(socket)
    <%= schema.singular %> = <%= inspect context.alias %>.get_<%= schema.singular %>!(id, owner_id)
    {:ok, _} = <%= inspect context.alias %>.delete_<%= schema.singular %>(<%= schema.singular %>)

    socket =
      socket
      |> assign_<%= schema.plural %>(owner_id, socket.assigns.index_params)
      |> put_flash(:info, "<%= schema.human_singular %> deleted successfully")

    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_ai_query", _params, socket) do
    {:noreply, assign(socket, :ai_search_open?, !socket.assigns.ai_search_open?)}
  end

  @impl true
  def handle_event("export_csv", _params, socket) do
    # TODO: Implement CSV export
    {:noreply, socket}
  end

  defp assign_<%= schema.plural %>(socket, owner_id, params) do
    # TODO: Implement DataTable.search/3 for filtering, sorting, pagination
    # For now, just list all records
    <%= schema.plural %> = <%= inspect context.alias %>.list_<%= schema.plural %>(owner_id, params)

    meta = %{
      current_page: 1,
      total_pages: 1,
      total_count: length(<%= schema.plural %>),
      page_size: 10
    }

    assign(socket, <%= schema.plural %>: <%= schema.plural %>, meta: meta)
  end

  defp get_owner_id(socket) do
    # TODO: Extract owner_id from current_user or current_tenant
    # socket.assigns.current_user.owner_id
    raise "get_owner_id/1 not implemented. Extract from socket.assigns.current_user.owner_id"
  end
end

defmodule <%= inspect context.web_module %>.<%= inspect Module.concat(schema.web_namespace, schema.alias) %>LiveTest do
  use <%= inspect context.web_module %>.ConnCase

  import Phoenix.LiveViewTest
  import <%= inspect context.module %>Fixtures

  @moduletag :refactored

  @create_attrs <%= Mix.Phoenix.to_text(schema.params.create) %>
  @update_attrs <%= Mix.Phoenix.to_text(schema.params.update) %>
  @invalid_attrs <%= Mix.Phoenix.to_text(for {key, _} <- schema.params.create, into: %{}, do: {key, nil}) %>

  defp create_<%= schema.singular %>(_) do
    <%= schema.singular %> = <%= schema.singular %>_fixture()
    %{<%= schema.singular %>: <%= schema.singular %>}
  end

  describe "Index" do
    setup [:create_<%= schema.singular %>]

    test "lists all <%= schema.plural %>", %{conn: conn, <%= schema.singular %>: <%= schema.singular %>} do
      {:ok, _index_live, html} = live(conn, ~p"<%= schema.route_prefix %>")

      assert html =~ "Listing <%= schema.human_plural %>"<%= for {key, val} <- schema.params.create do %>
      assert html =~ to_string(<%= schema.singular %>.<%= key %>)<% end %>
    end

    test "deletes <%= schema.singular %> in listing", %{conn: conn, <%= schema.singular %>: <%= schema.singular %>} do
      {:ok, index_live, _html} = live(conn, ~p"<%= schema.route_prefix %>")

      assert index_live |> element("#<%= schema.plural %>-#{<%= schema.singular %>.id} a", "Delete") |> render_click()
      refute has_element?(index_live, "#<%= schema.singular %>-#{<%= schema.singular %>.id}")
    end
  end

  describe "Edit" do
    setup [:create_<%= schema.singular %>]

    test "displays <%= schema.singular %>", %{conn: conn, <%= schema.singular %>: <%= schema.singular %>} do
      {:ok, _edit_live, html} = live(conn, ~p"<%= schema.route_prefix %>/#{<%= schema.singular %>}")

      assert html =~ "Edit <%= schema.human_singular %>"
    end

    test "saves new <%= schema.singular %>", %{conn: conn} do
      {:ok, edit_live, _html} = live(conn, ~p"<%= schema.route_prefix %>/new")

      assert edit_live
             |> form("#<%= schema.singular %>-form", <%= schema.singular %>: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert edit_live
             |> form("#<%= schema.singular %>-form", <%= schema.singular %>: @create_attrs)
             |> render_submit()

      assert_patch(edit_live, ~p"<%= schema.route_prefix %>")

      html = render(edit_live)
      assert html =~ "<%= schema.human_singular %> created successfully"
    end

    test "updates <%= schema.singular %>", %{conn: conn, <%= schema.singular %>: <%= schema.singular %>} do
      {:ok, edit_live, _html} = live(conn, ~p"<%= schema.route_prefix %>/#{<%= schema.singular %>}")

      assert edit_live
             |> form("#<%= schema.singular %>-form", <%= schema.singular %>: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert edit_live
             |> form("#<%= schema.singular %>-form", <%= schema.singular %>: @update_attrs)
             |> render_submit()

      assert_patch(edit_live, ~p"<%= schema.route_prefix %>")

      html = render(edit_live)
      assert html =~ "<%= schema.human_singular %> updated successfully"
    end
  end
end

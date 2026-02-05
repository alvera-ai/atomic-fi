defmodule <%= inspect context.module %>Test do
  use <%= inspect context.base_module %>.DataCase<%= if schema.binary_id do %>, async: true<% end %>


  alias <%= inspect context.module %>

  describe "<%= schema.plural %>" do
    alias <%= inspect schema.module %>

    @invalid_attrs <%= Mix.Phoenix.to_text for {key, _} <- schema.params, into: %{}, do: {key, nil} %>

    test "list_<%= schema.plural %>/2 returns all <%= schema.plural %>", %{session: session} do
      <%= schema.singular %> = insert(:<%= schema.singular %>, tenant_id: session.tenant_id)
      {:ok, {<%= schema.plural %>, _meta}} = <%= inspect context.alias %>.list_<%= schema.plural %>(session)
      assert Enum.any?(<%= schema.plural %>, fn s -> s.id == <%= schema.singular %>.id end)
    end

    test "get_<%= schema.singular %>!/2 returns the <%= schema.singular %> with given id", %{session: session} do
      <%= schema.singular %> = insert(:<%= schema.singular %>, tenant_id: session.tenant_id)
      assert <%= inspect context.alias %>.get_<%= schema.singular %>!(session, <%= schema.singular %>.id).id == <%= schema.singular %>.id
    end

    test "create_<%= schema.singular %>/2 with valid data creates a <%= schema.singular %>", %{session: session} do
      valid_attrs = params_for(:<%= schema.singular %>, tenant_id: session.tenant_id)

      assert {:ok, %<%= inspect schema.alias %>{} = <%= schema.singular %>} = <%= inspect context.alias %>.create_<%= schema.singular %>(session, valid_attrs)
<%= for {key, value} <- schema.params do %>      assert <%= schema.singular %>.<%= key %> == valid_attrs.<%= key %>
<% end %>    end

    test "create_<%= schema.singular %>/2 with invalid data returns error changeset", %{session: session} do
      assert {:error, %Ecto.Changeset{}} = <%= inspect context.alias %>.create_<%= schema.singular %>(session, @invalid_attrs)
    end

    test "update_<%= schema.singular %>/3 with valid data updates the <%= schema.singular %>", %{session: session} do
      <%= schema.singular %> = insert(:<%= schema.singular %>, tenant_id: session.tenant_id)
      update_attrs = <%= Mix.Phoenix.to_text for {key, value} <- schema.params, into: %{}, do: {key, Mix.Phoenix.Schema.live_form_value(value)} %>

      assert {:ok, %<%= inspect schema.alias %>{} = <%= schema.singular %>} = <%= inspect context.alias %>.update_<%= schema.singular %>(session, <%= schema.singular %>, update_attrs)
<%= for {key, value} <- schema.params do %>      assert <%= schema.singular %>.<%= key %> == <%= Mix.Phoenix.Schema.live_form_value(value) |> inspect %>
<% end %>    end

    test "update_<%= schema.singular %>/3 with invalid data returns error changeset", %{session: session} do
      <%= schema.singular %> = insert(:<%= schema.singular %>, tenant_id: session.tenant_id)
      assert {:error, %Ecto.Changeset{}} = <%= inspect context.alias %>.update_<%= schema.singular %>(session, <%= schema.singular %>, @invalid_attrs)
      assert <%= inspect context.alias %>.get_<%= schema.singular %>!(session, <%= schema.singular %>.id).id == <%= schema.singular %>.id
    end

    test "delete_<%= schema.singular %>/2 deletes the <%= schema.singular %>", %{session: session} do
      <%= schema.singular %> = insert(:<%= schema.singular %>, tenant_id: session.tenant_id)
      assert {:ok, %<%= inspect schema.alias %>{}} = <%= inspect context.alias %>.delete_<%= schema.singular %>(session, <%= schema.singular %>)
      assert_raise Ecto.NoResultsError, fn -> <%= inspect context.alias %>.get_<%= schema.singular %>!(session, <%= schema.singular %>.id) end
    end

    test "change_<%= schema.singular %>/1 returns a <%= schema.singular %> changeset" do
      <%= schema.singular %> = insert(:<%= schema.singular %>)
      assert %Ecto.Changeset{} = <%= inspect context.alias %>.change_<%= schema.singular %>(<%= schema.singular %>)
    end
  end
end

# Add LiveView UI

Generate LiveView UI with Petal Components and data table.

## Usage

```bash
mix alvera.gen.live <Context> <Schema> <plural> [fields] [options]
```

## Options

- `--data_table` - Generate with Flop data table (sorting, filtering, pagination) - **Recommended**
- `--route_root <path>` - Custom route prefix (default: "/")
- `--no-context` - Skip context/schema generation (if already exists)

## Example

```bash
# Generate LiveView with data table
mix alvera.gen.live Accounts User users \
  email:string \
  first_name:string \
  last_name:string \
  --data_table \
  --route_root "/admin"
```

## Generated Files

- `lib/atomic_fi_web/live/user_live/index.ex` (with data table)
- `lib/atomic_fi_web/live/user_live/edit.ex` (instead of show)
- `lib/atomic_fi_web/live/user_live/form_component.ex`
- `lib/atomic_fi_web/live/user_live/index.html.heex`
- `lib/atomic_fi_web/live/user_live/edit.html.heex`
- `lib/atomic_fi_web/live/user_live/form_component.html.heex`
- `test/atomic_fi_web/live/user_live_test.exs`

## Pattern Checklist

### LiveView Index (with Data Table)

```elixir
defmodule AtomicFiWeb.UserLive.Index do
  use AtomicFiWeb, :live_view
  use AtomicFiWeb.ProComponents

  # Authentication hook
  on_mount {AtomicFiWeb.UserOnMountHooks, :require_authenticated_user}

  alias AtomicFi.Accounts
  alias AtomicFi.Accounts.User

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    # Get current tenant from session
    tenant_id = socket.assigns.current_user.owner_id

    # Flop data table
    with {:ok, {users, meta}} <- Accounts.list_users(tenant_id, params) do
      {:noreply,
       socket
       |> assign(:meta, meta)
       |> stream(:users, users, reset: true)
       |> apply_action(socket.assigns.live_action, params)}
    end
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Users")
    |> assign(:user, nil)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New User")
    |> assign(:user, %User{})
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    tenant_id = socket.assigns.current_user.owner_id
    user = Accounts.get_user!(id, tenant_id)
    {:ok, _} = Accounts.delete_user(user)

    {:noreply, stream_delete(socket, :users, user)}
  end
end
```

### LiveView Template (with Petal Components)

```heex
<.header>
  Users
  <:actions>
    <.link patch={~p"/admin/users/new"}>
      <.button>New User</.button>
    </.link>
  </:actions>
</.header>

<.data_table
  id="users-table"
  rows={@streams.users}
  meta={@meta}
  path={~p"/admin/users"}
>
  <:col :let={{_id, user}} label="Email" field={:email}>
    <%= user.email %>
  </:col>
  <:col :let={{_id, user}} label="Name" field={:first_name}>
    <%= user.first_name %> <%= user.last_name %>
  </:col>
  <:col :let={{_id, user}} label="Status" field={:status}>
    <.badge color={status_color(user.status)}>
      <%= user.status %>
    </.badge>
  </:col>
  <:action :let={{_id, user}}>
    <.link navigate={~p"/admin/users/#{user}/edit"}>Edit</.link>
  </:action>
  <:action :let={{id, user}}>
    <.link
      phx-click={JS.push("delete", value: %{id: user.id}) |> hide("##{id}")}
      data-confirm="Are you sure?"
    >
      Delete
    </.link>
  </:action>
</.data_table>

<.modal
  :if={@live_action in [:new, :edit]}
  id="user-modal"
  show
  on_cancel={JS.patch(~p"/admin/users")}
>
  <.live_component
    module={AtomicFiWeb.UserLive.FormComponent}
    id={@user.id || :new}
    user={@user}
    action={@live_action}
    patch={~p"/admin/users"}
  />
</.modal>
```

### Form Component

```elixir
defmodule AtomicFiWeb.UserLive.FormComponent do
  use AtomicFiWeb, :live_component
  use AtomicFiWeb.ProComponents

  alias AtomicFi.Accounts

  @impl true
  def update(%{user: user} = assigns, socket) do
    changeset = Accounts.change_user(user)

    {:ok,
     socket
     |> assign(assigns)
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"user" => user_params}, socket) do
    changeset =
      socket.assigns.user
      |> Accounts.change_user(user_params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"user" => user_params}, socket) do
    save_user(socket, socket.assigns.action, user_params)
  end

  defp save_user(socket, :new, user_params) do
    # Add tenant context
    tenant_id = socket.assigns.current_user.owner_id
    params = Map.put(user_params, "owner_id", tenant_id)

    case Accounts.create_user(params) do
      {:ok, _user} ->
        {:noreply,
         socket
         |> put_flash(:info, "User created successfully")
         |> push_patch(to: socket.assigns.patch)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, %Ecto.Changeset{} = changeset) do
    assign(socket, :form, to_form(changeset))
  end
end
```

### Form Template

```heex
<div>
  <.header>
    <%= @action |> to_string() |> String.capitalize() %> User
  </.header>

  <.simple_form
    for={@form}
    id="user-form"
    phx-target={@myself}
    phx-change="validate"
    phx-submit="save"
  >
    <.input field={@form[:email]} type="email" label="Email" required />
    <.input field={@form[:first_name]} type="text" label="First Name" />
    <.input field={@form[:last_name]} type="text" label="Last Name" />
    <.input field={@form[:phone]} type="text" label="Phone" />
    <.input
      field={@form[:status]}
      type="select"
      label="Status"
      options={[{"Active", "active"}, {"Suspended", "suspended"}]}
    />

    <:actions>
      <.button phx-disable-with="Saving...">Save User</.button>
    </:actions>
  </.simple_form>
</div>
```

## Router Integration

Add routes to `lib/atomic_fi_web/router.ex`:

```elixir
scope "/admin", AtomicFiWeb do
  pipe_through [:browser, :require_authenticated_user]

  live "/users", UserLive.Index, :index
  live "/users/new", UserLive.Index, :new
  live "/users/:id/edit", UserLive.Edit, :edit
  live "/users/bulk-upload", UserLive.Index, :bulk_upload
end
```

## On-Mount Hooks

Hooks are defined in `lib/atomic_fi_web/live/hooks/user_on_mount_hooks.ex`:

- `:require_authenticated_user` - Ensures user is logged in
- `:require_confirmed_user` - Ensures email is confirmed
- `:attach_read_relevant_notifications_hook` - Loads notifications

## Testing Pattern

```elixir
defmodule AtomicFiWeb.UserLiveTest do
  use AtomicFiWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import AtomicFi.AccountsFixtures

  setup :register_and_log_in_user

  describe "Index" do
    test "lists all users", %{conn: conn, user: user} do
      {:ok, _index_live, html} = live(conn, ~p"/admin/users")

      assert html =~ "Users"
      assert html =~ user.email
    end

    test "saves new user", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/admin/users")

      assert index_live |> element("a", "New User") |> render_click() =~
               "New User"

      assert_patch(index_live, ~p"/admin/users/new")

      assert index_live
             |> form("#user-form", user: %{email: "invalid"})
             |> render_change() =~ "must have the @ sign"

      assert index_live
             |> form("#user-form", user: %{email: "new@example.com", first_name: "John"})
             |> render_submit()

      assert_patch(index_live, ~p"/admin/users")

      html = render(index_live)
      assert html =~ "User created successfully"
      assert html =~ "new@example.com"
    end
  end
end
```

## Key Features

- **Data Table**: Flop-powered sorting, filtering, pagination
- **Streaming**: LiveView streams for performance
- **Multi-Tenancy**: Scoped to current user's tenant
- **Authentication**: On-mount hooks enforce auth
- **Form Validation**: Client-side validation with changesets
- **Pro Components**: Petal Components for UI

## Post-Generation Checklist

After successfully generating a LiveView UI, **update the implementation status**:

1. Open [guides/core-modules.md](../../guides/core-modules.md)
2. Update the status table for this context:
   - Mark **LiveView** as ✅ if LiveView components are implemented and tested
   - Update the **Status** score (e.g., from 5/7 to 6/7)
3. Update the **Progress Summary** percentages for LiveView completion
4. Test the UI at the configured route (e.g., http://localhost:4000/admin/users)

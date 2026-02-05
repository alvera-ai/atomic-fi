defmodule <%= inspect context.web_module %>.<%= inspect Module.concat(schema.web_namespace, schema.alias) %>Live.AIComponent do
  use <%= inspect context.web_module %>, :live_component

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:prompt, "")
     |> assign(:loading, false)}
  end

  @impl true
  def handle_event("search", %{"prompt" => prompt}, socket) do
    # TODO: Implement AI search functionality
    # This could integrate with OpenAI, Claude, or your custom AI service
    # to perform semantic search on <%= schema.plural %>

    {:noreply,
     socket
     |> assign(:prompt, prompt)
     |> assign(:loading, true)
     |> push_event("ai-search-started", %{prompt: prompt})}
  end

  @impl true
  def handle_event("clear", _params, socket) do
    send(self(), {:clear_ai_search})
    {:noreply, assign(socket, :prompt, "")}
  end
end

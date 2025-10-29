defmodule ThunderlineWeb.DashboardLive do
  use ThunderlineWeb, :live_view
  require Ash.Query

  # Skip authentication for now
  # on_mount {ThunderlineWeb.LiveUserAuth, :live_user_required}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, agents: [])}
  end

  @impl true
  def handle_event("create_agent", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/agents/new")}
  end

  @impl true
  def handle_event("view_agent", %{"id" => _id}, socket) do
    # TODO: Add agent detail view
    {:noreply, socket}
  end

  defp load_agents(socket) do
    # Skip auth for now - return empty list
    assign(socket, agents: [])
  end
end

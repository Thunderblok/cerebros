defmodule ThunderlineWeb.PageController do
  use ThunderlineWeb, :controller

  def home(conn, _params) do
    # Redirect to dashboard if user is logged in
    if conn.assigns[:current_user] do
      redirect(conn, to: "/dashboard")
    else
      render(conn, :home)
    end
  end

  def redirect_to_dashboard(conn, _params) do
    # Skip authentication - go directly to dashboard
    redirect(conn, to: "/dashboard")
  end

  def index(conn, _params) do
    render(conn, :index)
  end
end

defmodule ThunderlineWeb.PageController do
  use ThunderlineWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end

  def index conn, _params do
    render(conn, :index)
  end
end

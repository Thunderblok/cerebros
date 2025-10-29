defmodule ThunderlineWeb.AshTypescriptRpcController do
  use ThunderlineWeb, :controller

  def run(conn, params) do
    result = AshTypescript.Rpc.run_action(:thunderline, conn, params)
    json(conn, result)
  end

  def validate(conn, params) do
    result = AshTypescript.Rpc.validate_action(:thunderline, conn, params)
    json(conn, result)
  end
end

defmodule DarkorbitWeb.PageController do
  use DarkorbitWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end

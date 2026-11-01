defmodule DarkorbitWeb.GameController do
  use DarkorbitWeb, :controller

  alias DarkorbitWeb.GameAuth

  def show(conn, _params) do
    account = conn.assigns.current_player

    render(conn, :show,
      page_title: "Sector 1-1",
      socket_token: GameAuth.socket_token(account),
      logout_form: Phoenix.Component.to_form(%{}, as: :logout)
    )
  end
end

defmodule DarkorbitWeb.SessionController do
  use DarkorbitWeb, :controller

  alias Darkorbit.Accounts
  alias DarkorbitWeb.GameAuth

  def new(conn, _params) do
    if conn.assigns.current_player do
      redirect(conn, to: ~p"/play")
    else
      render(conn, :new,
        page_title: "Pilot sign in",
        form: Phoenix.Component.to_form(%{"username" => ""}, as: :session)
      )
    end
  end

  def create(conn, %{"session" => %{"username" => username, "password" => password} = params}) do
    case Accounts.login_account(username, password) do
      {:ok, account} ->
        conn
        |> GameAuth.log_in_player(account)
        |> put_flash(:info, "Welcome aboard, #{account.pilot_name}.")
        |> redirect(to: ~p"/play")

      {:error, _reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> put_flash(:error, "Invalid or unverified pilot credentials.")
        |> render(:new,
          page_title: "Pilot sign in",
          form: Phoenix.Component.to_form(Map.delete(params, "password"), as: :session)
        )
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_flash(:error, "Enter a username and password.")
    |> render(:new,
      page_title: "Pilot sign in",
      form: Phoenix.Component.to_form(%{"username" => ""}, as: :session)
    )
  end

  def delete(conn, _params) do
    conn
    |> GameAuth.log_out_player()
    |> put_flash(:info, "Your pilot session has ended.")
    |> redirect(to: ~p"/login")
  end
end

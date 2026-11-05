defmodule DarkorbitWeb.RegistrationController do
  @moduledoc """
  Public pilot onboarding. New accounts cannot sign in until the email address
  has been confirmed. Production signup is enabled only when an actual email
  delivery provider has been configured.
  """

  use DarkorbitWeb, :controller

  require Logger

  alias Darkorbit.Accounts
  alias Darkorbit.Mailer
  alias DarkorbitWeb.RegistrationEmail

  def new(conn, _params) do
    if conn.assigns.current_player do
      redirect(conn, to: ~p"/play")
    else
      render_registration(conn, %{})
    end
  end

  def create(conn, %{"registration" => params}) when is_map(params) do
    if registration_enabled?() do
      case Accounts.register_account(params) do
        {:ok, account} ->
          verification_url =
            DarkorbitWeb.Endpoint.url() <>
              "/verify-account?" <>
              URI.encode_query(%{
                "id" => Integer.to_string(account.id),
                "token" => account.verification["hash"]
              })

          case Mailer.deliver(RegistrationEmail.verification(account, verification_url)) do
            {:ok, _response} ->
              redirect(conn, to: ~p"/register/success")

            {:error, _reason} ->
              Logger.error("Space Nova registration verification email delivery failed")

              conn
              |> put_flash(:error, "Your account was created, but confirmation email delivery failed. Please contact the server operator for activation.")
              |> redirect(to: ~p"/register/success")
          end

        {:error, %Ecto.Changeset{} = changeset} ->
          # Never return a submitted password in HTML (including rejected forms).
          safe_changeset = %{changeset | changes: Map.delete(changeset.changes, :password)}

          conn
          |> put_status(:unprocessable_entity)
          |> render(:new,
            page_title: "Create pilot account",
            registration_enabled: true,
            form: Phoenix.Component.to_form(safe_changeset,
              as: :registration, action: :insert)
          )

        {:error, _reason} ->
          Logger.error("Space Nova registration provisioning failed")

          conn
          |> put_flash(:error, "We couldn't provision your starter ship. Please try again later.")
          |> redirect(to: ~p"/register")
      end
    else
      conn
      |> put_status(:service_unavailable)
      |> render(:new,
        page_title: "Create pilot account",
        registration_enabled: false,
        form: Phoenix.Component.to_form(%{}, as: :registration)
      )
    end
  end

  def create(conn, _params) do
    conn
    |> put_status(:unprocessable_entity)
    |> render(:new,
      page_title: "Create pilot account",
      registration_enabled: registration_enabled?(),
      form: Phoenix.Component.to_form(%{}, as: :registration)
    )
  end

  def success(conn, _params) do
    render(conn, :success, page_title: "Check your inbox")
  end

  def verify(conn, %{"id" => id, "token" => token}) when is_binary(id) and is_binary(token) do
    result =
      case Integer.parse(id) do
        {account_id, ""} when account_id > 0 ->
          Accounts.verify_account(account_id, token)

        _ ->
          {:error, :invalid_link}
      end

    conn =
      conn
      |> put_resp_header("cache-control", "no-store")
      |> put_resp_header("referrer-policy", "no-referrer")

    case result do
      {:ok, _account} ->
        conn
        |> put_flash(:info, "Pilot account verified. You can now establish your uplink.")
        |> redirect(to: ~p"/login")

      _ ->
        conn
        |> put_flash(:error, "This verification link is invalid or has already been used.")
        |> redirect(to: ~p"/login")
    end
  end

  def verify(conn, _params) do
    conn
    |> put_flash(:error, "This verification link is invalid.")
    |> redirect(to: ~p"/login")
  end

  defp render_registration(conn, params) do
    render(conn, :new,
      page_title: "Create pilot account",
      registration_enabled: registration_enabled?(),
      form: Phoenix.Component.to_form(params, as: :registration)
    )
  end

  defp registration_enabled? do
    Application.get_env(:darkorbit_web, :registration_email_enabled, false)
  end
end

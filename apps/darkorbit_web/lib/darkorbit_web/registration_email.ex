defmodule DarkorbitWeb.RegistrationEmail do
  @moduledoc "Email confirmation for newly created Space Nova pilot accounts."

  import Swoosh.Email

  def verification(account, verification_url) when is_binary(verification_url) do
    from_address =
      Application.get_env(:darkorbit_web, :registration_from, "noreply@localhost")

    new()
    |> to(account.email)
    |> from({"Space Nova", from_address})
    |> subject("Confirm your Space Nova pilot account")
    |> text_body("""
    Welcome to Space Nova, #{account.pilot_name}!

    Confirm your email address to activate your pilot account:

    #{verification_url}

    This link expires after 24 hours. Opening it shows a confirmation page;
    activating the account requires selecting Confirm email.
    If it expired or delivery failed, request a replacement at:
    https://spacenova.ddns.net/register/resend

    If you did not request this account, you can ignore this email.
    """)
  end
end

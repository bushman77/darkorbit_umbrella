defmodule Darkorbit.Email.Probe do
  @moduledoc """
  Operator-only outbound email smoke test.

  Call via the running release's `rpc` command, not a public HTTP endpoint.
  This never registers a pilot or changes database state. The live SMTP or
  Resend provider handles actual delivery and may still reject the message.
  """

  import Swoosh.Email

  alias Darkorbit.Mailer

  @recipient_pattern ~r/\A[^\s@]+@[^\s@]+\.[^\s@]+\z/

  @doc """
  Send a single non-sensitive test message through the configured production
  provider. Returns {:ok, :accepted} when the provider accepts the message,
  not proof that it reached the inbox. Never exposes provider error details.
  """
  def send_test(recipient) when is_binary(recipient) do
    recipient = String.trim(recipient)
    configured? = Application.get_env(:darkorbit_web, :email_delivery_configured, false)
    from = Application.get_env(:darkorbit_web, :registration_from)

    cond do
      not Regex.match?(@recipient_pattern, recipient) ->
        {:error, :invalid_recipient}

      not configured? or not is_binary(from) or
          not Regex.match?(@recipient_pattern, from) ->
        {:error, :not_configured}

      true ->
        email =
          new()
          |> to(recipient)
          |> from({"Space Nova", from})
          |> subject("Space Nova email delivery test")
          |> text_body("""
          This is a Space Nova email delivery test.

          Your server accepted an operator request to check outbound email.
          No pilot account was created or changed by this message.

          If you did not request this test, you can ignore it.
          """)

        try do
          case Mailer.deliver(email) do
            {:ok, _receipt} -> {:ok, :accepted}
            _ -> {:error, :delivery_failed}
          end
        rescue
          _ -> {:error, :delivery_failed}
        end
    end
  end

  def send_test(_recipient), do: {:error, :invalid_recipient}
end

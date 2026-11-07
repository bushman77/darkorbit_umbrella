defmodule Darkorbit.Email.ProbeTest do
  use ExUnit.Case, async: false

  import Swoosh.TestAssertions

  alias Darkorbit.Email.Probe

  setup do
    previous = Application.get_env(:darkorbit_web, :email_delivery_configured)
    previous_from = Application.get_env(:darkorbit_web, :registration_from)
    Application.put_env(:darkorbit_web, :registration_from, "sender@example.test")

    on_exit(fn ->
      case previous_from do
        nil -> Application.delete_env(:darkorbit_web, :registration_from)
        address -> Application.put_env(:darkorbit_web, :registration_from, address)
      end

      case previous do
        nil -> Application.delete_env(:darkorbit_web, :email_delivery_configured)
        enabled -> Application.put_env(:darkorbit_web, :email_delivery_configured, enabled)
      end
    end)

    :ok
  end

  test "refuses delivery when a production email provider is not configured" do
    Application.put_env(:darkorbit_web, :email_delivery_configured, false)
    assert {:error, :not_configured} = Probe.send_test("recipient@example.test")
  end

  test "rejects invalid destination email addresses" do
    Application.put_env(:darkorbit_web, :email_delivery_configured, true)
    assert {:error, :invalid_recipient} = Probe.send_test("not an email")
    assert {:error, :invalid_recipient} = Probe.send_test("pilot@example.test\nbcc:someone@example.test")
  end

  test "delivers an operator smoke test using Swoosh.Test without account creation" do
    Application.put_env(:darkorbit_web, :email_delivery_configured, true)

    assert {:ok, :accepted} = Probe.send_test("pilot@example.test")

    assert_email_sent(fn email ->
      assert email.subject == "Space Nova email delivery test"
      assert email.text_body =~ "No pilot account was created"
      assert Enum.any?(email.to, fn {_name, address} ->
               address == "pilot@example.test"
             end)
    end)
  end
end

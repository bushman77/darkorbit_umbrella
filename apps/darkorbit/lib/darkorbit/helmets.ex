defmodule Darkorbit.Helmets do
  @moduledoc """
  Persistent headset credentials. A helmet is a *viewer*, never a pilot.

  Only the SHA-256 digest is stored. Registration credentials do not expire when
  the headset disconnects; they remain valid until the pilot forgets the device.
  """
  alias Darkorbit.Helmets.Device
  alias Darkorbit.Repo

  def device(player_id) when is_integer(player_id) do
    Repo.get_by(Device, player_id: player_id)
  end

  def register(player_id, name \\ "Phone headset") when is_integer(player_id) do
    if device(player_id) do
      {:error, :already_paired}
    else
      credential = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)

      result =
        %Device{}
        |> Device.changeset(%{
          player_id: player_id,
          credential_hash: digest(credential),
          device_name: normalize_name(name)
        })
        |> Repo.insert()

      case result do
        {:ok, saved} -> {:ok, %{device: saved, credential: credential}}
        error -> error
      end
    end
  end

  def authenticate(credential) when is_binary(credential) and byte_size(credential) == 43 do
    if String.match?(credential, ~r/^[A-Za-z0-9_-]{43}$/) do
      case Repo.get_by(Device, credential_hash: digest(credential)) do
        %Device{} = device -> {:ok, device}
        _ -> :error
      end
    else
      :error
    end
  end

  def authenticate(_), do: :error

  def forget(player_id) when is_integer(player_id) do
    case device(player_id) do
      nil -> :ok
      device ->
        {:ok, _deleted} = Repo.delete(device)
        :ok
    end
  end

  defp digest(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)

  defp normalize_name(name) when is_binary(name) do
    case String.trim(name) do
      "" -> "Phone headset"
      trimmed -> String.slice(trimmed, 0, 64)
    end
  end

  defp normalize_name(_), do: "Phone headset"
end

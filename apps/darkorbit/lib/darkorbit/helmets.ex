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

  @doc """
  Return the device's persisted optical alignment, or nil until first save.
  The caller must already have authenticated the helmet's viewer credential.
  """
  def calibration(device_id) when is_integer(device_id) do
    case Repo.get(Device, device_id) do
      %Device{eye_gap_px: gap, eye_sep_mm: sep}
          when is_integer(gap) and is_integer(sep) ->
        %{eye_gap_px: gap, eye_sep_mm: sep}

      _ ->
        nil
    end
  end

  @doc """
  Save both calibration values atomically for an authenticated helmet device.
  Device ID is obtained exclusively from the authenticated Phoenix socket,
  never a client-supplied ID. No new registration or credential is created.
  """
  def save_calibration(device_id, gap, sep)
      when is_integer(device_id) and is_integer(gap) and is_integer(sep) do
    case Repo.get(Device, device_id) do
      %Device{} = device ->
        device
        |> Device.calibration_changeset(%{eye_gap_px: gap, eye_sep_mm: sep})
        |> Repo.update()
        |> case do
          {:ok, saved} ->
            {:ok, %{eye_gap_px: saved.eye_gap_px, eye_sep_mm: saved.eye_sep_mm}}
          {:error, _changeset} ->
            {:error, :invalid_alignment}
        end

      nil ->
        {:error, :revoked}
    end
  end

  def save_calibration(_device_id, _gap, _sep), do: {:error, :invalid_alignment}

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

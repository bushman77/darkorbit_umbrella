defmodule Darkorbit.HelmetsCalibrationTest do
  use Darkorbit.DataCase, async: true

  import Darkorbit.AccountsFixtures
  alias Darkorbit.Helmets

  test "new device is uncalibrated; saved values survive reconnects and are device-scoped" do
    player = verified_player_account_fixture()
    {:ok, %{device: device, credential: credential}} =
      Helmets.register(player.id, "Galaxy S21")

    assert Helmets.calibration(device.id) == nil

    assert {:ok, %{eye_gap_px: -86, eye_sep_mm: 62}} =
             Helmets.save_calibration(device.id, -86, 62)

    assert Helmets.calibration(device.id) == %{eye_gap_px: -86, eye_sep_mm: 62}
    assert {:ok, authenticated} = Helmets.authenticate(credential)
    assert authenticated.id == device.id

    # A new session still reads the same PostgreSQL calibration row.
    assert Helmets.calibration(authenticated.id) == %{eye_gap_px: -86, eye_sep_mm: 62}
  end

  test "out-of-range or partial settings never overwrite valid saved calibration" do
    player = verified_player_account_fixture()
    {:ok, %{device: device}} = Helmets.register(player.id, "Galaxy S21")
    assert {:ok, _} = Helmets.save_calibration(device.id, -30, 64)

    assert {:error, :invalid_alignment} = Helmets.save_calibration(device.id, -161, 64)
    assert {:error, :invalid_alignment} = Helmets.save_calibration(device.id, 81, 64)
    assert {:error, :invalid_alignment} = Helmets.save_calibration(device.id, -30, 39)
    assert {:error, :invalid_alignment} = Helmets.save_calibration(device.id, -30, nil)

    assert Helmets.calibration(device.id) == %{eye_gap_px: -30, eye_sep_mm: 64}
  end

  test "forgetting a headset deletes its calibration together with the credential" do
    player = verified_player_account_fixture()
    {:ok, %{device: device, credential: credential}} =
      Helmets.register(player.id, "Galaxy S21")

    assert {:ok, _} = Helmets.save_calibration(device.id, -42, 61)
    assert :ok = Helmets.forget(player.id)

    assert Helmets.calibration(device.id) == nil
    assert :error = Helmets.authenticate(credential)
    assert {:error, :revoked} = Helmets.save_calibration(device.id, -42, 61)
  end
end

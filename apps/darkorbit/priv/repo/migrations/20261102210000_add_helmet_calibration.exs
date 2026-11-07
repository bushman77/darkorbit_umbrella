defmodule Darkorbit.Repo.Migrations.AddHelmetCalibration do
  use Ecto.Migration

  def change do
    alter table(:helmet_devices) do
      # NULL means the headset has never saved a calibration. Do not overwrite
      # existing phone-local adjustments during this first migration.
      add :eye_gap_px, :integer
      add :eye_sep_mm, :integer
    end

    create constraint(:helmet_devices, :helmet_eye_gap_range,
             check: "eye_gap_px IS NULL OR eye_gap_px BETWEEN -160 AND 80")

    create constraint(:helmet_devices, :helmet_eye_sep_range,
             check: "eye_sep_mm IS NULL OR eye_sep_mm BETWEEN 40 AND 85")

    create constraint(:helmet_devices, :helmet_calibration_complete,
             check: "(eye_gap_px IS NULL) = (eye_sep_mm IS NULL)")
  end
end

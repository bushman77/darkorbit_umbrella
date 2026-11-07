defmodule Core.World.Orientation do
  @moduledoc """
  Server-owned body-local ship orientation. Quaternion coordinates use the
  scene axes X east / Y up / Z south. Initially the nose points along -Z.
  Positive yaw = local -Y, pitch = local +X and roll = local +Z.
  """

  @type t :: %{x: float(), y: float(), z: float(), w: float()}

  @spec identity() :: t()
  def identity, do: %{x: 0.0, y: 0.0, z: 0.0, w: 1.0}

  @spec from_angles(map()) :: t()
  def from_angles(%{yaw: yaw, pitch: pitch, roll: roll}) do
    multiply(multiply(axis_angle(0.0, -1.0, 0.0, yaw),
                      axis_angle(1.0, 0.0, 0.0, pitch)),
             axis_angle(0.0, 0.0, 1.0, roll))
    |> normalize()
  end

  @spec rotate_local(t(), map()) :: t()
  def rotate_local(orientation, angles) do
    orientation |> multiply(from_angles(angles)) |> normalize()
  end

  @spec forward(t()) :: %{x: float(), y: float(), z: float()}
  def forward(orientation) do
    scene = rotate(orientation, %{x: 0.0, y: 0.0, z: -1.0})
    %{x: scene.x, y: scene.z, z: scene.y}
  end

  @spec rotate(t(), map()) :: %{x: float(), y: float(), z: float()}
  def rotate(q, v) do
    tx = 2.0 * (q.y * v.z - q.z * v.y)
    ty = 2.0 * (q.z * v.x - q.x * v.z)
    tz = 2.0 * (q.x * v.y - q.y * v.x)
    %{
      x: v.x + q.w * tx + (q.y * tz - q.z * ty),
      y: v.y + q.w * ty + (q.z * tx - q.x * tz),
      z: v.z + q.w * tz + (q.x * ty - q.y * tx)
    }
  end

  @spec multiply(t(), t()) :: t()
  def multiply(a, b) do
    %{
      x: a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
      y: a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
      z: a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
      w: a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z
    }
  end

  defp axis_angle(x, y, z, angle) do
    s = :math.sin(angle / 2.0)
    %{x: x * s, y: y * s, z: z * s, w: :math.cos(angle / 2.0)}
  end

  defp normalize(q) do
    n = :math.sqrt(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w)
    if n <= 0.0, do: identity(),
      else: %{x: q.x / n, y: q.y / n, z: q.z / n, w: q.w / n}
  end
end

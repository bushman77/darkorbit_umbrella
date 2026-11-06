defmodule Darkorbit.Accounts.Verification do
  @moduledoc """
  Opaque, single-use pilot email verification.

  Only the SHA-256 digest of a random bearer token is persisted. The raw
  token is returned once for email delivery, not stored in the database.
  Resends are bounded per account to prevent continuous token invalidation.
  """

  @lifetime_seconds 24 * 60 * 60
  @resend_cooldown_seconds 60
  @resend_window_seconds 24 * 60 * 60
  @max_resends_per_window 5

  def issue(previous \\ %{}, now \\ System.system_time(:second))
      when is_map(previous) and is_integer(now) do
    token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

    record =
      previous
      |> Map.put("verified", false)
      |> Map.put("hash", digest(token))
      |> Map.put("issued_at", now)
      |> Map.put("expires_at", now + @lifetime_seconds)
      |> Map.delete("verified_at")

    {record, token}
  end

  def valid?(verification, token, now \\ System.system_time(:second))

  def valid?(%{"verified" => false, "hash" => expected, "expires_at" => expires_at}, token, now)
      when is_binary(expected) and is_binary(token) and is_integer(expires_at) and
             is_integer(now) do
    byte_size(expected) == 64 and byte_size(token) <= 512 and
      now < expires_at and :crypto.hash_equals(expected, digest(token))
  end

  def valid?(_verification, _token, _now), do: false

  def verified(verification, now \\ System.system_time(:second)) do
    verification
    |> Map.drop(["hash", "expires_at", "issued_at", "resend_requested_at"])
    |> Map.put("verified", true)
    |> Map.put("verified_at", now)
  end

  def resend_allowed?(verification, now \\ System.system_time(:second))
      when is_map(verification) and is_integer(now) do
    last_request = verification["resend_requested_at"]
    window_start = verification["resend_window_started_at"]
    count = verification["resend_count"]

    cooldown_passed? = not is_integer(last_request) or now - last_request >= @resend_cooldown_seconds
    within_window? = is_integer(window_start) and now - window_start < @resend_window_seconds
    within_limit? = not within_window? or not is_integer(count) or count < @max_resends_per_window

    verification["verified"] != true and cooldown_passed? and within_limit?
  end

  def mark_resend(verification, now \\ System.system_time(:second))
      when is_map(verification) and is_integer(now) do
    window_start = verification["resend_window_started_at"]
    within_window? = is_integer(window_start) and now - window_start < @resend_window_seconds

    verification
    |> Map.put("resend_requested_at", now)
    |> Map.put("resend_window_started_at", if(within_window?, do: window_start, else: now))
    |> Map.put("resend_count", if(within_window?, do: (verification["resend_count"] || 0) + 1, else: 1))
  end

  defp digest(token), do: :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)
end

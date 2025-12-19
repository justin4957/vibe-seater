defmodule VibeSeater.Repo do
  use Ecto.Repo,
    otp_app: :vibe_seater,
    adapter: Ecto.Adapters.Postgres
end

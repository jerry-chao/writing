defmodule Writing.Repo do
  use Ecto.Repo,
    otp_app: :writing,
    adapter: Ecto.Adapters.Postgres
end

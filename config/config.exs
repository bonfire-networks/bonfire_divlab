import Config

#### General configuration useful for tests, everything else should be in `bonfire_divlab.exs` or `Bonfire.Divlab.RuntimeConfig`

# You probably won't want to touch these. You might override some in
# other config files.

config :bonfire, :repo_module, Bonfire.Common.Repo

config :phoenix, :json_library, Jason

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :mime, :types, %{
  "application/activity+json" => ["activity+json"]
}

config :bonfire_divlab, :otp_app, :bonfire_divlab
config :bonfire_common, :otp_app, :bonfire_divlab
config :bonfire_divlab, :repo_module, Bonfire.Common.Repo
config :bonfire_divlab, ecto_repos: [Bonfire.Common.Repo]
config :bonfire_common, :localisation_path, "priv/localisation"

config :bonfire_data_identity, Bonfire.Data.Identity.Credential, hasher_module: Argon2

import_config "bonfire_divlab.exs"
# import_config "#{Mix.env()}.exs"

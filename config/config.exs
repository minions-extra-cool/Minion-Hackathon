# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :minion,
  ecto_repos: [Minion.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

# Configure the endpoint
config :minion, MinionWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: MinionWeb.ErrorHTML, json: MinionWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Minion.PubSub,
  live_view: [signing_salt: "Kd4MTBFJ"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :minion, Minion.Mailer, adapter: Swoosh.Adapters.Local

channels = [
  email: Minion.Channels.Email,
  sms: Minion.Channels.Sms,
  phone: Minion.Channels.Phone
]

config :minion, :channels, channels

config :minion, Oban,
  repo: Minion.Repo,
  queues: Enum.map(channels, fn {name, _module} -> {name, 10} end) ++ [maintenance: 1],
  lifeline: [rescue_after: {2, :minutes}],
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       {"* * * * *", Minion.Alerts.QuietSweepWorker, args: %{schedule_half_minute_run: true}}
     ]}
  ]

config :minion, :kafka,
  brokers: [{"localhost", 19092}],
  events_topic: "events",
  events_partitions: 24,
  dead_letter_topic: "events_dead",
  events_retention_hours: 6

config :minion, :pipeline, enabled: true

config :minion, :kafka_sources, [
  %{topic: "workflow-events", source: "workflow-engine"},
  %{topic: "trade-events", source: "trading-platform"}
]

config :minion, :gemini,
  model: "gemini-2.5-flash",
  base_url: "https://generativelanguage.googleapis.com"

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  minion: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.3",
  minion: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

config :slack_to_html,
  output_dir: "./output",
  excluded_channels: ~w(freenode),
  ga_tracking_id: nil # keep to nil if you don't want GA tracking


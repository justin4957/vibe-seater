defmodule VibeSeater.Sources.Source do
  @moduledoc """
  Represents a data source that can be overlaid with streams.
  Examples: Twitter feed, GitHub repo, Discord channel, etc.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @source_types ~w(twitter github discord reddit tiktok rss custom)

  schema "sources" do
    field(:name, :string)
    field(:source_type, :string)
    field(:source_url, :string)
    field(:config, :map, default: %{})
    field(:active, :boolean, default: true)

    many_to_many(:streams, VibeSeater.Streaming.Stream,
      join_through: VibeSeater.Streaming.StreamSource
    )

    has_many(:stream_sources, VibeSeater.Streaming.StreamSource)
    has_many(:events, VibeSeater.Events.Event)

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(source, attrs) do
    source
    |> cast(attrs, [:name, :source_type, :source_url, :config, :active])
    |> validate_required([:name, :source_type])
    |> validate_inclusion(:source_type, @source_types)
    |> validate_config_for_type()
  end

  defp validate_config_for_type(changeset) do
    source_type = get_field(changeset, :source_type)

    case source_type do
      "twitter" -> validate_twitter_config(changeset)
      "github" -> validate_github_config(changeset)
      "tiktok" -> validate_tiktok_config(changeset)
      _ -> changeset
    end
  end

  defp validate_twitter_config(changeset) do
    config = get_field(changeset, :config, %{})

    if Map.has_key?(config, "hashtag") or Map.has_key?(config, "username") do
      changeset
    else
      add_error(changeset, :config, "must include either hashtag or username for Twitter sources")
    end
  end

  defp validate_github_config(changeset) do
    config = get_field(changeset, :config, %{})

    if Map.has_key?(config, "repo") do
      changeset
    else
      add_error(changeset, :config, "must include repo for GitHub sources")
    end
  end

  defp validate_tiktok_config(changeset) do
    config = get_field(changeset, :config, %{})

    if Map.has_key?(config, "hashtag") or Map.has_key?(config, "username") do
      changeset
    else
      add_error(changeset, :config, "must include either hashtag or username for TikTok sources")
    end
  end
end

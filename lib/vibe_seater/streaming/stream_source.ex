defmodule VibeSeater.Streaming.StreamSource do
  @moduledoc """
  Join table representing the relationship between streams and sources.
  Tracks when a source is actively being monitored for a stream.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "stream_sources" do
    field(:started_at, :utc_datetime_usec)
    field(:ended_at, :utc_datetime_usec)

    belongs_to(:stream, VibeSeater.Streaming.Stream)
    belongs_to(:source, VibeSeater.Sources.Source)

    timestamps(type: :utc_datetime_usec)
  end

  @doc false
  def changeset(stream_source, attrs) do
    stream_source
    |> cast(attrs, [:started_at, :ended_at, :stream_id, :source_id])
    |> validate_required([:started_at, :stream_id, :source_id])
    |> foreign_key_constraint(:stream_id)
    |> foreign_key_constraint(:source_id)
    |> unique_constraint([:stream_id, :source_id])
    |> validate_time_range()
  end

  defp validate_time_range(changeset) do
    started_at = get_field(changeset, :started_at)
    ended_at = get_field(changeset, :ended_at)

    case {started_at, ended_at} do
      {nil, _} ->
        changeset

      {_, nil} ->
        changeset

      {start_time, end_time} ->
        if DateTime.compare(start_time, end_time) == :lt do
          changeset
        else
          add_error(changeset, :ended_at, "must be after started_at")
        end
    end
  end
end

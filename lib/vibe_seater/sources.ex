defmodule VibeSeater.Sources do
  @moduledoc """
  The Sources context manages data sources that can be overlaid with streams.
  """

  import Ecto.Query, warn: false
  alias VibeSeater.Repo
  alias VibeSeater.Sources.Source

  @doc """
  Returns the list of sources.
  """
  def list_sources do
    Repo.all(Source)
  end

  @doc """
  Gets a single source.
  """
  def get_source!(id), do: Repo.get!(Source, id)

  @doc """
  Creates a source.
  """
  def create_source(attrs \\ %{}) do
    %Source{}
    |> Source.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a source.
  """
  def update_source(%Source{} = source, attrs) do
    source
    |> Source.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a source.
  """
  def delete_source(%Source{} = source) do
    Repo.delete(source)
  end

  @doc """
  Lists sources by type.
  """
  def list_sources_by_type(type) do
    Source
    |> where([s], s.source_type == ^type)
    |> Repo.all()
  end

  @doc """
  Lists all active sources.
  """
  def list_active_sources do
    Source
    |> where([s], s.active == true)
    |> Repo.all()
  end

  @doc """
  Activates a source.
  """
  def activate_source(%Source{} = source) do
    update_source(source, %{active: true})
  end

  @doc """
  Deactivates a source.
  """
  def deactivate_source(%Source{} = source) do
    update_source(source, %{active: false})
  end
end

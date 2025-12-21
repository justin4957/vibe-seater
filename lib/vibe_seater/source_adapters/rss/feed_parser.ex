defmodule VibeSeater.SourceAdapters.RSS.FeedParser do
  @moduledoc """
  Parses RSS 2.0, Atom, and RDF feed formats.

  Handles various feed formats and normalizes them to a consistent structure.
  """

  require Logger

  @doc """
  Parses an RSS/Atom feed from XML string.

  Returns `{:ok, %{feed: feed_metadata, items: [items]}}` or `{:error, reason}`.
  """
  def parse(xml_string) when is_binary(xml_string) do
    case parse_xml(xml_string) do
      {:ok, doc} -> extract_feed_data(doc)
      {:error, reason} -> {:error, reason}
    end
  end

  # Private Functions

  defp parse_xml(xml_string) do
    try do
      import SweetXml
      doc = SweetXml.parse(xml_string, dtd: :none)
      {:ok, doc}
    rescue
      e ->
        Logger.error("Failed to parse XML: #{inspect(e)}")
        {:error, :invalid_xml}
    end
  end

  defp extract_feed_data(doc) do
    import SweetXml

    # Detect feed type
    feed_type = detect_feed_type(doc)

    case feed_type do
      :rss -> parse_rss(doc)
      :atom -> parse_atom(doc)
      :rdf -> parse_rdf(doc)
      :unknown -> {:error, :unknown_feed_format}
    end
  end

  defp detect_feed_type(doc) do
    import SweetXml

    cond do
      xpath(doc, ~x"//rss") != nil -> :rss
      xpath(doc, ~x"//feed"e) != nil -> :atom
      xpath(doc, ~x"//rdf:RDF"e) != nil -> :rdf
      true -> :unknown
    end
  end

  # RSS 2.0 Parser
  defp parse_rss(doc) do
    import SweetXml

    feed = %{
      title: xpath(doc, ~x"//channel/title/text()"s),
      description: xpath(doc, ~x"//channel/description/text()"s),
      link: xpath(doc, ~x"//channel/link/text()"s),
      type: :rss
    }

    items =
      doc
      |> xpath(
        ~x"//channel/item"l,
        title: ~x"./title/text()"s,
        link: ~x"./link/text()"s,
        description: ~x"./description/text()"s,
        pub_date: ~x"./pubDate/text()"s,
        author: ~x"./author/text()"s,
        guid: ~x"./guid/text()"s,
        categories: ~x"./category/text()"ls,
        content_encoded: ~x"./content:encoded/text()"s
      )
      |> Enum.map(&normalize_item/1)
      |> Enum.reject(&is_nil/1)

    {:ok, %{feed: feed, items: items}}
  rescue
    e ->
      Logger.error("Failed to parse RSS feed: #{inspect(e)}")
      {:error, :parse_error}
  end

  # Atom Parser
  defp parse_atom(doc) do
    import SweetXml

    feed = %{
      title: xpath(doc, ~x"//feed/title/text()"s),
      subtitle: xpath(doc, ~x"//feed/subtitle/text()"s),
      link: xpath(doc, ~x"//feed/link[@rel='alternate']/@href"s),
      type: :atom
    }

    items =
      doc
      |> xpath(
        ~x"//feed/entry"l,
        title: ~x"./title/text()"s,
        link: ~x"./link[@rel='alternate']/@href"s,
        summary: ~x"./summary/text()"s,
        content: ~x"./content/text()"s,
        published: ~x"./published/text()"s,
        updated: ~x"./updated/text()"s,
        author_name: ~x"./author/name/text()"s,
        id: ~x"./id/text()"s
      )
      |> Enum.map(&normalize_atom_item/1)
      |> Enum.reject(&is_nil/1)

    {:ok, %{feed: feed, items: items}}
  rescue
    e ->
      Logger.error("Failed to parse Atom feed: #{inspect(e)}")
      {:error, :parse_error}
  end

  # RDF Parser (basic support)
  defp parse_rdf(doc) do
    import SweetXml

    feed = %{
      title: xpath(doc, ~x"//channel/title/text()"s),
      description: xpath(doc, ~x"//channel/description/text()"s),
      link: xpath(doc, ~x"//channel/link/text()"s),
      type: :rdf
    }

    items =
      doc
      |> xpath(
        ~x"//item"l,
        title: ~x"./title/text()"s,
        link: ~x"./link/text()"s,
        description: ~x"./description/text()"s,
        date: ~x"./dc:date/text()"s,
        creator: ~x"./dc:creator/text()"s
      )
      |> Enum.map(&normalize_rdf_item/1)
      |> Enum.reject(&is_nil/1)

    {:ok, %{feed: feed, items: items}}
  rescue
    e ->
      Logger.error("Failed to parse RDF feed: #{inspect(e)}")
      {:error, :parse_error}
  end

  # Normalize RSS items to consistent format
  defp normalize_item(item) do
    %{
      title: item.title,
      link: item.link,
      description: get_content(item),
      published_at: parse_date(item.pub_date),
      author: item.author,
      guid: item.guid || item.link,
      categories: item.categories
    }
  end

  defp normalize_atom_item(item) do
    %{
      title: item.title,
      link: item.link,
      description: item.content || item.summary,
      published_at: parse_date(item.published || item.updated),
      author: item.author_name,
      guid: item.id,
      categories: []
    }
  end

  defp normalize_rdf_item(item) do
    %{
      title: item.title,
      link: item.link,
      description: item.description,
      published_at: parse_date(item.date),
      author: item.creator,
      guid: item.link,
      categories: []
    }
  end

  defp get_content(item) do
    cond do
      item.content_encoded && String.length(item.content_encoded) > 0 ->
        item.content_encoded

      item.description && String.length(item.description) > 0 ->
        item.description

      true ->
        ""
    end
  end

  @doc """
  Parses various date formats found in RSS feeds.

  Supports:
  - RFC 822 (RSS 2.0): "Mon, 12 Sep 2024 10:30:00 GMT"
  - ISO 8601 (Atom): "2024-09-12T10:30:00Z"
  - Dublin Core: "2024-09-12"

  Returns DateTime or nil if parsing fails.
  """
  def parse_date(nil), do: nil
  def parse_date(""), do: nil

  def parse_date(date_string) when is_binary(date_string) do
    # Try ISO 8601 first (Atom feeds)
    case DateTime.from_iso8601(date_string) do
      {:ok, datetime, _offset} ->
        datetime

      _ ->
        # Try RFC 822 (RSS feeds)
        parse_rfc822_date(date_string)
    end
  end

  defp parse_rfc822_date(date_string) do
    # This is a simplified parser for common RSS date formats
    # For production, consider using a library like Timex
    case Regex.run(~r/(\d{1,2})\s+(\w{3})\s+(\d{4})\s+(\d{2}):(\d{2}):(\d{2})/, date_string) do
      [_, day, month, year, hour, minute, second] ->
        month_num = month_to_number(month)

        case NaiveDateTime.new(
               String.to_integer(year),
               month_num,
               String.to_integer(day),
               String.to_integer(hour),
               String.to_integer(minute),
               String.to_integer(second)
             ) do
          {:ok, naive} -> DateTime.from_naive!(naive, "Etc/UTC")
          _ -> nil
        end

      _ ->
        # Fallback: use current time if we can't parse
        Logger.warning("Could not parse date: #{date_string}, using current time")
        DateTime.utc_now()
    end
  end

  defp month_to_number("Jan"), do: 1
  defp month_to_number("Feb"), do: 2
  defp month_to_number("Mar"), do: 3
  defp month_to_number("Apr"), do: 4
  defp month_to_number("May"), do: 5
  defp month_to_number("Jun"), do: 6
  defp month_to_number("Jul"), do: 7
  defp month_to_number("Aug"), do: 8
  defp month_to_number("Sep"), do: 9
  defp month_to_number("Oct"), do: 10
  defp month_to_number("Nov"), do: 11
  defp month_to_number("Dec"), do: 12
  defp month_to_number(_), do: 1
end

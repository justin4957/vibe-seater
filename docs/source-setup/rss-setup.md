# RSS Feed Source Adapter Setup Guide

This guide covers setting up RSS/Atom feeds as data sources for Vibe Seater, enabling monitoring of news sites, blogs, podcasts, and other RSS-enabled content.

## Overview

The RSS adapter supports:
- **RSS 2.0** - Most common format for blogs and news sites
- **Atom** - Modern XML feed format
- **RDF** - Resource Description Framework feeds
- Podcasts with media enclosures
- News aggregators
- Blog feeds

## Supported Feed Types

### News Sites
- CNN, BBC, Reuters, Al Jazeera
- Tech news: TechCrunch, Ars Technica, The Verge
- Financial news: Bloomberg, CNBC, Financial Times

### Blogs & Publications
- Medium, WordPress, Ghost blogs
- Substack newsletters (often have RSS)
- Academic journals and preprints

### Podcasts
- Most podcasts provide RSS feeds
- Apple Podcasts, Spotify (if RSS available)
- Podcast aggregators

### Aggregators
- Google News (specific topics/searches)
- Reddit (subreddits have RSS)
- Hacker News
- Product Hunt

## Quick Start

### Finding RSS Feed URLs

Most websites offer RSS feeds, but they're often hidden. Here's how to find them:

#### Method 1: Look for RSS Icons
- Look for RSS icon (📡 or orange wave icon) on website
- Common locations: footer, sidebar, "Subscribe" section
- Click icon to get feed URL

#### Method 2: View Page Source
- Right-click page → "View Page Source"
- Search for "rss", "atom", or "feed"
- Look for `<link rel="alternate" type="application/rss+xml">`

#### Method 3: Try Common Patterns
```
https://example.com/feed/
https://example.com/rss/
https://example.com/feed.xml
https://example.com/rss.xml
https://example.com/atom.xml
```

#### Method 4: Use RSS Discovery Tools
- [RSS Feed Finder](https://rss-finder.rook1e.com/)
- Browser extension: "RSS Feed Detector"
- Command line: `curl -s https://example.com | grep -i rss`

### Creating an RSS Source

```elixir
# Basic RSS source
{:ok, source} = VibeSeater.Sources.create_source(%{
  name: "TechCrunch Feed",
  source_type: "rss",
  source_url: "https://techcrunch.com/feed/"
})

# RSS source with custom configuration
{:ok, source} = VibeSeater.Sources.create_source(%{
  name: "BBC World News",
  source_type: "rss",
  source_url: "http://feeds.bbci.co.uk/news/world/rss.xml",
  config: %{
    "poll_interval_seconds" => 300,  # Check every 5 minutes
    "include_content" => true,        # Include full article content
    "categories" => ["world", "politics"]  # Filter by category
  }
})
```

### Attaching to a Stream

```elixir
# Get your stream
stream = VibeSeater.Streaming.get_stream!(stream_id)

# Attach RSS source
VibeSeater.Streaming.attach_source(stream, source)

# Start monitoring
VibeSeater.Streaming.start_stream(stream)
```

## Configuration Options

### Required Fields

| Field | Type | Description | Example |
|-------|------|-------------|---------|
| `name` | string | Descriptive name for the source | "TechCrunch Feed" |
| `source_type` | string | Must be "rss" | "rss" |
| `source_url` | string | RSS feed URL | "https://example.com/feed.xml" |

### Optional Configuration

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `poll_interval_seconds` | integer | 60 | How often to check for new items (min: 30) |
| `include_content` | boolean | true | Include full content vs summary only |
| `categories` | list | [] | Filter items by feed categories |

### Configuration Examples

#### High-Frequency News Feed
```elixir
config: %{
  "poll_interval_seconds" => 60,  # Check every minute
  "include_content" => false       # Titles only for speed
}
```

#### Low-Frequency Blog
```elixir
config: %{
  "poll_interval_seconds" => 3600,  # Check hourly
  "include_content" => true          # Full articles
}
```

#### Category-Filtered Feed
```elixir
config: %{
  "poll_interval_seconds" => 300,
  "categories" => ["technology", "science"]  # Only these categories
}
```

## Popular RSS Feeds

### News Sites

```elixir
# BBC World News
source_url: "http://feeds.bbci.co.uk/news/world/rss.xml"

# CNN Top Stories
source_url: "http://rss.cnn.com/rss/cnn_topstories.rss"

# Reuters World News
source_url: "https://www.reutersagency.com/feed/?taxonomy=best-topics&post_type=best"

# Al Jazeera English
source_url: "https://www.aljazeera.com/xml/rss/all.xml"

# NPR News
source_url: "https://feeds.npr.org/1001/rss.xml"
```

### Technology News

```elixir
# TechCrunch
source_url: "https://techcrunch.com/feed/"

# Ars Technica
source_url: "http://feeds.arstechnica.com/arstechnica/index"

# The Verge
source_url: "https://www.theverge.com/rss/index.xml"

# Hacker News
source_url: "https://news.ycombinator.com/rss"

# Slashdot
source_url: "http://rss.slashdot.org/Slashdot/slashdotMain"
```

### Reddit Feeds

Reddit subreddits have RSS feeds:

```elixir
# r/worldnews
source_url: "https://www.reddit.com/r/worldnews/.rss"

# r/technology
source_url: "https://www.reddit.com/r/technology/.rss"

# r/programming
source_url: "https://www.reddit.com/r/programming/.rss"
```

### Podcasts

```elixir
# Note: Most podcast apps provide RSS URLs
# Example formats:

# NPR Politics Podcast
source_url: "https://feeds.npr.org/510310/podcast.xml"

# Radiolab
source_url: "http://feeds.wnyc.org/radiolab"
```

## Advanced Usage

### Monitoring Multiple Feeds

```elixir
# Create multiple sources for comprehensive coverage
feeds = [
  {"BBC World", "http://feeds.bbci.co.uk/news/world/rss.xml"},
  {"CNN", "http://rss.cnn.com/rss/cnn_topstories.rss"},
  {"Reuters", "https://www.reutersagency.com/feed/?best-topics"}
]

sources = Enum.map(feeds, fn {name, url} ->
  {:ok, source} = VibeSeater.Sources.create_source(%{
    name: name,
    source_type: "rss",
    source_url: url,
    config: %{"poll_interval_seconds" => 300}
  })
  source
end)

# Attach all to same stream
stream = VibeSeater.Streaming.get_stream!(stream_id)
Enum.each(sources, &VibeSeater.Streaming.attach_source(stream, &1))
```

### Handling Feed Updates

RSS feeds may change URLs or become unavailable:

```elixir
# Update feed URL
VibeSeater.Sources.update_source(source, %{
  source_url: "https://new-feed-url.com/feed.xml"
})

# Deactivate temporarily
VibeSeater.Sources.deactivate_source(source)

# Reactivate
VibeSeater.Sources.activate_source(source)
```

### Filtering by Date Range

```elixir
# Get events from specific time period
start_time = ~U[2024-01-01 00:00:00Z]
end_time = ~U[2024-01-31 23:59:59Z]

events = VibeSeater.Events.list_events_for_stream_in_range(
  stream,
  start_time,
  end_time
)
```

## Performance Considerations

### Polling Intervals

Choose appropriate intervals based on feed update frequency:

| Feed Type | Recommended Interval | Reason |
|-----------|---------------------|---------|
| Breaking News | 60-120 seconds | Updates very frequently |
| Tech News | 300-600 seconds | Updates several times/hour |
| Blog Posts | 1800-3600 seconds | Updates few times/day |
| Podcasts | 3600-7200 seconds | Updates weekly/daily |

### Resource Usage

```elixir
# For many feeds (50+), use longer intervals
config: %{
  "poll_interval_seconds" => 600  # 10 minutes
}

# Monitor feed statistics
stats = VibeSeater.Events.get_stream_statistics(stream)
# Shows: event_count per source
```

### Deduplication

The RSS adapter automatically:
- Tracks seen items by GUID (or link as fallback)
- Prevents duplicate events
- Maintains history of last 1000 items

## Troubleshooting

### Feed Not Updating

**Problem**: No new events appearing

**Solutions**:
1. Check feed URL is accessible:
   ```bash
   curl -I https://example.com/feed.xml
   ```

2. Verify feed has new items:
   ```bash
   curl https://example.com/feed.xml | grep pubDate
   ```

3. Check logs:
   ```elixir
   # Look for polling messages
   tail -f log/dev.log | grep RSS
   ```

4. Manually test fetch:
   ```elixir
   VibeSeater.SourceAdapters.RSSAdapter.fetch_feed(source)
   ```

### Feed Returns 404

**Problem**: Feed URL returns "Not Found"

**Solutions**:
- Feed may have moved - check website for new URL
- Try alternate feed formats (replace `/feed/` with `/rss.xml`)
- Check if site still provides RSS (many sites removed RSS)

### Feed Returns 403 Forbidden

**Problem**: Feed blocks automated requests

**Solutions**:
- Some feeds block certain user agents
- RSS adapter uses: "VibeSeater RSS Reader/1.0"
- May need to use feed aggregator service as proxy

### Malformed XML Errors

**Problem**: Parser fails with XML errors

**Solutions**:
- Feed may be malformed - validate at [W3C Feed Validator](https://validator.w3.org/feed/)
- Check feed encoding (should be UTF-8)
- Some feeds have invalid HTML in descriptions - adapter strips HTML

### Missing Dates on Items

**Problem**: Events don't have correct timestamps

**Solutions**:
- Not all feeds include publication dates
- Adapter falls back to ingestion time
- Filter feeds by quality (prefer feeds with proper dates)

## Feed Quality Tips

### Choosing Good Feeds

✅ **Good Quality Feeds**:
- Include publication dates
- Have unique GUIDs
- Provide full content or good summaries
- Update regularly
- Use valid XML

❌ **Poor Quality Feeds**:
- Missing dates (events use ingestion time)
- Duplicate items
- Broken/truncated content
- Irregular updates
- Invalid XML

### Testing Feed Quality

```bash
# Check if feed is valid
curl -s https://example.com/feed.xml | xmllint --noout - 2>&1

# Count items in feed
curl -s https://example.com/feed.xml | grep -c "<item>"

# Check for dates
curl -s https://example.com/feed.xml | grep -i "pubdate\|published"
```

## Example Use Cases

### 1. News Aggregation Stream

Monitor breaking news from multiple sources:

```elixir
# Create stream
{:ok, stream} = VibeSeater.Streaming.create_stream(%{
  title: "Breaking News Aggregator",
  stream_url: "https://youtube.com/watch?v=live-news",
  stream_type: "youtube"
})

# Add news feeds
news_feeds = [
  "http://feeds.bbci.co.uk/news/world/rss.xml",
  "http://rss.cnn.com/rss/cnn_topstories.rss",
  "https://www.aljazeera.com/xml/rss/all.xml"
]

Enum.each(news_feeds, fn url ->
  {:ok, source} = VibeSeater.Sources.create_source(%{
    name: "News: #{url}",
    source_type: "rss",
    source_url: url,
    config: %{"poll_interval_seconds" => 120}
  })
  VibeSeater.Streaming.attach_source(stream, source)
end)
```

### 2. Tech News + Product Launches

Combine tech news with product announcements:

```elixir
sources = [
  # Tech news
  {"TechCrunch", "https://techcrunch.com/feed/"},
  {"Hacker News", "https://news.ycombinator.com/rss"},

  # Product launches
  {"Product Hunt", "https://www.producthunt.com/feed"},
  {"Kickstarter Tech", "https://www.kickstarter.com/projects.atom"}
]
```

### 3. Research & Academic Feeds

Monitor preprints and journal publications:

```elixir
sources = [
  {"arXiv CS", "http://export.arxiv.org/rss/cs"},
  {"Nature News", "http://www.nature.com/nature/current_issue/rss"},
  {"Science Daily", "https://www.sciencedaily.com/rss/all.xml"}
]
```

## Best Practices

1. **Respectful Polling**: Don't poll too frequently (minimum 30 seconds)
2. **Monitor Bandwidth**: Track data usage for many feeds
3. **Handle Errors Gracefully**: Feeds may be temporarily unavailable
4. **Validate Feed URLs**: Check accessibility before adding
5. **Regular Cleanup**: Remove inactive or broken feeds

## Next Steps

1. Explore available RSS feeds for your interests
2. Test feeds with manual fetch before adding to stream
3. Monitor event statistics to ensure feeds are working
4. Adjust polling intervals based on actual update frequency
5. Consider using feed aggregator services for reliability

## Additional Resources

- [RSS 2.0 Specification](https://www.rssboard.org/rss-specification)
- [Atom Specification](https://tools.ietf.org/html/rfc4287)
- [W3C Feed Validator](https://validator.w3.org/feed/)
- [Find RSS Feeds](https://rss-finder.rook1e.com/)
- [About RSS](https://aboutfeeds.com/)

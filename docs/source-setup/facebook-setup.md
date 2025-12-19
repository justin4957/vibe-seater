# Facebook Source Adapter Setup Guide

This guide covers setting up Facebook as a data source for Vibe Seater, including bot account monitoring and Graph API configuration.

## Overview

Facebook integration supports monitoring:
- **Public Pages**: News organizations, public figures, brands
- **Groups**: Public and private groups (requires membership)
- **Hashtags**: Search-based monitoring

## Monitoring Strategies

### Strategy 1: Bot Account Monitoring (Recommended)

Due to Facebook's restrictive Graph API policies, the recommended approach is using a dedicated bot account with browser automation.

#### Why Bot Account Monitoring?

- ✅ **No API approval required** - No business verification needed
- ✅ **Access to more content** - Can monitor pages, groups, and hashtags
- ✅ **Simpler setup** - No app creation or review process
- ⚠️ **Requires maintenance** - Facebook UI changes may break scraping
- ⚠️ **Rate limiting** - Must be careful to avoid account suspension

#### Creating a Facebook Bot Account

**IMPORTANT**: This account should be used solely for monitoring purposes and should comply with Facebook's Terms of Service.

1. **Create a New Facebook Account**
   - Use a dedicated email address (e.g., `vibe-seater-bot@yourdomain.com`)
   - Use a real name (fake names may be flagged)
   - Complete account verification (phone number, email)
   - Add a profile photo to appear more legitimate

2. **Configure Account Security**
   - Enable two-factor authentication (save backup codes)
   - Create a strong, unique password
   - Store credentials securely (use environment variables, never commit to git)

3. **Build Account Credibility**
   - Join a few groups in your monitoring niche
   - Like a few pages
   - Make occasional legitimate posts/comments
   - Wait 24-48 hours before starting automated monitoring

4. **Join Target Pages/Groups**
   - Follow the pages you want to monitor
   - Join groups you want to monitor (request access if private)
   - Ensure you can see the content manually first

#### Browser Automation Setup

The Facebook adapter uses browser automation to scrape content. You'll need:

1. **Install Wallaby (Elixir Browser Automation)**
   ```bash
   # Add to mix.exs dependencies
   {:wallaby, "~> 0.30", runtime: false, only: :dev}
   ```

2. **Install ChromeDriver**
   ```bash
   # macOS
   brew install --cask chromedriver

   # Ubuntu/Debian
   sudo apt-get install chromium-chromedriver

   # Verify installation
   chromedriver --version
   ```

3. **Configure Wallaby**
   ```elixir
   # config/config.exs
   config :wallaby,
     driver: Wallaby.Chrome,
     hackney_options: [timeout: 30_000, recv_timeout: 30_000],
     screenshot_on_failure: true,
     js_errors: false
   ```

4. **Store Bot Credentials Securely**
   ```bash
   # .env or environment variables (NEVER commit these)
   export FACEBOOK_BOT_EMAIL="your-bot@example.com"
   export FACEBOOK_BOT_PASSWORD="your-secure-password"
   ```

   ```elixir
   # config/runtime.exs
   config :vibe_seater,
     facebook_bot_email: System.get_env("FACEBOOK_BOT_EMAIL"),
     facebook_bot_password: System.get_env("FACEBOOK_BOT_PASSWORD")
   ```

#### Usage Example

```elixir
# Create a Facebook source for a public page
{:ok, source} = VibeSeater.Sources.create_source(%{
  name: "CNN Facebook Page",
  source_type: "facebook",
  config: %{
    "type" => "page",
    "page_id" => "cnn",
    "monitoring_mode" => "bot_account",
    "poll_interval_seconds" => 300  # Check every 5 minutes
  }
})

# Attach to a stream
stream = VibeSeater.Streaming.get_stream!(stream_id)
VibeSeater.Streaming.attach_source(stream, source)

# Start the stream (will begin monitoring)
VibeSeater.Streaming.start_stream(stream)
```

### Strategy 2: Graph API (Optional - Requires Business Verification)

The Facebook Graph API provides official access but requires business verification.

#### Requirements

- Facebook Developer account
- Business verification (can take weeks)
- App creation and review
- Limited to public page data only

#### Graph API Setup Steps

1. **Create Facebook App**
   - Go to https://developers.facebook.com
   - Create new app
   - Choose "Business" type

2. **Add Pages API**
   - Navigate to App Dashboard
   - Add "Pages API" product
   - Submit for app review

3. **Get Access Token**
   - Generate Page Access Token
   - Store securely as environment variable

4. **Configure Vibe Seater**
   ```bash
   export FACEBOOK_APP_ID="your-app-id"
   export FACEBOOK_APP_SECRET="your-app-secret"
   export FACEBOOK_PAGE_TOKEN="your-page-token"
   ```

   ```elixir
   # Create source with Graph API mode
   {:ok, source} = VibeSeater.Sources.create_source(%{
     name: "Page via Graph API",
     source_type: "facebook",
     config: %{
       "type" => "page",
       "page_id" => "cnn",
       "monitoring_mode" => "graph_api"
     }
   })
   ```

## Best Practices

### Bot Account Monitoring

1. **Rate Limiting**
   - Don't poll more frequently than every 5 minutes
   - Add random delays between requests (30-60 seconds)
   - Monitor only during business hours if possible

2. **Human-Like Behavior**
   - Add random mouse movements (if using visible browser)
   - Vary scroll speeds and distances
   - Include small delays between actions (1-3 seconds)

3. **Session Management**
   - Persist cookies between sessions
   - Re-login only when necessary
   - Handle CAPTCHA gracefully (manual intervention)

4. **Error Handling**
   - Detect when logged out and re-authenticate
   - Handle rate limiting gracefully
   - Log errors without exposing credentials

5. **Account Safety**
   - Don't run monitoring 24/7 initially
   - Gradually increase monitoring frequency
   - Monitor from same IP address when possible
   - Use residential IP (not datacenter/VPS)

### Compliance and Ethics

⚠️ **Important Considerations**:

1. **Facebook Terms of Service**
   - Bot account monitoring may violate Facebook's ToS
   - Use at your own risk
   - Consider official Graph API for production

2. **Privacy**
   - Only monitor public content
   - Respect user privacy
   - Don't store sensitive personal information

3. **Data Usage**
   - Use scraped data responsibly
   - Don't republish without permission
   - Attribute content to original authors

## Troubleshooting

### Bot Account Issues

**Account Suspended/Locked**
- Facebook detected automated behavior
- Solution: Reduce polling frequency, add more delays
- May need to verify account via phone/ID

**Login Fails**
- Password changed or 2FA issue
- Solution: Update credentials, check 2FA codes
- May need to login manually first

**Missing Content**
- Bot account doesn't have access
- Solution: Ensure account follows page or joined group
- Check privacy settings on target

**CAPTCHA Challenges**
- Facebook requires manual verification
- Solution: Implement manual intervention notification
- Consider using CAPTCHA solving service (with caution)

### Graph API Issues

**App Not Approved**
- Facebook app review pending or rejected
- Solution: Provide detailed use case in review
- May take 2-4 weeks for approval

**Token Expired**
- Access token has limited lifetime
- Solution: Implement token refresh
- Use long-lived tokens where possible

## Configuration Reference

### Page Monitoring

```elixir
%{
  "type" => "page",
  "page_id" => "cnn",                    # Facebook page username
  "monitoring_mode" => "bot_account",    # or "graph_api"
  "poll_interval_seconds" => 300         # 5 minutes minimum
}
```

### Group Monitoring

```elixir
%{
  "type" => "group",
  "group_id" => "123456789",             # Numeric group ID
  "monitoring_mode" => "bot_account",
  "poll_interval_seconds" => 600         # 10 minutes for groups
}
```

### Hashtag Monitoring

```elixir
%{
  "type" => "hashtag",
  "hashtag" => "#news",                  # Include # symbol
  "monitoring_mode" => "bot_account",
  "poll_interval_seconds" => 900         # 15 minutes for searches
}
```

## Next Steps

1. Set up your bot account or Graph API credentials
2. Test with a single page before scaling
3. Monitor logs for errors or rate limiting
4. Adjust polling intervals based on page activity
5. Implement proper error handling and notifications

## Additional Resources

- [Facebook Graph API Documentation](https://developers.facebook.com/docs/graph-api)
- [Facebook Terms of Service](https://www.facebook.com/legal/terms)
- [Wallaby Documentation](https://hexdocs.pm/wallaby)
- [Ethical Web Scraping Guidelines](https://www.scrapehero.com/web-scraping-laws/)

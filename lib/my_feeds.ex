defmodule MyFeeds do
  def run do
    Application.get_env(:my_feeds, :urls)
    |> Enum.map(&fetch/1)
    |> Task.await_many(60_000)
    |> Enum.map(&parse/1)
    |> List.flatten()
    |> Enum.sort_by(&parse_pubdate/1, {:desc, NaiveDateTime})
    |> Enum.take(10)
    |> build()
    |> IO.puts()
  end

  defp fetch(url) do
    Task.async(fn ->
      Req.get!(url).body
    end)
  end

  defp parse(body) do
    {:ok, feed} = FastRSS.parse(body)
    feed["items"]
  end

  defp parse_pubdate(item) do
    {:ok, dt} = DateTimeParser.parse(item["pub_date"])
    dt
  end

  defp build(items) do
    title = Application.get_env(:my_feeds, :title)
    link = Application.get_env(:my_feeds, :link)
    description = Application.get_env(:my_feeds, :description)
    {:ok, date} = Timex.now() |> Timex.format("{RFC1123}")

    channel = """
      <title>#{title}</title>
      <link>#{link}</link>
      <description>#{description}</description>
      <lastBuildDate>#{date}</lastBuildDate>
    """

    """
    <?xml version="1.0" encoding="utf-8"?>
    <rss version="2.0">
    <channel>
    #{channel}
    #{Enum.map(items, &build_item/1)}
    </channel>
    </rss>
    """
  end

  defp build_item(item) do
    """
      <item>
        <title>#{item["title"]}</title>
        <description><![CDATA[
          #{item["description"]}
        ]]></description>
        <pubDate>#{item["pub_date"]}</pubDate>
        <link>#{item["link"]}</link>
        <guid isPermalink="#{item["guid"]["permalink"]}">#{item["guid"]["value"]}</guid>
        #{enclosure(item)}
      </item>
    """
  end

  defp enclosure(item) do
    cond do
      item["link"] |> String.starts_with?("https://listen.style") ->
        """
        <enclosure url="#{item["itunes_ext"]["image"]}" type="image/jpeg" />
        """
      item["link"] |> String.starts_with?("https://note.com") ->
        """
        <enclosure url="#{get_in(item, ["extensions", "media", "thumbnail", Access.at(0), "value"])}" type="image/jpeg" />
        """
      item["link"] |> String.starts_with?("https://zenn.dev") ->
        """
        <enclosure url="#{item["enclosure"]["url"]}"  type="image/png" />
        """
    end
  end
end

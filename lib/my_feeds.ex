defmodule MyFeeds do
  def run(opts \\ []) do
    Application.get_env(:my_feeds, :urls)
    |> Enum.map(&fetch/1)
    |> Task.await_many(60_000)
    |> Enum.map(&parse/1)
    |> List.flatten()
    |> filter()
    |> Enum.sort_by(&parse_pubdate/1, {:desc, NaiveDateTime})
    |> Enum.take(opts[:num] || 100)
    |> build()
    |> write(opts[:file] || "output/index.xml")
  end

  defp fetch(url) do
    Task.async(fn ->
      Req.get!(url).body
    end)
  end

  defp parse(body) do
    {:ok, feed} =
      case String.match?(body, ~r/<feed/) do
        true -> body |> FastRSS.parse_atom()
        _ -> body |> FastRSS.parse_rss()
      end

    feed["items"] || feed["entries"]
  end

  defp parse_pubdate(item) do
    {:ok, dt} = DateTimeParser.parse(item["pub_date"] || item["published"])
    dt
  end

  defp filter(items) do
    # noteの有料記事を除外する
    items
    |> Enum.filter(fn item ->
      !Regex.match?(~r|^https://note\.com|, link(item)) ||
        !Regex.match?(~r|^\d+年\d+月\d+日|, title(item))
    end)
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
        <title>#{title(item)}</title>
        <description><![CDATA[
          #{description(item)}
        ]]></description>
        <pubDate>#{pub_date(item)}</pubDate>
        <link>#{link(item)}</link>
        #{guid(item)}
        #{enclosure(item)}
      </item>
    """
  end

  defp title(item) do
    (is_map(item["title"]) && item["title"]["value"]) ||
      item["title"]
  end

  defp description(item) do
    (item["description"] && item["description"]) ||
      get_in(item, [
        "extensions",
        "media",
        "group",
        Access.at(0),
        "children",
        "description",
        Access.at(0),
        "value"
      ])
  end

  defp link(item) do
    (is_list(item["links"]) && get_in(item["links"], [Access.at(0), "href"])) ||
      item["link"]
  end

  defp pub_date(item) do
    item["pub_date"] || item["published"]
  end

  defp guid(item) do
    (item["guid"] &&
       """
       <guid isPermalink="#{item["guid"]["permalink"]}">#{item["guid"]["value"]}</guid>
       """) ||
      """
      <guid isPermalink="false">#{item["id"]}</guid>
      """
  end

  defp enclosure(item) do
    cond do
      link(item) |> String.starts_with?("https://listen.style") ->
        """
        <enclosure url="#{item["itunes_ext"]["image"]}" type="image/jpeg" />
        """

      link(item) |> String.starts_with?("https://note.com") ->
        """
        <enclosure url="#{get_in(item, ["extensions", "media", "thumbnail", Access.at(0), "value"])}" type="image/jpeg" />
        """

      link(item) |> String.starts_with?("https://zenn.dev") ->
        """
        <enclosure url="#{item["enclosure"]["url"]}"  type="image/png" />
        """

      link(item) |> String.starts_with?("https://www.youtube.com") ->
        url =
          get_in(item, [
            "extensions",
            "media",
            "group",
            Access.at(0),
            "children",
            "thumbnail",
            Access.at(0),
            "attrs",
            "url"
          ])

        """
        <enclosure url="#{url}"  type="image/jpeg" />
        """

      link(item) |> String.starts_with?("https://www.tiktok.com") ->
        """
        <enclosure url="#{item["enclosure"]["url"] |> String.replace("&", "&amp;")}" type="image/jpeg" />
        """

      link(item) |> String.starts_with?("https://speakerdeck.com") ->
        url = get_in(item, ["extensions", "media", "content", Access.at(0), "attrs", "url"])

        """
        <enclosure url="#{url}" type="image/jpeg" />
        """

      link(item) |> String.starts_with?("https://soundcloud.com") ->
        """
        <enclosure url="#{item["itunes_ext"]["image"]}" type="image/jpeg" />
        """
    end
  end

  defp write(content, file) do
    File.write(file, content)
  end
end

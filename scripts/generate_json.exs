{:ok, rss} =
  File.read!("output/index.xml")
  |> FastRSS.parse()
json =
  rss
  |> Jason.encode!(pretty: true)

File.write("output/index.json", json)

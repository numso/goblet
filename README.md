# Goblet

> Something to help you consume that sweet, sweet absinthe.

A GraphQL client library that formats and sends queries and mutations to your GraphQL server while also validating those queries and mutations against a schema at compile time. ([documentation](https://hexdocs.pm/goblet))

## Installation

The package can be installed by adding `goblet` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:goblet, "~> 0.1.2"}]
end
```

## Basic Usage

```elixir
defmodule MyGoblet do
  use Goblet, from: "./path/to/schema.json"

  def process(query, _ctx) do
    HTTPoison.post!("https://api.myserver.example/graphql", Jason.encode!(%{body: query}))
    Map.get(:body)
    |> Jason.decode!()
  end
end

defmodule Queries do
  use MyGoblet

  query "FetchUser" do
    user(id: ^id) do
      id
      name

      friends(first: 3) do
        id
        name
        profilePic
      end

      @as "moreFriends"
      friends(first: 15) do
        id
        name
      end
    end
  end
end

Queries.fetch_user(%{id: "abc"})
# %{
#   "operationName" => "FetchUser",
#   "query" =>
#     "query FetchUser($id: ID!) {user(id: $id) {id name friends(first: 3){id name profilePic} moreFriends:friends(first:15){id name}}}",
#   "variables" => %{id: "abc"}
# }

Queries.fetch_user(%{id: "abc"}, ctx)
# formats the query like above and then passes it, along with ctx, into your process function
```

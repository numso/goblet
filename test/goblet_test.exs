defmodule GobletTest do
  use ExUnit.Case
  alias Mix.Task.Compiler.Diagnostic

  defmodule MyGoblet do
    use Goblet, from: "./test/schema.json"
  end

  defmodule MyGobletWithProcess do
    use Goblet, from: "./test/schema.json"

    def process(query, ctx) do
      %{query: query, ctx: ctx}
    end
  end

  defmodule Queries do
    use MyGoblet

    query "Test" do
      id
    end
  end

  test "can build a simple query" do
    assert Queries.test() == %{
             "operationName" => "Test",
             "query" => "query Test {id}",
             "variables" => %{}
           }
  end

  test "does not create test/2 if process is not defined" do
    assert function_exported?(Queries, :test, 2) == false
  end

  defmodule Queries2 do
    use MyGobletWithProcess

    query "Test" do
      id
    end
  end

  test "can process a simple query" do
    assert function_exported?(Queries2, :test, 2)

    assert Queries2.test(%{}, "ctx") == %{
             query: %{
               "operationName" => "Test",
               "query" => "query Test {id}",
               "variables" => %{}
             },
             ctx: "ctx"
           }
  end

  defmodule Queries3 do
    use MyGoblet

    query "Test" do
      whoops
    end
  end

  test "reports errors to EditorDiagnostics" do
    assert EditorDiagnostics.collect() == [
             %Diagnostic{
               compiler_name: "goblet",
               file: Path.absname("./test/goblet_test.exs"),
               message: "Could not find field whoops on type RootQueryType",
               position: 62,
               severity: :error
             }
           ]
  end

  defmodule Queries4 do
    use MyGoblet

    query "GetId" do
      id
    end

    query "GetAge" do
      age
    end
  end

  test "can define multiple queries" do
    assert Queries4.get_id() == %{
             "operationName" => "GetId",
             "query" => "query GetId {id}",
             "variables" => %{}
           }

    assert Queries4.get_age() == %{
             "operationName" => "GetAge",
             "query" => "query GetAge {age}",
             "variables" => %{}
           }
  end

  defmodule ComplexQueries do
    use MyGoblet

    query "MoreInteresting" do
      ages
      withArgs(a: "hi", b: "hello")

      thing do
        name
      end

      things do
        name
      end

      requiredThing do
        name
      end

      requiredThings do
        name
      end

      requiredThingsAgain do
        name
      end

      doublyRequiredThings do
        name
      end
    end
  end

  test "can define more complex queries" do
    assert ComplexQueries.more_interesting() == %{
             "operationName" => "MoreInteresting",
             "query" =>
               "query MoreInteresting {ages withArgs(a: \"hi\", b: \"hello\") thing {name} things {name} requiredThing {name} requiredThings {name} requiredThingsAgain {name} doublyRequiredThings {name}}",
             "variables" => %{}
           }
  end
end

defmodule GobletTest do
  use ExUnit.Case
  alias Mix.Task.Compiler.Diagnostic

  defmodule SimpleGoblet do
    use Goblet, from: "./test/schema.json"
  end

  defmodule Simple do
    use SimpleGoblet

    query "Test" do
      id
    end
  end

  test "can build a simple query" do
    assert Simple.test() == %{
             "operationName" => "Test",
             "query" => "query Test {id}",
             "variables" => %{}
           }
  end

  test "does not create test/2 if process is not defined" do
    assert function_exported?(Simple, :test, 2) == false
  end

  defmodule SimpleGoblet2 do
    use Goblet, from: "./test/schema.json"

    def process(query, ctx) do
      %{query: query, ctx: ctx}
    end
  end

  defmodule Simple2 do
    use SimpleGoblet2

    query "Test" do
      id
    end
  end

  test "can process a simple query" do
    assert function_exported?(Simple2, :test, 2)

    assert Simple2.test(%{}, "ctx") == %{
             query: %{
               "operationName" => "Test",
               "query" => "query Test {id}",
               "variables" => %{}
             },
             ctx: "ctx"
           }
  end

  defmodule SimpleGoblet3 do
    use Goblet, from: "./test/schema.json"
  end

  defmodule Simple3 do
    use SimpleGoblet3

    query "Test" do
      whoops
    end
  end

  test "reports errors to EditorDiagnostics" do
    assert EditorDiagnostics.collect() == [
             %Diagnostic{
               compiler_name: "goblet",
               details: nil,
               file: Path.absname("./test/goblet_test.exs"),
               message: "Could not find field whoops on type RootQueryType",
               position: 66,
               severity: :error
             }
           ]
  end

  defmodule SimpleGoblet4 do
    use Goblet, from: "./test/schema.json"
  end

  defmodule Simple4 do
    use SimpleGoblet4

    query "GetId" do
      id
    end

    query "GetAge" do
      age
    end
  end

  test "can define multiple queries" do
    assert Simple4.get_id() == %{
             "operationName" => "GetId",
             "query" => "query GetId {id}",
             "variables" => %{}
           }

    assert Simple4.get_age() == %{
             "operationName" => "GetAge",
             "query" => "query GetAge {age}",
             "variables" => %{}
           }
  end

  defmodule ComplexGoblet do
    use Goblet, from: "./test/schema.json"
  end

  defmodule Complex do
    use ComplexGoblet

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
    assert Complex.more_interesting() == %{
             "operationName" => "MoreInteresting",
             "query" =>
               "query MoreInteresting {ages withArgs(a: \"hi\", b: \"hello\") thing {name} things {name} requiredThing {name} requiredThings {name} requiredThingsAgain {name} doublyRequiredThings {name}}",
             "variables" => %{}
           }
  end
end

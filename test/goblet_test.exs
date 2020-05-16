defmodule GobletTest do
  use ExUnit.Case

  test "can build a simple query" do
    {mod, _} =
      Code.eval_string("""
      defmodule G1 do
        use Goblet, from: "./test/schema.json"
      end

      defmodule Q1 do
        use G1
        query "Test" do
          id
        end
      end

      Q1
      """)

    assert mod.test() == %{
             "operationName" => "Test",
             "query" => "query Test {id}",
             "variables" => %{}
           }
  end

  test "does not create test/2 if process is not defined" do
    {mod, _} =
      Code.eval_string("""
      defmodule G2 do
        use Goblet, from: "./test/schema.json"
      end

      defmodule Q2 do
        use G2
        query "Test" do
          id
        end
      end

      Q2
      """)

    assert function_exported?(mod, :test, 1) == true
    assert function_exported?(mod, :test, 2) == false
  end

  test "creates test/2 if process is defined" do
    {mod, _} =
      Code.eval_string("""
      defmodule G3 do
        use Goblet, from: "./test/schema.json"
        def process(query, ctx), do: %{query: query, ctx: ctx}
      end

      defmodule Q3 do
        use G3
        query "Test" do
          id
        end
      end

      Q3
      """)

    assert function_exported?(mod, :test, 1) == true
    assert function_exported?(mod, :test, 2) == true
  end

  test "can process a simple query" do
    {mod, _} =
      Code.eval_string("""
      defmodule G4 do
        use Goblet, from: "./test/schema.json"
        def process(query, ctx), do: %{query: query, ctx: ctx}
      end

      defmodule Q4 do
        use G4
        query "Test" do
          id
        end
      end

      Q4
      """)

    assert mod.test(%{}, "ctx") == %{
             query: %{
               "operationName" => "Test",
               "query" => "query Test {id}",
               "variables" => %{}
             },
             ctx: "ctx"
           }
  end

  test "reports errors" do
    result =
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        assert_raise RuntimeError, fn ->
          Code.eval_string("""
          defmodule G5 do
            use Goblet, from: "./test/schema.json"
          end

          defmodule Q5 do
            use G5
            query "Test" do
              whoops
            end
          end

          Q5
          """)
        end
      end)

    assert result =~ "Unexpected field whoops on type RootQueryType"
  end

  test "can define multiple queries" do
    {mod, _} =
      Code.eval_string("""
      defmodule G6 do
        use Goblet, from: "./test/schema.json"
      end

      defmodule Q6 do
        use G6
        query "GetId" do
          id
        end
        query "GetAge" do
          age
        end
      end

      Q6
      """)

    assert mod.get_id() == %{
             "operationName" => "GetId",
             "query" => "query GetId {id}",
             "variables" => %{}
           }

    assert mod.get_age() == %{
             "operationName" => "GetAge",
             "query" => "query GetAge {age}",
             "variables" => %{}
           }
  end

  test "can define more complex queries" do
    {mod, _} =
      Code.eval_string("""
      defmodule G7 do
        use Goblet, from: "./test/schema.json"
      end

      defmodule Q7 do
        use G7
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

      Q7
      """)

    assert mod.more_interesting() == %{
             "operationName" => "MoreInteresting",
             "query" =>
               "query MoreInteresting {ages withArgs(a: \"hi\", b: \"hello\") thing {name} things {name} requiredThing {name} requiredThings {name} requiredThingsAgain {name} doublyRequiredThings {name}}",
             "variables" => %{}
           }
  end
end

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

  test "reports nested errors" do
    result =
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        assert_raise RuntimeError, fn ->
          Code.eval_string("""
          defmodule G51 do
            use Goblet, from: "./test/schema.json"
          end

          defmodule Q51 do
            use G51
            query "Test" do
              thing do
                lololol
              end
            end
          end

          Q51
          """)
        end
      end)

    assert result =~ "Unexpected field lololol on type Thing"
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
          withArgs(a: 7, b: "hello")
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
               "query MoreInteresting {ages withArgs(a: 7, b: \"hello\") thing {name} things {name} requiredThing {name} requiredThings {name} requiredThingsAgain {name} doublyRequiredThings {name}}",
             "variables" => %{}
           }
  end

  test "can pin variables" do
    {mod, _} =
      Code.eval_string("""
      defmodule G8 do
        use Goblet, from: "./test/schema.json"
      end

      defmodule Q8 do
        use G8
        query "Test" do
          withArgs(a: ^my_num, b: ^my_str)
          withRequiredArgs(a: ^my_num_2, b: ^my_str_2, c: 7)
          thing do
            what(is: ^my_num_3, this: ^my_num_4, magic: ^my_str_3)
          end
        end
      end

      Q8
      """)

    assert mod.test() == %{
             "operationName" => "Test",
             "query" =>
               "query Test($my_num: Int, $my_num_2: Int!, $my_num_3: Int, $my_num_4: Int, $my_str: String, $my_str_2: String!, $my_str_3: String) {withArgs(a: $my_num, b: $my_str) withRequiredArgs(a: $my_num_2, b: $my_str_2, c: 7) thing {what(is: $my_num_3, this: $my_num_4, magic: $my_str_3)}}",
             "variables" => %{}
           }
  end

  test "variables can share pins" do
    {mod, _} =
      Code.eval_string("""
      defmodule G81 do
        use Goblet, from: "./test/schema.json"
      end

      defmodule Q81 do
        use G81
        query "Test" do
          withArgs(a: ^my_num, b: ^my_str)
          withRequiredArgs(a: ^my_num, b: ^my_str, c: ^my_num)
        end
      end

      Q81
      """)

    assert mod.test() == %{
             "operationName" => "Test",
             "query" =>
               "query Test($my_num: Int!, $my_str: String!) {withArgs(a: $my_num, b: $my_str) withRequiredArgs(a: $my_num, b: $my_str, c: $my_num)}",
             "variables" => %{}
           }
  end

  test "cannot pin same variable to different types" do
    result =
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        assert_raise RuntimeError, fn ->
          Code.eval_string("""
          defmodule G9 do
            use Goblet, from: "./test/schema.json"
          end

          defmodule Q9 do
            use G9
            query "Test" do
              withArgs(a: ^my_num, b: ^my_str)
              withRequiredArgs(a: ^my_num, b: ^my_str, c: ^my_str)
            end
          end

          Q9
          """)
        end
      end)

    assert result =~ "cannot pin my_str to both types Int and String"
  end

  test "reports missing required variables" do
    result =
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        assert_raise RuntimeError, fn ->
          Code.eval_string("""
          defmodule G10 do
            use Goblet, from: "./test/schema.json"
          end

          defmodule Q10 do
            use G10
            query "Test" do
              withRequiredArgs(a: 2)
            end
          end

          Q10
          """)
        end
      end)

    assert result =~ "RootQueryType.withRequiredArgs is missing required arg b"
  end

  test "reports extra variables" do
    result =
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        assert_raise RuntimeError, fn ->
          Code.eval_string("""
          defmodule G11 do
            use Goblet, from: "./test/schema.json"
          end

          defmodule Q11 do
            use G11
            query "Test" do
              withArgs(whoops: 8)
            end
          end

          Q11
          """)
        end
      end)

    assert result =~ "Unexpected variable whoops on RootQueryType.withArgs"
  end

  test "reports duplicate variables" do
    result =
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        assert_raise RuntimeError, fn ->
          Code.eval_string("""
          defmodule G12 do
            use Goblet, from: "./test/schema.json"
          end

          defmodule Q12 do
            use G12
            query "Test" do
              withArgs(a: 8, a: 7, b: "test")
            end
          end

          Q12
          """)
        end
      end)

    assert result =~ "RootQueryType.withArgs was passed more than one arg named a"
  end

  test "fields may be renamed with @as" do
    {mod, _} =
      Code.eval_string("""
      defmodule G13 do
        use Goblet, from: "./test/schema.json"
      end

      defmodule Q13 do
        use G13
        query "Test" do
          @as "otherThing"
          thing do
            @as "newId"
            id
          end
        end
      end

      Q13
      """)

    assert mod.test() == %{
             "operationName" => "Test",
             "query" => "query Test {otherThing:thing {newId:id}}",
             "variables" => %{}
           }
  end

  test "the @as directive must be named with a string" do
    result =
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        assert_raise RuntimeError, fn ->
          Code.eval_string("""
          defmodule G14 do
            use Goblet, from: "./test/schema.json"
          end

          defmodule Q14 do
            use G14
            query "Test" do
              @as 7
              thing do
                @as something
                id
              end
            end
          end

          Q14
          """)
        end
      end)

    assert result =~ ~s(Alias names must be a string: @as "foo")
    assert result =~ "nofile:8"
    assert result =~ "nofile:10"
  end

  test "directives other than @as are not supported" do
    result =
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        assert_raise RuntimeError, fn ->
          Code.eval_string("""
          defmodule G15 do
            use Goblet, from: "./test/schema.json"
          end

          defmodule Q15 do
            use G15
            query "Test" do
              @include something
              thing do
                id
              end
            end
          end

          Q15
          """)
        end
      end)

    assert result =~ "Directives are not yet supported"
  end

  test "directives must preceed a field" do
    result =
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        assert_raise RuntimeError, fn ->
          Code.eval_string("""
          defmodule G16 do
            use Goblet, from: "./test/schema.json"
          end

          defmodule Q16 do
            use G16
            query "Test" do
              thing do
                id
                @as "invalid"
              end
              @as "also invalid"
            end
          end

          Q16
          """)
        end
      end)

    assert result =~ "directives should always be placed before fields"
    assert result =~ "nofile:10"
    assert result =~ "nofile:12"
  end

  test "field names must be unique" do
    result =
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        assert_raise RuntimeError, fn ->
          Code.eval_string("""
          defmodule G17 do
            use Goblet, from: "./test/schema.json"
          end

          defmodule Q17 do
            use G17
            query "Test" do
              age
              age
              @as "age"
              thing do
                id
              end
            end
          end

          Q17
          """)
        end
      end)

    assert result =~ "Multiple fields found with the same name: age."
    assert result =~ "nofile:8"
    assert result =~ "nofile:9"
    assert result =~ "nofile:11"
  end
end

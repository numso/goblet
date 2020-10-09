defmodule Goblet do
  @moduledoc """
  Documentation for Goblet.
  """

  defmacro __using__(from: path) do
    # support module attributes as path? https://stackoverflow.com/questions/54000082/pass-module-attribute-as-an-argument-to-macros
    schema = path |> File.read!() |> Jason.decode!() |> Map.get("__schema") |> Macro.escape()

    quote bind_quoted: [path: path, schema: schema] do
      @external_resource path

      defmacro query(name, do: expr) do
        schema = unquote(schema |> Macro.escape())
        fn_name = name |> Macro.underscore() |> String.to_atom()
        body = Goblet.build(:query, name, expr, schema, fn_name, __CALLER__)

        if body == :error do
          reraise "There are errors in your query", Macro.Env.stacktrace(__CALLER__)
        end

        # TODO:: determine types of pinned variables and create a typespec here
        quote do
          def unquote(fn_name)(variables \\ %{}) do
            %{
              "operationName" => unquote(name),
              "query" => unquote(body),
              "variables" => variables
            }
          end

          if function_exported?(unquote(__MODULE__), :process, 2) do
            def unquote(fn_name)(variables, ctx) do
              apply(__MODULE__, unquote(fn_name), [variables])
              |> unquote(__MODULE__).process(ctx)
            end
          end
        end
      end

      defmacro mutation(name, do: expr) do
        schema = unquote(schema |> Macro.escape())
        fn_name = name |> Macro.underscore() |> String.to_atom()
        body = Goblet.build(:mutation, name, expr, schema, fn_name, __CALLER__)

        # TODO:: determine types of pinned variables and create a typespec here
        quote do
          def unquote(fn_name)(variables \\ %{}) do
            %{
              "operationName" => unquote(name),
              "query" => unquote(body),
              "variables" => variables
            }
          end

          if function_exported?(unquote(__MODULE__), :process, 2) do
            def unquote(fn_name)(variables, ctx) do
              apply(__MODULE__, unquote(fn_name), [variables])
              |> unquote(__MODULE__).process(ctx)
            end
          end
        end
      end

      defmacro __using__(_) do
        quote do
          import unquote(__MODULE__), only: [query: 2, mutation: 2]
        end
      end
    end
  end

  def build(type, name, expr, schema, fn_name, caller) do
    Goblet.Parser.parse(expr, type, schema)
    |> Goblet.Validator.validate({fn_name, caller})
    |> Goblet.Printer.print(type, name)
  end
end

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

        # TODO:: determine types of pinned variables and create a typespec here
        quote do
          def unquote(fn_name)(variables \\ %{}) do
            %{
              "operationName" => unquote(name),
              "query" =>
                "query #{unquote(name)} {#{unquote(Goblet.build(expr, schema, __CALLER__.file))}}",
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
          import unquote(__MODULE__), only: [query: 2]
        end
      end
    end
  end

  def build(expr, schema, file) do
    query_type = get_in(schema, ["queryType", "name"])
    types = Map.get(schema, "types")
    parse_gql(expr, query_type, types, file)
  end

  defp parse_gql({:__block__, _, args}, cur_type, types, file) do
    Enum.map(args, &parse_gql(&1, cur_type, types, file)) |> Enum.join(" ")
  end

  defp parse_gql({name, [line: line], rest}, cur_type, types, file) do
    field_name = Atom.to_string(name)

    case Enum.find(types, &(&1["name"] == cur_type)) do
      nil ->
        report({:error, "type #{cur_type} not found in the schema", file, line})

      type ->
        case Enum.find(type["fields"], &(&1["name"] == field_name)) do
          nil ->
            report({:error, "Could not find field #{field_name} on type #{cur_type}", file, line})

          field ->
            case {get_subfield_name(field["type"]), rest} do
              {nil, [[do: _expr]]} ->
                report({:error, "Did not expect to find a subquery on #{field_name}", file, line})

              {nil, [_variables, [do: _expr]]} ->
                report({:error, "Did not expect to find a subquery on #{field_name}", file, line})

              {nil, [variables]} ->
                "#{field_name}(#{parse_variables(variables)})"

              {nil, nil} ->
                field_name

              {nil, _} ->
                report({:error, "Not really sure what happened here...", file, line})

              {name, [variables, [do: expr]]} ->
                "#{field_name}(#{parse_variables(variables)}) {#{
                  parse_gql(expr, name, types, file)
                }}"

              {name, [[do: expr]]} ->
                "#{field_name} {#{parse_gql(expr, name, types, file)}}"

              {_, _} ->
                report(
                  {:error,
                   "Expected a subquery on #{cur_type}.#{field_name}. Are you missing a do...end?",
                   file, line}
                )
            end
        end
    end
  end

  defp parse_variables(variables) do
    # parse it correctly, strings should have quotes around them
    # if the variable is pinned, put it in the vars array, check it's type, yadda yadda
    # if it's a non-pinned variable, raise
    Keyword.keys(variables)
    |> Enum.map(fn key -> "#{Atom.to_string(key)}: #{Keyword.get(variables, key)}" end)
    |> Enum.join(", ")
  end

  defp get_subfield_name(%{"kind" => "OBJECT", "name" => name}), do: name
  defp get_subfield_name(%{"kind" => "LIST", "ofType" => type}), do: get_subfield_name(type)
  defp get_subfield_name(%{"kind" => "NON_NULL", "ofType" => type}), do: get_subfield_name(type)
  defp get_subfield_name(_), do: nil

  def report(diagnostic) do
    :ok = EditorDiagnostics.report(diagnostic)
    nil
  end
end

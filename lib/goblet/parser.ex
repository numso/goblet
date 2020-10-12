defmodule Goblet.Parser.Statement do
  defstruct line: nil,
            field: nil,
            fragment: nil,
            variables: [],
            sub_fields: nil,
            parent: nil,
            type: nil,
            attrs: []
end

defmodule Goblet.Parser.Variable do
  defstruct line: nil, key: nil, value: nil, type: nil
end

defmodule Goblet.Parser do
  @moduledoc false

  alias Goblet.Parser.{Statement, Variable}

  def parse(ast, type, schema) do
    root_type = get_root_type(type, schema)
    types = Map.get(schema, "types")
    parse_statement(ast, root_type, types)
  end

  defp get_root_type(:query, schema), do: get_in(schema, ["queryType", "name"])
  defp get_root_type(:mutation, schema), do: get_in(schema, ["mutationType", "name"])

  defp parse_statement_list([], [], _type, _types), do: []

  defp parse_statement_list([], [{_, line, _} | _], _type, _types) do
    [{:error, {"directives should always be placed before fields", line}}]
  end

  defp parse_statement_list([{:@, _, [{key, [line: line], [value]}]} | args], attrs, type, types) do
    parse_statement_list(args, attrs ++ [{key, line, value}], type, types)
  end

  defp parse_statement_list([arg | args], attrs, type, types) do
    statement = parse_statement(arg, type, types)
    statement = %Statement{statement | attrs: attrs}
    [statement | parse_statement_list(args, [], type, types)]
  end

  defp parse_statement({:__block__, _, args}, type, types) do
    parse_statement_list(args, [], type, types)
  end

  defp parse_statement({:..., [line: line], [[on: parent], [do: expr]]}, type, types)
       when is_binary(parent) do
    {full_type, next_type} = determine_union_type(parent, type, types)

    %Statement{
      line: line,
      field: parent,
      sub_fields: parse_statement(expr, next_type, types),
      fragment: true,
      parent: type,
      type: full_type
    }
  end

  defp parse_statement({name, [line: line], [[do: expr]]}, type, types) do
    {full_type, next_type} = determine_type(name, type, types)

    %Statement{
      line: line,
      field: Atom.to_string(name),
      sub_fields: parse_statement(expr, next_type, types),
      parent: type,
      type: full_type
    }
  end

  defp parse_statement({name, [line: line], [variables, [do: expr]]}, type, types) do
    {full_type, next_type} = determine_type(name, type, types)

    %Statement{
      line: line,
      field: Atom.to_string(name),
      variables: parse_variables(variables, full_type),
      sub_fields: parse_statement(expr, next_type, types),
      parent: type,
      type: full_type
    }
  end

  defp parse_statement({name, [line: line], [variables]}, type, types) do
    {full_type, _next_type} = determine_type(name, type, types)

    %Statement{
      line: line,
      field: Atom.to_string(name),
      variables: parse_variables(variables, full_type),
      parent: type,
      type: full_type
    }
  end

  defp parse_statement({name, [line: line], []}, type, types) do
    {full_type, _next_type} = determine_type(name, type, types)

    %Statement{
      line: line,
      field: Atom.to_string(name),
      parent: type,
      type: full_type
    }
  end

  defp parse_statement({name, [line: line], nil}, type, types) do
    {full_type, _next_type} = determine_type(name, type, types)

    %Statement{
      line: line,
      field: Atom.to_string(name),
      parent: type,
      type: full_type
    }
  end

  defp parse_variables(variables, type) do
    Enum.map(variables, &parse_variable(&1, type))
  end

  defp parse_variable({key, value}, type)
       when is_number(value) or is_boolean(value) or is_binary(value) do
    %Variable{
      key: key,
      value: {:value, value},
      type: determine_variable_type(type, key)
    }
  end

  defp parse_variable({key, {:^, [line: line], [{value, _, _}]}}, type) do
    %Variable{
      line: line,
      key: key,
      value: {:reference, value},
      type: determine_variable_type(type, key)
    }
  end

  defp parse_variable({key, value}, type) do
    %Variable{
      key: key,
      value: {:not_implemented, value},
      type: determine_variable_type(type, key)
    }
  end

  defp determine_type(_name, nil, _types), do: {nil, nil}

  defp determine_type(name, type, types) do
    with %{"fields" => fields} <- Enum.find(types, &(&1["name"] == type)),
         self <- Enum.find(fields, &(&1["name"] == Atom.to_string(name))),
         %{"kind" => kind, "name" => name} <- unwrap(self["type"]) do
      {self, if(kind in ["OBJECT", "INTERFACE", "UNION"], do: name)}
    else
      _ -> {nil, nil}
    end
  end

  defp determine_union_type(_name, nil, _types), do: {nil, nil}

  defp determine_union_type(name, type, types) do
    with %{"kind" => "UNION", "possibleTypes" => possibles} <-
           Enum.find(types, &(&1["name"] == type)),
         %{} <- Enum.find(possibles, &(&1["name"] == name)),
         self = %{} <- Enum.find(types, &(&1["name"] == name)) do
      {self, name}
    else
      _ -> {nil, nil}
    end
  end

  defp determine_variable_type(%{"args" => args}, key) when is_list(args) do
    Enum.find(args, &(&1["name"] == Atom.to_string(key)))
  end

  defp determine_variable_type(_type, _key), do: nil

  defp unwrap(%{"ofType" => nil} = type), do: type
  defp unwrap(%{"ofType" => type}), do: unwrap(type)
  defp unwrap(_), do: nil
end

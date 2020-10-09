defmodule Goblet.Parser do
  @moduledoc false

  defmodule Statement do
    defstruct line: nil, field: nil, variables: nil, sub_fields: nil, parent: nil, type: nil
  end

  defmodule Variable do
    defstruct line: nil, key: nil, value: nil, type: nil
  end

  def parse(ast, type, schema) do
    root_type = get_root_type(type, schema)
    types = Map.get(schema, "types")
    parse_statement(ast, root_type, types)
  end

  defp get_root_type(:query, schema), do: get_in(schema, ["queryType", "name"])
  defp get_root_type(:mutation, schema), do: get_in(schema, ["mutationType", "name"])

  defp parse_statement({:__block__, _, args}, type, types) do
    Enum.map(args, &parse_statement(&1, type, types))
  end

  defp parse_statement({name, [line: line], [[do: expr]]}, type, types) do
    {cur_type, next_type} = determine_type(name, type, types)

    %Statement{
      line: line,
      field: name,
      sub_fields: parse_statement(expr, next_type, types),
      parent: type,
      type: cur_type
    }
  end

  defp parse_statement({name, [line: line], [variables, [do: expr]]}, type, types) do
    {cur_type, next_type} = determine_type(name, type, types)

    %Statement{
      line: line,
      field: name,
      variables: parse_variables(variables, cur_type),
      sub_fields: parse_statement(expr, next_type, types),
      parent: type,
      type: cur_type
    }
  end

  defp parse_statement({name, [line: line], [variables]}, type, types) do
    {cur_type, _next_type} = determine_type(name, type, types)

    %Statement{
      line: line,
      field: name,
      variables: parse_variables(variables, cur_type),
      parent: type,
      type: cur_type
    }
  end

  defp parse_statement({name, [line: line], []}, type, types) do
    {cur_type, _next_type} = determine_type(name, type, types)

    %Statement{
      line: line,
      field: name,
      parent: type,
      type: cur_type
    }
  end

  defp parse_statement({name, [line: line], nil}, type, types) do
    {cur_type, _next_type} = determine_type(name, type, types)

    %Statement{
      line: line,
      field: name,
      parent: type,
      type: cur_type
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
    case Enum.find(types, &(&1["name"] == type)) do
      %{"fields" => fields} ->
        case Enum.find(fields, &(&1["name"] == Atom.to_string(name))) do
          %{"type" => type} = self ->
            case unwrap(type) do
              %{"kind" => "OBJECT", "name" => name} -> {self, name}
              _ -> {self, nil}
            end

          _ ->
            {nil, nil}
        end

      _ ->
        {nil, nil}
    end
  end

  defp determine_variable_type(%{"args" => args}, key) when is_list(args) do
    Enum.find(args, &(&1["name"] == Atom.to_string(key)))
  end

  defp determine_variable_type(_type, _key), do: nil

  defp unwrap(%{"ofType" => nil} = type), do: type
  defp unwrap(%{"ofType" => type}), do: unwrap(type)
end

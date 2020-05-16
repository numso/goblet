defmodule Goblet.Diagnostics do
  @moduledoc false

  def error(message, ctx), do: do_report(message, ctx, {IO, :warn})
  def warn(message, ctx), do: do_report(message, ctx, {IO, :warn})
  def critical(message, ctx), do: do_report(message, ctx, {Kernel, :reraise})

  defp do_report(message, %{err_ctx: {name, caller}, line: line}, {mod, fun}) do
    trace = Macro.Env.stacktrace(%{caller | line: line, function: {name, 0}})
    apply(mod, fun, [message, trace])
  end
end

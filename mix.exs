defmodule Goblet.MixProject do
  use Mix.Project

  def project do
    [
      app: :goblet,
      version: "0.1.4",
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      description: "Something to help you consume that sweet, sweet absinthe.",
      homepage_url: "https://github.com/numso/goblet",
      source_url: "https://github.com/numso/goblet"
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, ">= 0.0.0", only: :dev},
      {:jason, "~> 1.0"},
      {:mix_test_watch, "~> 1.0", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["Dallin Osmun"],
      licenses: ["MIT"],
      links: %{github: "https://github.com/numso/goblet"}
    ]
  end
end

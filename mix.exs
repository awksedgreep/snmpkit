defmodule Snmpkit.MixProject do
  use Mix.Project

  def project do
    [
      app: :snmpkit,
      version: "1.2.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      test_pattern: "**/*_test.exs",
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ],
      compilers: [:yecc] ++ Mix.compilers(),
      deps: deps(),
      dialyzer: dialyzer(),

      # Hex package metadata
      description: description(),
      package: package(),
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :crypto, :parsetools],
      mod: {Snmpkit.Application, []}
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Core dependencies
      {:jason, "~> 1.4"},
      {:yaml_elixir, "~> 2.9", optional: true},
      {:telemetry, "~> 1.0", optional: true},

      # Development and test dependencies
      {:ex_doc, "~> 0.29", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:benchee, "~> 1.1", only: [:dev, :test]},
      {:stream_data, "~> 0.5", only: :test}
    ]
  end

  defp description do
    """
    A comprehensive SNMP toolkit for Elixir featuring a unified API, pure Elixir
    implementation, and powerful device simulation. Perfect for network monitoring,
    testing, and development with support for SNMP operations, MIB management,
    and realistic device simulation.
    """
  end

  defp package do
    [
      name: "snmpkit",
      maintainers: ["SnmpKit Team"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/awksedgreep/snmpkit",
        "Documentation" => "https://hexdocs.pm/snmpkit"
      },
      files: ~w(lib priv src mix.exs README.md LICENSE.md),
      exclude_patterns: ["priv/walks/*"]
    ]
  end

  defp docs do
    [
      main: "api-reference",
      extras: [
        "README.md",
        "CONTRIBUTING.md",
        "LICENSE",
        "docs/mib-guide.md",
        "docs/testing-guide.md",
        "docs/unified-api-guide.md",
        "docs/enriched-output-migration.md",
        "docs/concurrent-multi.md",
        "docs/v0.2.0-release-notes.md",
        "docs/v0.3.0-release-notes.md",
        "docs/v0.3.1-release-notes.md",
        "docs/v0.3.2-release-notes.md",
        "docs/v0.3.3-release-notes.md",
        "docs/v0.3.4-release-notes.md",
        "docs/v0.3.5-release-notes.md",
        "docs/v0.4.0-release-notes.md",
        "livebooks/snmpkit_tour.livemd",
        "examples/README.md"
      ],
      groups_for_modules: [
        "Core API": [
          SnmpKit,
          SnmpKit.SNMP,
          SnmpKit.MIB,
          SnmpKit.Sim
        ],
        "SNMP Protocol": [
          SnmpKit.SnmpLib,
          SnmpKit.SnmpLib.Types,
          SnmpKit.SnmpLib.Pdu,
          SnmpKit.SnmpLib.Message,
          SnmpKit.SnmpLib.Oid
        ],
        "MIB Support": [
          SnmpKit.MibParser,
          SnmpKit.SnmpMgr.MIB,
          SnmpKit.SnmpLib.MIB
        ],
        "Device Simulation": [
          SnmpKit.SnmpSim,
          SnmpKit.SnmpSim.Device,
          SnmpKit.SnmpSim.ProfileLoader
        ],
        "Network Management": [
          SnmpKit.SnmpMgr,
          SnmpKit.TestSupport
        ]
      ]
    ]
  end

  defp dialyzer do
    [
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      plt_add_apps: [:mix, :ex_unit],
      ignore_warnings: ".dialyzer_ignore.exs",
      flags: [
        :error_handling,
        :underspecs,
        :unknown
      ]
    ]
  end
end

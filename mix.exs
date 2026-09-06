defmodule Snmpkit.MixProject do
  use Mix.Project

  def project do
    [
      app: :snmpkit,
      version: "2.0.0-dev",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      test_coverage: [tool: ExCoveralls],
      compilers: [:yecc] ++ Mix.compilers(),
      deps: deps(),
      dialyzer: dialyzer(),
      aliases: aliases(),

      # Hex package metadata
      description: description(),
      package: package(),
      docs: docs()
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
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
      {:telemetry, "~> 1.2"},

      # Development and test dependencies
      {:ex_doc, "~> 0.29", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:benchee, "~> 1.1", only: [:dev, :test]},
      {:stream_data, "~> 1.1", only: :test}
    ]
  end

  defp aliases do
    [
      # Static checks used in CI: formatting, credo (strict), dialyzer
      lint: ["format --check-formatted", "credo --strict", "dialyzer"]
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
      files: ~w(lib priv/walks src mix.exs README.md LICENSE.md)
    ]
  end

  defp docs do
    [
      main: "api-reference",
      extras: [
        "README.md",
        "docs/v2-migration.md",
        "CONTRIBUTING.md",
        "LICENSE",
        "docs/mib-guide.md",
        "docs/testing-guide.md",
        "docs/unified-api-guide.md",
        "docs/enriched-output-migration.md",
        "docs/concurrent-multi.md",
        "docs/mib-parser-oracle.md",
        "docs/v1.4.0-release-notes.md",
        "docs/v1.3.24-release-notes.md",
        "docs/v1.3.23-release-notes.md",
        "docs/v1.3.22-release-notes.md",
        "docs/v1.3.21-release-notes.md",
        "TIMEOUT_DOCUMENTATION.md",
        "docs/v0.2.0-release-notes.md",
        "docs/v0.3.0-release-notes.md",
        "docs/v0.3.1-release-notes.md",
        "docs/v0.3.2-release-notes.md",
        "docs/v0.3.3-release-notes.md",
        "docs/v0.3.4-release-notes.md",
        "docs/v0.3.5-release-notes.md",
        "docs/v0.4.0-release-notes.md",
        "livebooks/01_quickstart.livemd",
        "livebooks/02_snmp_operations.livemd",
        "livebooks/03_mib_management.livemd",
        "livebooks/04_device_simulation.livemd",
        "livebooks/05_high_performance.livemd",
        "livebooks/06_snmp_agent.livemd",
        "livebooks/07_snmpv3.livemd",
        "examples/README.md"
      ],
      groups_for_modules: [
        "Core API": [
          SnmpKit,
          SnmpKit.SNMP,
          SnmpKit.MIB,
          SnmpKit.Sim,
          SnmpKit.Agent,
          SnmpKit.Trap,
          SnmpKit.Telemetry,
          SnmpKit.SNMP.Rate
        ],
        "SNMP Protocol": [
          SnmpKit.SnmpLib,
          SnmpKit.SnmpLib.ASN1,
          SnmpKit.SnmpLib.Types,
          SnmpKit.SnmpLib.Types.Validation,
          SnmpKit.SnmpLib.Types.Format,
          SnmpKit.SnmpLib.PDU,
          SnmpKit.SnmpLib.PDU.Builder,
          SnmpKit.SnmpLib.PDU.Constants,
          SnmpKit.SnmpLib.PDU.Decoder,
          SnmpKit.SnmpLib.PDU.Encoder,
          SnmpKit.SnmpLib.PDU.V3Encoder,
          SnmpKit.SnmpLib.OID,
          SnmpKit.SnmpLib.Transport,
          SnmpKit.SnmpLib.Manager,
          SnmpKit.SnmpLib.Manager.Request,
          SnmpKit.SnmpLib.Manager.Response,
          SnmpKit.SnmpLib.Walker,
          SnmpKit.SnmpLib.HostParser,
          SnmpKit.SnmpLib.Error,
          SnmpKit.SnmpLib.ErrorHandler,
          SnmpKit.SnmpLib.Utils
        ],
        "SNMP Agent": [
          SnmpKit.Agent.Handler,
          SnmpKit.Agent.Store,
          SnmpKit.Agent.Table,
          SnmpKit.Agent.Request
        ],
        "SNMPv3 Security": [
          SnmpKit.SnmpLib.Security,
          SnmpKit.SnmpLib.Security.EngineCache,
          SnmpKit.SnmpLib.Manager.V3,
          SnmpKit.SnmpSim.Core.UsmAgent,
          SnmpKit.SnmpLib.Security.Auth,
          SnmpKit.SnmpLib.Security.Keys,
          SnmpKit.SnmpLib.Security.Priv,
          SnmpKit.SnmpLib.Security.USM
        ],
        "MIB Support": [
          SnmpKit.SnmpMgr.MIB,
          SnmpKit.MIB.Builtin,
          SnmpKit.MIB.Resolver,
          SnmpKit.MIB.Import,
          SnmpKit.MIB.Compiler,
          SnmpKit.MIB.Parser,
          SnmpKit.MIB.Registry,
          SnmpKit.MIB.Syntax,
          SnmpKit.MIB.DisplayHint,
          SnmpKit.MIB.TableIndex,
          SnmpKit.MIB.Lint
        ],
        "Network Management": [
          SnmpKit.SnmpMgr,
          SnmpKit.SnmpMgr.Notify,
          SnmpKit.SnmpMgr.Config,
          SnmpKit.SnmpMgr.Core,
          SnmpKit.SnmpMgr.Walk,
          SnmpKit.SnmpMgr.Bulk,
          SnmpKit.SnmpMgr.Table,
          SnmpKit.SnmpMgr.Multi,
          SnmpKit.SnmpMgr.Format,
          SnmpKit.SnmpMgr.Target,
          SnmpKit.SnmpMgr.Types,
          SnmpKit.SnmpMgr.Stream,
          SnmpKit.SnmpMgr.AdaptiveWalk
        ],
        "Manager Infrastructure": [
          SnmpKit.SnmpMgr.Engine,
          SnmpKit.SnmpMgr.RequestIdGenerator
        ],
        "Device Simulation": [
          SnmpKit.SnmpSim,
          SnmpKit.SnmpSim.Device,
          SnmpKit.SnmpSim.ProfileLoader,
          SnmpKit.SnmpSim.Recorder,
          SnmpKit.SnmpSim.WalkParser,
          SnmpKit.SnmpSim.Config,
          SnmpKit.SnmpSim.SafeFile,
          SnmpKit.SnmpSim.OIDTree,
          SnmpKit.SnmpSim.ValueSimulator,
          SnmpKit.SnmpSim.ValueSimulator.Counters,
          SnmpKit.SnmpSim.ValueSimulator.Patterns,
          SnmpKit.SnmpSim.ValueSimulator.Variance,
          SnmpKit.SnmpSim.Device.Metrics,
          SnmpKit.SnmpSim.TimePatterns,
          SnmpKit.SnmpSim.MIB.SharedProfiles,
          SnmpKit.SnmpSim.MIB.BehaviorAnalyzer,
          SnmpKit.SnmpSim.Core.Server,
          SnmpKit.SnmpSim.Device.OidHandler,
          SnmpKit.SnmpSim.Device.PduProcessor,
          SnmpKit.SnmpSim.Device.WalkPduProcessor,
          SnmpKit.SnmpSim.Device.ModemUpgrade,
          SnmpKit.SnmpSim.ErrorInjector,
          SnmpKit.SnmpSim.Device.ErrorConditions,
          SnmpKit.SnmpSim.LazyDevicePool,
          SnmpKit.SnmpSim.DeviceDistribution,
          SnmpKit.SnmpSim.CorrelationEngine
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

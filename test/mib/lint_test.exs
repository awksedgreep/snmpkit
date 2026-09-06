defmodule SnmpKit.MIB.LintTest do
  use ExUnit.Case, async: true

  alias SnmpKit.MIB.Lint

  defp codes(report), do: report.findings |> Enum.map(& &1.code) |> Enum.sort()
  defp with_code(report, code), do: Enum.filter(report.findings, &(&1.code == code))

  @clean """
  LINT-CLEAN-MIB DEFINITIONS ::= BEGIN
  IMPORTS MODULE-IDENTITY, OBJECT-TYPE, Integer32, enterprises FROM SNMPv2-SMI
          DisplayString FROM SNMPv2-TC;

  lintClean MODULE-IDENTITY
    LAST-UPDATED "202401010000Z"
    ORGANIZATION "test"
    CONTACT-INFO "test"
    DESCRIPTION "clean module"
    ::= { enterprises 99990 }

  lintObjects OBJECT IDENTIFIER ::= { lintClean 1 }

  lintName OBJECT-TYPE
    SYNTAX DisplayString (SIZE (0..64))
    MAX-ACCESS read-only
    STATUS current
    DESCRIPTION "name"
    ::= { lintObjects 1 }

  lintPeerTable OBJECT-TYPE
    SYNTAX SEQUENCE OF LintPeerEntry
    MAX-ACCESS not-accessible
    STATUS current
    DESCRIPTION "peers"
    ::= { lintObjects 2 }

  lintPeerEntry OBJECT-TYPE
    SYNTAX LintPeerEntry
    MAX-ACCESS not-accessible
    STATUS current
    DESCRIPTION "peer"
    INDEX { lintPeerIndex }
    ::= { lintPeerTable 1 }

  LintPeerEntry ::= SEQUENCE {
    lintPeerIndex Integer32,
    lintPeerName DisplayString
  }

  lintPeerIndex OBJECT-TYPE
    SYNTAX Integer32 (1..1024)
    MAX-ACCESS not-accessible
    STATUS current
    DESCRIPTION "index"
    ::= { lintPeerEntry 1 }

  lintPeerName OBJECT-TYPE
    SYNTAX DisplayString
    MAX-ACCESS read-only
    STATUS current
    DESCRIPTION "name"
    ::= { lintPeerEntry 2 }
  END
  """

  test "a well-formed SMIv2 module has no findings" do
    assert {:ok, report} = Lint.check(@clean)
    assert report.findings == [], inspect(report.findings)
    assert report.errors == 0 and report.warnings == 0
    assert report.name == "LINT-CLEAN-MIB"
  end

  test "unresolved parents, duplicate OIDs, unknown types and duplicate names are errors" do
    mib = """
    LINT-BAD-MIB DEFINITIONS ::= BEGIN
    IMPORTS MODULE-IDENTITY, OBJECT-TYPE, Integer32, enterprises FROM SNMPv2-SMI;

    lintBad MODULE-IDENTITY
      LAST-UPDATED "202401010000Z"
      ORGANIZATION "test"
      CONTACT-INFO "test"
      DESCRIPTION "bad module"
      ::= { enterprises 99991 }

    orphan OBJECT-TYPE
      SYNTAX Integer32
      MAX-ACCESS read-only
      STATUS current
      DESCRIPTION "parent does not exist"
      ::= { noSuchParent 1 }

    first OBJECT-TYPE
      SYNTAX Integer32
      MAX-ACCESS read-only
      STATUS current
      DESCRIPTION "one"
      ::= { lintBad 1 }

    second OBJECT-TYPE
      SYNTAX Integer32
      MAX-ACCESS read-only
      STATUS current
      DESCRIPTION "same OID as first"
      ::= { lintBad 1 }

    typed OBJECT-TYPE
      SYNTAX NoSuchType
      MAX-ACCESS read-only
      STATUS current
      DESCRIPTION "unknown type"
      ::= { lintBad 2 }

    typed OBJECT-TYPE
      SYNTAX Integer32
      MAX-ACCESS read-only
      STATUS current
      DESCRIPTION "duplicate name"
      ::= { lintBad 3 }
    END
    """

    assert {:ok, report} = Lint.check(mib)
    assert :unresolved_parent in codes(report)
    assert :duplicate_oid in codes(report)
    assert :unknown_type in codes(report)
    assert :duplicate_name in codes(report)
    assert report.errors >= 4

    assert [%{name: "orphan", severity: :error, line: line}] =
             with_code(report, :unresolved_parent)

    assert is_integer(line)
    assert [%{message: message}] = with_code(report, :duplicate_oid)
    assert message =~ "same OID as `first'"
  end

  test "SMIv1 constructs in an SMIv2 module and a missing MODULE-IDENTITY are warnings" do
    mib = """
    LINT-MIXED-MIB DEFINITIONS ::= BEGIN
    IMPORTS OBJECT-TYPE, Integer32, enterprises FROM SNMPv2-SMI;

    lintMixed OBJECT IDENTIFIER ::= { enterprises 99992 }

    oldStyle OBJECT-TYPE
      SYNTAX INTEGER
      ACCESS read-only
      STATUS mandatory
      DESCRIPTION "v1 object"
      ::= { lintMixed 1 }
    END
    """

    assert {:ok, report} = Lint.check(mib)
    assert :smiv1_in_smiv2 in codes(report)
    assert :missing_module_identity in codes(report)
    assert report.errors == 0
  end

  test "table problems: no INDEX, index without SIZE, SEQUENCE mismatches" do
    mib = """
    LINT-TABLE-MIB DEFINITIONS ::= BEGIN
    IMPORTS MODULE-IDENTITY, OBJECT-TYPE, Integer32, enterprises FROM SNMPv2-SMI;

    lintTable MODULE-IDENTITY
      LAST-UPDATED "202401010000Z"
      ORGANIZATION "test"
      CONTACT-INFO "test"
      DESCRIPTION "tables"
      ::= { enterprises 99993 }

    aTable OBJECT-TYPE
      SYNTAX SEQUENCE OF AEntry
      MAX-ACCESS not-accessible
      STATUS current
      DESCRIPTION "table"
      ::= { lintTable 1 }

    aEntry OBJECT-TYPE
      SYNTAX AEntry
      MAX-ACCESS not-accessible
      STATUS current
      DESCRIPTION "row without INDEX"
      ::= { aTable 1 }

    AEntry ::= SEQUENCE {
      aKey OCTET STRING,
      aGhost Integer32,
      aValue OCTET STRING
    }

    aKey OBJECT-TYPE
      SYNTAX OCTET STRING
      MAX-ACCESS not-accessible
      STATUS current
      DESCRIPTION "unbounded string index"
      ::= { aEntry 1 }

    aValue OBJECT-TYPE
      SYNTAX Integer32
      MAX-ACCESS read-only
      STATUS current
      DESCRIPTION "type differs from SEQUENCE"
      ::= { aEntry 2 }

    aExtra OBJECT-TYPE
      SYNTAX Integer32
      MAX-ACCESS read-only
      STATUS current
      DESCRIPTION "not in SEQUENCE"
      ::= { aEntry 3 }

    bTable OBJECT-TYPE
      SYNTAX SEQUENCE OF BEntry
      MAX-ACCESS not-accessible
      STATUS current
      DESCRIPTION "table"
      ::= { lintTable 2 }

    bEntry OBJECT-TYPE
      SYNTAX BEntry
      MAX-ACCESS not-accessible
      STATUS current
      DESCRIPTION "row"
      INDEX { bKey }
      ::= { bTable 1 }

    BEntry ::= SEQUENCE { bKey OCTET STRING }

    bKey OBJECT-TYPE
      SYNTAX OCTET STRING
      MAX-ACCESS not-accessible
      STATUS current
      DESCRIPTION "no size"
      ::= { bEntry 1 }
    END
    """

    assert {:ok, report} = Lint.check(mib)
    assert :row_without_index in codes(report)
    assert :index_without_size in codes(report)
    assert :sequence_field_undefined in codes(report)
    assert :column_not_in_sequence in codes(report)
    assert :sequence_type_mismatch in codes(report)
    assert [%{name: "bKey"}] = with_code(report, :index_without_size)
    assert [%{name: "aValue"}] = with_code(report, :sequence_type_mismatch)
  end

  test "imports from unavailable modules are warnings, satisfied by context" do
    smi = """
    LINT-VENDOR-SMI DEFINITIONS ::= BEGIN
    IMPORTS MODULE-IDENTITY, enterprises FROM SNMPv2-SMI
            TEXTUAL-CONVENTION FROM SNMPv2-TC;
    lintVendor MODULE-IDENTITY
      LAST-UPDATED "202401010000Z"
      ORGANIZATION "test"
      CONTACT-INFO "test"
      DESCRIPTION "vendor root"
      ::= { enterprises 99994 }
    lintVendorProducts OBJECT IDENTIFIER ::= { lintVendor 1 }
    VendorStatus ::= TEXTUAL-CONVENTION
      STATUS current
      DESCRIPTION "status"
      SYNTAX INTEGER { ok(1), failed(2) }
    END
    """

    product = """
    LINT-PRODUCT-MIB DEFINITIONS ::= BEGIN
    IMPORTS MODULE-IDENTITY, OBJECT-TYPE FROM SNMPv2-SMI
            lintVendorProducts, VendorStatus FROM LINT-VENDOR-SMI;
    lintProduct MODULE-IDENTITY
      LAST-UPDATED "202401010000Z"
      ORGANIZATION "test"
      CONTACT-INFO "test"
      DESCRIPTION "product"
      ::= { lintVendorProducts 7 }
    lintProductStatus OBJECT-TYPE
      SYNTAX VendorStatus
      MAX-ACCESS read-only
      STATUS current
      DESCRIPTION "status"
      ::= { lintProduct 1 }
    END
    """

    assert {:ok, alone} = Lint.check(product)
    assert Enum.all?(alone.findings, &(&1.code == :unknown_import)), inspect(alone.findings)
    assert alone.errors == 0 and alone.warnings >= 1

    {:ok, compiled_smi} = SnmpKit.MIB.compile_string(smi)
    assert {:ok, together} = Lint.check(product, context: [compiled_smi])
    assert together.findings == [], inspect(together.findings)
  end

  test "notifications referencing unknown objects are reported" do
    mib = """
    LINT-NOTIF-MIB DEFINITIONS ::= BEGIN
    IMPORTS MODULE-IDENTITY, NOTIFICATION-TYPE, enterprises FROM SNMPv2-SMI;
    lintNotif MODULE-IDENTITY
      LAST-UPDATED "202401010000Z"
      ORGANIZATION "test"
      CONTACT-INFO "test"
      DESCRIPTION "notifications"
      ::= { enterprises 99989 }
    lintAlarm NOTIFICATION-TYPE
      OBJECTS { sysDescr, noSuchObject }
      STATUS current
      DESCRIPTION "alarm"
      ::= { lintNotif 1 }
    END
    """

    assert {:ok, report} = Lint.check(mib)
    assert [%{code: :unknown_object, message: message}] = with_code(report, :unknown_object)
    assert message =~ "noSuchObject"
  end

  test "real fixture MIBs check without crashing and report parser warnings" do
    for file <- [
          "test/fixtures/mibs/working/IF-MIB.mib",
          "test/fixtures/mibs/docsis/DOCS-IF-MIB",
          "test/fixtures/mibs/topvision/PRIVATE_MIB_FILES/TOPVISION-CCMTS-MIB.mib"
        ] do
      assert {:ok, report} = Lint.check(file)
      assert is_integer(report.errors)
    end

    {:ok, ccmts} =
      Lint.check("test/fixtures/mibs/topvision/PRIVATE_MIB_FILES/TOPVISION-CCMTS-MIB.mib")

    assert :parser_warning in codes(ccmts)
    assert Lint.format(hd(ccmts.findings), "x.mib") =~ ~r/^x\.mib:\d+: (warning|error): \[/
  end
end

defmodule SnmpKit.SafeFileTest do
  use ExUnit.Case, async: true

  alias SnmpKit.SafeFile

  @moduletag :tmp_dir

  setup %{tmp_dir: dir} do
    root = Path.join(dir, "root")
    elsewhere = Path.join(dir, "elsewhere")
    File.mkdir_p!(Path.join(root, "sub"))
    File.mkdir_p!(elsewhere)

    inside = Path.join([root, "sub", "inside.txt"])
    outside = Path.join(elsewhere, "outside.txt")
    File.write!(inside, "hello")
    File.write!(outside, "secret")

    %{root: root, elsewhere: elsewhere, inside: inside, outside: outside}
  end

  describe "roots confinement" do
    test "reads a file under an allowed root", %{root: root, inside: inside} do
      assert {:ok, "hello"} = SafeFile.read(inside, roots: [root])
      assert {:ok, ^inside} = SafeFile.check(inside, roots: [root])
    end

    test "refuses a file outside every root", %{root: root, outside: outside} do
      assert {:error, :outside_allowed_roots} = SafeFile.read(outside, roots: [root])
      assert {:error, :outside_allowed_roots} = SafeFile.stream(outside, roots: [root])
    end

    test "a root only matches whole path components", %{root: root, tmp_dir: dir} do
      sibling = Path.join(dir, "root-2")
      File.mkdir_p!(sibling)
      path = Path.join(sibling, "file.txt")
      File.write!(path, "x")

      assert {:error, :outside_allowed_roots} = SafeFile.read(path, roots: [root])
    end

    test "a symlink inside a root that escapes it is refused", %{
      root: root,
      outside: outside
    } do
      link = Path.join(root, "escape.txt")
      :ok = File.ln_s(outside, link)

      assert {:error, :outside_allowed_roots} = SafeFile.read(link, roots: [root])
    end

    test "a symlink that stays inside the root resolves to its target", %{
      root: root,
      inside: inside
    } do
      link = Path.join(root, "alias.txt")
      :ok = File.ln_s(inside, link)

      assert {:ok, ^inside} = SafeFile.check(link, roots: [root])
      assert {:ok, "hello"} = SafeFile.read(link, roots: [root])
    end

    test "a symlink loop is refused", %{root: root} do
      a = Path.join(root, "a")
      b = Path.join(root, "b")
      :ok = File.ln_s(b, a)
      :ok = File.ln_s(a, b)

      assert {:error, :eloop} = SafeFile.read(a, roots: [root])
    end

    test "nil or empty roots mean unconfined", %{outside: outside} do
      assert {:ok, "secret"} = SafeFile.read(outside, roots: nil)
      assert {:ok, "secret"} = SafeFile.read(outside, roots: [])
    end

    test "the default configuration is unconfined", %{outside: outside} do
      assert SafeFile.configured_roots() == nil
      assert {:ok, "secret"} = SafeFile.read(outside)
    end
  end

  describe "size cap" do
    test "refuses files above max_bytes before reading them", %{inside: inside} do
      assert {:error, :file_too_large} = SafeFile.read(inside, max_bytes: 4)
      assert {:error, :file_too_large} = SafeFile.stream(inside, max_bytes: 4)
      assert {:ok, "hello"} = SafeFile.read(inside, max_bytes: 5)
    end

    test "the default cap is 64 MiB" do
      assert SafeFile.configured_max_bytes() == 64 * 1024 * 1024
    end
  end

  describe "other errors" do
    test "directories and missing files surface as posix errors", %{root: root} do
      assert {:error, :eisdir} = SafeFile.read(root)
      assert {:error, :enoent} = SafeFile.read(Path.join(root, "missing.txt"))
    end

    test "stream/2 yields the file's lines", %{inside: inside} do
      assert {:ok, stream} = SafeFile.stream(inside)
      assert Enum.to_list(stream) == ["hello"]
    end
  end

  test "SnmpKit.SnmpSim.SafeFile keeps working as an alias", %{root: root, inside: inside} do
    assert {:ok, "hello"} = SnmpKit.SnmpSim.SafeFile.read(inside, roots: [root])
    assert {:error, :file_too_large} = SnmpKit.SnmpSim.SafeFile.check(inside, max_bytes: 1)
    assert SnmpKit.SnmpSim.SafeFile.configured_roots() == SafeFile.configured_roots()
  end
end

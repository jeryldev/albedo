defmodule Albedo.Agents.ArchitectureTest do
  use ExUnit.Case, async: true

  alias Albedo.TestSupport.Mocks

  describe "structure analysis" do
    setup do
      dir = Mocks.create_temp_dir()
      on_exit(fn -> Mocks.cleanup_temp_dir(dir) end)
      {:ok, dir: dir}
    end

    test "analyzes elixir structure", %{dir: dir} do
      File.mkdir_p!(Path.join(dir, "lib"))
      File.write!(Path.join([dir, "lib", "my_app.ex"]), "defmodule MyApp do\nend")
      File.write!(Path.join([dir, "lib", "helper.ex"]), "defmodule Helper do\nend")

      result = analyze_structure(dir, :elixir)

      assert result[:contexts] == []
      assert is_list(result[:modules])
      assert "my_app" in result[:modules]
      assert "helper" in result[:modules]
    end

    test "returns empty for unknown project type", %{dir: dir} do
      result = analyze_structure(dir, :unknown)

      assert result == %{contexts: [], entry_points: []}
    end
  end

  describe "Phoenix structure analysis" do
    setup do
      dir = Mocks.create_temp_dir()
      setup_phoenix_project(dir)
      on_exit(fn -> Mocks.cleanup_temp_dir(dir) end)
      {:ok, dir: dir}
    end

    test "detects app name", %{dir: dir} do
      result = analyze_phoenix_structure(dir)

      assert result[:app_name] == "my_app"
    end

    test "finds contexts", %{dir: dir} do
      result = analyze_phoenix_structure(dir)

      assert is_list(result[:contexts])
      context_names = Enum.map(result[:contexts], & &1.name)
      assert "accounts" in context_names
    end

    test "finds entry points from router", %{dir: dir} do
      result = analyze_phoenix_structure(dir)

      assert is_list(result[:entry_points])

      router_entry = Enum.find(result[:entry_points], fn {type, _} -> type == :router end)
      assert router_entry != nil

      {_type, routes} = router_entry
      refute Enum.empty?(routes)
    end
  end

  describe "context finding" do
    setup do
      dir = Mocks.create_temp_dir()
      on_exit(fn -> Mocks.cleanup_temp_dir(dir) end)
      {:ok, dir: dir}
    end

    test "finds schemas in context", %{dir: dir} do
      context_path = Path.join(dir, "accounts")
      File.mkdir_p!(context_path)

      File.write!(Path.join(context_path, "user.ex"), """
      defmodule MyApp.Accounts.User do
        use Ecto.Schema
      end
      """)

      schemas = find_schemas(context_path)

      assert is_list(schemas)
    end

    test "finds context functions", %{dir: dir} do
      File.write!(Path.join(dir, "accounts.ex"), """
      defmodule MyApp.Accounts do
        def get_user(id), do: Repo.get(User, id)
        def list_users(), do: Repo.all(User)
        def create_user(attrs), do: User.changeset(attrs)
      end
      """)

      functions = find_context_functions(dir, "accounts", "my_app")

      assert is_list(functions)
      assert "get_user" in functions
      assert "list_users" in functions
      assert "create_user" in functions
    end

    test "returns empty list for missing context file", %{dir: dir} do
      functions = find_context_functions(dir, "missing", "my_app")
      assert functions == []
    end
  end

  describe "umbrella structure" do
    setup do
      dir = Mocks.create_temp_dir()
      setup_umbrella_project(dir)
      on_exit(fn -> Mocks.cleanup_temp_dir(dir) end)
      {:ok, dir: dir}
    end

    test "detects umbrella apps", %{dir: dir} do
      result = analyze_umbrella_structure(dir)

      assert result[:type] == :umbrella
      assert is_list(result[:apps])
      app_names = Enum.map(result[:apps], & &1.name)
      assert "core" in app_names
      assert "web" in app_names
    end
  end

  defp analyze_structure(path, project_type) do
    case project_type do
      :phoenix -> analyze_phoenix_structure(path)
      :elixir -> analyze_elixir_structure(path)
      :umbrella -> analyze_umbrella_structure(path)
      _ -> %{contexts: [], entry_points: []}
    end
  end

  defp analyze_phoenix_structure(path) do
    lib_path = Path.join(path, "lib")

    app_name =
      case File.ls(lib_path) do
        {:ok, entries} ->
          entries
          |> Enum.reject(&String.ends_with?(&1, "_web"))
          |> Enum.find(fn entry ->
            File.dir?(Path.join(lib_path, entry))
          end)

        _ ->
          nil
      end

    contexts =
      if app_name do
        app_path = Path.join(lib_path, app_name)
        find_contexts(app_path, app_name)
      else
        []
      end

    entry_points = find_entry_points(path, app_name)

    %{
      app_name: app_name,
      contexts: contexts,
      entry_points: entry_points
    }
  end

  defp analyze_elixir_structure(path) do
    lib_path = Path.join(path, "lib")

    modules =
      case Albedo.Search.FileScanner.find_files(lib_path, "*.ex") do
        {:ok, files} -> Enum.map(files, &Path.basename(&1, ".ex"))
        _ -> []
      end

    %{
      contexts: [],
      modules: modules,
      entry_points: []
    }
  end

  defp analyze_umbrella_structure(path) do
    apps_path = Path.join(path, "apps")

    apps =
      case File.ls(apps_path) do
        {:ok, entries} ->
          entries
          |> Enum.filter(fn entry ->
            File.dir?(Path.join(apps_path, entry))
          end)
          |> Enum.map(fn app ->
            app_path = Path.join(apps_path, app)
            %{name: app, contexts: find_contexts(Path.join([app_path, "lib", app]), app)}
          end)

        _ ->
          []
      end

    %{
      type: :umbrella,
      apps: apps,
      contexts: Enum.flat_map(apps, & &1.contexts),
      entry_points: []
    }
  end

  defp find_contexts(app_path, _app_name) do
    case File.ls(app_path) do
      {:ok, entries} ->
        entries
        |> Enum.filter(fn entry ->
          full_path = Path.join(app_path, entry)
          File.dir?(full_path)
        end)
        |> Enum.map(fn dir ->
          context_path = Path.join(app_path, dir)
          schemas = find_schemas(context_path)

          %{
            name: dir,
            schemas: schemas
          }
        end)

      _ ->
        []
    end
  end

  defp find_schemas(context_path) do
    case Albedo.Search.Ripgrep.search("use.*Schema|use Ecto.Schema",
           path: context_path,
           type: "elixir"
         ) do
      {:ok, results} ->
        results
        |> Enum.map(& &1.file)
        |> Enum.map(&Path.basename(&1, ".ex"))
        |> Enum.uniq()

      _ ->
        []
    end
  end

  defp find_context_functions(app_path, context_name, _app_name) do
    context_file = Path.join(app_path, "#{context_name}.ex")

    if File.exists?(context_file) do
      case File.read(context_file) do
        {:ok, content} ->
          Regex.scan(~r/def\s+(\w+)\s*\(/, content)
          |> Enum.map(fn [_, name] -> name end)
          |> Enum.uniq()

        _ ->
          []
      end
    else
      []
    end
  end

  @max_routes 20

  defp find_entry_points(path, app_name) do
    entry_points = []

    router_path = Path.join([path, "lib", "#{app_name}_web", "router.ex"])

    entry_points =
      if File.exists?(router_path) do
        case File.read(router_path) do
          {:ok, content} ->
            routes =
              Regex.scan(~r/(get|post|put|patch|delete|live)\s+["']([^"']+)["']/, content)
              |> Enum.map(fn [_, method, path] -> {method, path} end)
              |> Enum.take(@max_routes)

            entry_points ++ [{:router, routes}]

          _ ->
            entry_points
        end
      else
        entry_points
      end

    entry_points
  end

  defp setup_phoenix_project(dir) do
    File.mkdir_p!(Path.join([dir, "lib", "my_app", "accounts"]))
    File.mkdir_p!(Path.join([dir, "lib", "my_app_web"]))

    File.write!(Path.join([dir, "lib", "my_app", "accounts", "user.ex"]), """
    defmodule MyApp.Accounts.User do
      use Ecto.Schema
    end
    """)

    File.write!(Path.join([dir, "lib", "my_app", "accounts.ex"]), """
    defmodule MyApp.Accounts do
      def get_user(id), do: Repo.get(User, id)
    end
    """)

    File.write!(Path.join([dir, "lib", "my_app_web", "router.ex"]), """
    defmodule MyAppWeb.Router do
      use MyAppWeb, :router

      get "/", PageController, :index
      get "/users", UserController, :index
      post "/users", UserController, :create
      live "/dashboard", DashboardLive
    end
    """)
  end

  defp setup_umbrella_project(dir) do
    File.mkdir_p!(Path.join([dir, "apps", "core", "lib", "core"]))
    File.mkdir_p!(Path.join([dir, "apps", "web", "lib", "web"]))

    File.write!(Path.join([dir, "apps", "core", "lib", "core", "core.ex"]), """
    defmodule Core do
    end
    """)

    File.write!(Path.join([dir, "apps", "web", "lib", "web", "web.ex"]), """
    defmodule Web do
    end
    """)
  end
end

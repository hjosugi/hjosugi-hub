defmodule HjosugiHub.Config do
  @moduledoc """
  Loader and validator for site and feed configuration files.

  It evaluates trusted local config files, enforces the data shape used by
  collection/rendering, and exposes presentation helpers such as avatar URLs
  and feed weights.
  """

  def site(path \\ "config/site.exs"), do: load!(path, :site)
  def feeds(path \\ "config/feeds.exs"), do: load!(path, :feeds)

  def avatar_url(site) do
    handle =
      site
      |> Map.get(:links, [])
      |> Enum.find_value(Map.get(site, :handle, ""), fn link ->
        if String.downcase(Map.get(link, :label, "")) == "github" do
          link
          |> Map.get(:url, "")
          |> String.trim()
          |> String.replace_prefix("https://github.com/", "")
          |> String.trim("/")
        end
      end)
      |> to_string()

    if Regex.match?(~r/\A[A-Za-z0-9_.-]+\z/, handle) do
      "https://github.com/#{handle}.png?size=160"
    else
      ""
    end
  end

  def enabled_feeds(feeds) do
    Enum.count(feeds, &Map.get(&1, :enabled, true))
  end

  # Ranking bias per source. A feed may set its own :weight; otherwise it falls
  # back to a default for its :kind (crowd-voted aggregators rank highest).
  @kind_weights %{
    "aggregator" => 1.3,
    "newsletter" => 1.2,
    "engineering" => 1.15,
    "official" => 1.0,
    "youtube" => 1.0
  }
  @known_feed_kinds Map.keys(@kind_weights)
  @feed_required_keys [:id, :name, :url]
  @site_required_strings [:handle, :display_name, :headline, :location, :about]
  @handle_re ~r/\A[A-Za-z0-9_.-]+\z/

  def feed_weight(feed) do
    case Map.get(feed, :weight) do
      weight when is_number(weight) -> weight / 1
      _ -> Map.get(@kind_weights, Map.get(feed, :kind), 1.0)
    end
  end

  defp load!(path, schema) do
    {value, _binding} = Code.eval_file(path)
    validate!(schema, value, path)
    value
  end

  defp validate!(:feeds, value, path) when is_list(value) do
    path = display_path(path)

    errors =
      value
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {feed, index} -> validate_feed(feed, index, path) end)
      |> Kernel.++(duplicate_feed_id_errors(value, path))

    raise_if_errors!(errors)
  end

  defp validate!(:feeds, _value, path) do
    raise ArgumentError, "#{display_path(path)} must contain a list of feed maps."
  end

  defp validate!(:site, value, path) when is_map(value) do
    path = display_path(path)

    errors =
      required_key_errors(value, @site_required_strings, path)
      |> Kernel.++(required_string_errors(value, @site_required_strings, path))
      |> Kernel.++(handle_errors(value, path))
      |> Kernel.++(link_errors(value, path))
      |> Kernel.++(project_errors(value, path))

    raise_if_errors!(errors)
  end

  defp validate!(:site, _value, path) do
    raise ArgumentError, "#{display_path(path)} must contain a site map."
  end

  defp validate_feed(feed, index, path) when is_map(feed) do
    context = feed_context(path, index, feed)

    required_key_errors(feed, @feed_required_keys, context)
    |> Kernel.++(required_string_errors(feed, @feed_required_keys, context))
    |> Kernel.++(feed_url_errors(feed, context))
    |> Kernel.++(feed_kind_errors(feed, context))
    |> Kernel.++(feed_weight_errors(feed, context))
  end

  defp validate_feed(_feed, index, path) do
    ["#{path} entry #{index} must be a map."]
  end

  defp duplicate_feed_id_errors(feeds, path) do
    feeds
    |> Enum.with_index(1)
    |> Enum.reduce({%{}, []}, fn
      {feed, index}, {seen, errors} when is_map(feed) ->
        case Map.get(feed, :id) do
          id when is_binary(id) and id != "" ->
            case Map.fetch(seen, id) do
              {:ok, first_index} ->
                {seen,
                 errors ++
                   [
                     "#{feed_context(path, index, feed)} duplicates :id from entry #{first_index}."
                   ]}

              :error ->
                {Map.put(seen, id, index), errors}
            end

          _ ->
            {seen, errors}
        end

      {_feed, _index}, acc ->
        acc
    end)
    |> elem(1)
  end

  defp feed_url_errors(feed, context) do
    case Map.fetch(feed, :url) do
      {:ok, url} when is_binary(url) ->
        if http_url?(url), do: [], else: ["#{context} :url must be an http(s) URL."]

      _ ->
        []
    end
  end

  defp feed_kind_errors(feed, context) do
    case Map.fetch(feed, :kind) do
      :error ->
        []

      {:ok, kind} when kind in @known_feed_kinds ->
        []

      {:ok, kind} ->
        [
          "#{context} has unknown :kind #{inspect(kind)}; expected one of: #{known_feed_kinds()}."
        ]
    end
  end

  defp feed_weight_errors(feed, context) do
    case Map.fetch(feed, :weight) do
      {:ok, weight} when not is_number(weight) -> ["#{context} :weight must be numeric."]
      _ -> []
    end
  end

  defp handle_errors(site, path) do
    case Map.fetch(site, :handle) do
      {:ok, handle} when is_binary(handle) ->
        if Regex.match?(@handle_re, handle) do
          []
        else
          [
            "#{path} :handle must contain only letters, numbers, underscores, dots, or hyphens."
          ]
        end

      _ ->
        []
    end
  end

  defp link_errors(site, path) do
    case Map.fetch(site, :links) do
      :error ->
        ["#{path} missing :links."]

      {:ok, links} when is_list(links) ->
        links
        |> Enum.with_index(1)
        |> Enum.flat_map(fn {link, index} -> validate_link(link, index, path) end)

      {:ok, _links} ->
        ["#{path} :links must be a list."]
    end
  end

  defp validate_link(link, index, path) when is_map(link) do
    context = "#{path} :links entry #{index}"

    required_key_errors(link, [:label, :url], context)
    |> Kernel.++(required_string_errors(link, [:label, :url], context))
    |> Kernel.++(url_field_errors(link, :url, context))
  end

  defp validate_link(_link, index, path) do
    ["#{path} :links entry #{index} must be a map."]
  end

  defp project_errors(site, path) do
    case Map.fetch(site, :projects) do
      :error ->
        ["#{path} missing :projects."]

      {:ok, projects} when is_list(projects) ->
        projects
        |> Enum.with_index(1)
        |> Enum.flat_map(fn {project, index} -> validate_project(project, index, path) end)

      {:ok, _projects} ->
        ["#{path} :projects must be a list."]
    end
  end

  defp validate_project(project, index, path) when is_map(project) do
    context = project_context(path, index, project)

    required_key_errors(project, [:name, :url, :summary, :stack, :highlights], context)
    |> Kernel.++(required_string_errors(project, [:name, :url, :summary], context))
    |> Kernel.++(url_field_errors(project, :url, context))
    |> Kernel.++(optional_url_field_errors(project, [:docs_url, :demo_url], context))
    |> Kernel.++(string_list_field_errors(project, [:stack, :highlights], context))
    |> Kernel.++(optional_boolean_field_errors(project, :featured, context))
  end

  defp validate_project(_project, index, path) do
    ["#{path} :projects entry #{index} must be a map."]
  end

  defp required_key_errors(map, keys, context) do
    keys
    |> Enum.reject(&Map.has_key?(map, &1))
    |> Enum.map(&"#{context} missing :#{&1}.")
  end

  defp required_string_errors(map, keys, context) do
    Enum.flat_map(keys, fn key ->
      case Map.fetch(map, key) do
        {:ok, value} when is_binary(value) ->
          if String.trim(value) == "" do
            ["#{context} :#{key} must be a non-empty string."]
          else
            []
          end

        {:ok, _value} ->
          ["#{context} :#{key} must be a non-empty string."]

        :error ->
          []
      end
    end)
  end

  defp url_field_errors(map, key, context) do
    case Map.fetch(map, key) do
      {:ok, url} when is_binary(url) ->
        if http_url?(url), do: [], else: ["#{context} :#{key} must be an http(s) URL."]

      {:ok, _url} ->
        []

      :error ->
        []
    end
  end

  defp optional_url_field_errors(map, keys, context) do
    Enum.flat_map(keys, fn key ->
      case Map.fetch(map, key) do
        {:ok, ""} -> []
        {:ok, url} when is_binary(url) -> url_field_errors(map, key, context)
        {:ok, _url} -> ["#{context} :#{key} must be an http(s) URL when present."]
        :error -> []
      end
    end)
  end

  defp string_list_field_errors(map, keys, context) do
    Enum.flat_map(keys, fn key ->
      case Map.fetch(map, key) do
        {:ok, values} when is_list(values) ->
          if Enum.all?(values, &is_binary/1) do
            []
          else
            ["#{context} :#{key} must be a list of strings."]
          end

        {:ok, _values} ->
          ["#{context} :#{key} must be a list of strings."]

        :error ->
          []
      end
    end)
  end

  defp optional_boolean_field_errors(map, key, context) do
    case Map.fetch(map, key) do
      {:ok, value} when not is_boolean(value) -> ["#{context} :#{key} must be a boolean."]
      _ -> []
    end
  end

  defp http_url?(url) do
    case URI.parse(url) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) ->
        host != ""

      _ ->
        false
    end
  end

  defp feed_context(path, index, feed) do
    "#{path} entry #{index}#{id_context(feed)}"
  end

  defp project_context(path, index, project) do
    "#{path} :projects entry #{index}#{name_context(project)}"
  end

  defp id_context(%{id: nil}), do: ""
  defp id_context(%{id: id}), do: " (id: #{display_value(id)})"
  defp id_context(_feed), do: ""

  defp name_context(%{name: nil}), do: ""
  defp name_context(%{name: name}), do: " (name: #{display_value(name)})"
  defp name_context(_project), do: ""

  defp display_value(value) when is_binary(value), do: value
  defp display_value(value), do: inspect(value)

  defp known_feed_kinds do
    Enum.join(@known_feed_kinds, ", ")
  end

  defp display_path(path) do
    Path.relative_to_cwd(path)
  end

  defp raise_if_errors!([]), do: :ok

  defp raise_if_errors!(errors) do
    raise ArgumentError, Enum.join(errors, "\n")
  end
end

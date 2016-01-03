defmodule Mix.Tasks.Slack.Html do
  use Mix.Task

  require EEx

  @shortdoc "Export a Slack archive folder to HTML"

  @templates_root "templates"
  @static_root "static"

  EEx.function_from_file :def, :render_index, Path.join(@templates_root, "index.html.eex"), [:channels]
  EEx.function_from_file :def, :render_channel_index, Path.join(@templates_root, "channel_index.html.eex"), [:channel, :messages]
  EEx.function_from_file :def, :render_channel_messages, Path.join(@templates_root, "channel_messages.html.eex"), [:channel, :date, :users, :channels]
  EEx.function_from_file :def, :render_404, Path.join(@templates_root, "404.html.eex"), []
  EEx.function_from_file :def, :render_within_layout, Path.join(@templates_root, "layout.html.eex"), [:content]

  def run(path) do
    Mix.shell.info "Export path: #{path}"

    output_dir = Application.get_env(:slack_to_html, :output_dir)

    users = load_users!(path)
    channels = load_channels!(path)
      |> Stream.map(fn channel ->
        {channel["id"], fill_with_messages!(channel, path)}
      end)
      |> Stream.filter(fn {_, channel} -> !(channel["name"] in Application.get_env(:slack_to_html, :excluded_channels)) end)
      |> Enum.into(%{})

    setup_output_directory!(output_dir)
    generate_index!(output_dir, channels)
    generate_channels_messages!(output_dir, channels, users)
    generate_404(output_dir)
    copy_files!(output_dir, ~w(style.css))
  end

  def load_users!(path) do
    users_path = Path.join(path, "users.json")
    Mix.shell.info "Loading users from #{users_path}"
    case File.read(users_path) do
      {:ok, body} ->
        users =
          Poison.decode!(body)
          |> Enum.map(fn user -> {user["id"], user} end)
          |> Enum.into(%{})
      {:error, reason} ->
        Mix.shell.error "Error loading users: #{reason}"
    end
  end

  def load_channels!(path) do
    channels_path = Path.join(path, "channels.json")
    Mix.shell.info "Loading channels from #{channels_path}"
    case File.read(channels_path) do
      {:ok, body} -> Poison.decode!(body)
      {:error, reason} ->
        Mix.shell.error "Error loading channels: #{reason}"
    end
  end

  def fill_with_messages!(channel, path) do
    channel_messages_files = Path.join(path, channel["name"]) |> File.ls!()
    channel_messages = Enum.reduce(channel_messages_files, %{}, fn messages_path, new_channel_messages ->
      date = Path.basename(messages_path, ".json")
      messages =
        Path.join([path, channel["name"], messages_path])
        |> File.read!
        |> Poison.decode!
      Map.put(new_channel_messages, date, messages)
    end)
    Map.put(channel, "messages", channel_messages)
  end

  def setup_output_directory!(path) do
    Mix.shell.info "Setting up output directory (#{path})"
    File.rm_rf!(path)
    File.mkdir_p!(path)
  end

  def generate_index!(path, channels) do
    Mix.shell.info "Generating index for channels"
    body = render_index(channels) |> render_within_layout
    Path.join(path, "index.html") |> File.write!(body)
  end

  def generate_channels_messages!(path, channels, users) do
    tasks = for {_channel_id, channel} <- channels do
      Mix.shell.info "Generating html for #{channel["name"]}"
      Task.async(__MODULE__, :generate_channel_messages!, [path, channel, users, channels])
    end
    Task.yield_many(tasks, 60000)
  end

  def generate_channel_messages!(path, channel, users, channels) do
    channel_path = Path.join(path, channel["name"])
    File.mkdir_p!(channel_path)

    messages =
      Enum.group_by(channel["messages"], fn {d, _m} -> Timex.DateFormat.parse!(d, "{YYYY}-{0M}-{0D}").year end)
      |> Enum.map(fn {year, messages} ->
        {year, Enum.group_by(messages, fn {d, _m} -> Timex.DateFormat.parse!(d, "{YYYY}-{0M}-{0D}").month end)}
      end)
      |> Enum.into(%{})

    channel_index_body = render_channel_index(channel, messages) |> render_within_layout
    Path.join(channel_path, "index.html") |> File.write!(channel_index_body)

    for {date, _messages} <- channel["messages"] do
      messages_path = Path.join(channel_path, date)
      File.mkdir_p!(messages_path)
      channel_messages_body =
        render_channel_messages(channel, date, users, channels)
        |> render_within_layout
      Path.join(messages_path, "index.html") |> File.write!(channel_messages_body)
    end
  end

  def generate_404(path) do
    Mix.shell.info "Generating 404 page"
    error_content = render_404() |> render_within_layout()
    Path.join(path, "404.html") |> File.write!(error_content)
  end

  def copy_files!(path, files) do
    Mix.shell.info "Copying files from #{@static_root}"
    for file <- files do
      Path.join(@static_root, file) |> File.copy!(Path.join(path, file))
    end
  end

	def cleanup_message(message, channels, users) do
    message
    |> cleanup_system_messages()
    |> cleanup_users(users)
    |> cleanup_channels(channels)
    |> cleanup_urls()
	end

  def cleanup_system_messages(message) when message != nil do
    message = Regex.replace(~r/<@\S+> (has (joined|left) the channel)/, message, "\\1")
    message = Regex.replace(~r/<@\S+> (set the channel purpose: .*)/, message, "\\1")
    message = Regex.replace(~r/<@\S+> (uploaded a file: .*)/, message, "\\1")
    message = Regex.replace(~r/<@\S+> (pinned a message: .*)/, message, "\\1")
    Regex.replace(~r/<@\S+> (archived the group)/, message, "\\1")
  end
  def cleanup_system_messages(message), do: message

	def cleanup_users(message, users) when message != nil do
    ids = Regex.scan(~r/<@([\w\d]+)\|?.*>/, message, capture: :all_but_first)
    Enum.reduce(ids, message, fn [id|_tail], new_message ->
      username = users[id]["name"]
      String.replace(new_message, "<@#{id}>", username)
    end)
  end
  def cleanup_users(message, _users), do: message

	def cleanup_channels(message, channels) when message != nil do
		ids = Regex.scan(~r/<\#(\S+)>/, message, capture: :all_but_first)
		Enum.reduce(ids, message, fn [id|_tail], new_message ->
      channel = channels[id]["name"]
      String.replace(new_message, "<\##{id}>", "##{channel}")
    end)
  end
	def cleanup_channels(message, _channels), do: message

	def cleanup_urls(message) when message != nil do
    urls = Regex.scan(~r/<(http[^>]*)>/, message, capture: :all_but_first)
    Enum.reduce(urls, message, fn [url|_tail], new_message ->
      String.replace(new_message, "<#{url}>", ~s(<a href="#{url}">#{url}</a>))
    end)
  end
	def cleanup_urls(message), do: message
end

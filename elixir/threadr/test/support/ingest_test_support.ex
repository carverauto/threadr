defmodule Threadr.TestPublisher do
  def publish(envelope), do: publish(envelope, self())

  def publish(envelope, pid) do
    send(pid, {:published_envelope, envelope})
    :ok
  end
end

defmodule Threadr.TestIRCClient do
  use GenServer

  def start_link(options) do
    GenServer.start_link(__MODULE__, options)
  end

  def add_handler(client, handler) do
    GenServer.call(client, {:add_handler, handler})
  end

  def connect!(client, host, port, _options) do
    GenServer.call(client, {:connect, :tcp, host, port})
  end

  def connect_ssl!(client, host, port, _options) do
    GenServer.call(client, {:connect, :ssl, host, port})
  end

  def logon(client, pass, nick, user, name) do
    GenServer.call(client, {:logon, pass, nick, user, name})
  end

  def join(client, channel, key \\ "") do
    GenServer.call(client, {:join, channel, key})
  end

  @impl true
  def init(options) do
    {:ok,
     %{
       test_pid: Keyword.fetch!(options, :test_pid),
       auto_connect?: Keyword.get(options, :auto_connect?, true),
       auto_logon?: Keyword.get(options, :auto_logon?, true),
       handler: nil
     }}
  end

  @impl true
  def handle_call({:add_handler, handler}, _from, state) do
    send(state.test_pid, {:irc_client_add_handler, self(), handler})
    {:reply, :ok, %{state | handler: handler}}
  end

  def handle_call({:connect, transport, host, port}, _from, state) do
    send(state.test_pid, {:irc_client_connect, transport, host, port})

    if state.auto_connect? and state.handler do
      send(state.handler, {:connected, host, port})
    end

    {:reply, :ok, state}
  end

  def handle_call({:logon, pass, nick, user, name}, _from, state) do
    send(state.test_pid, {:irc_client_logon, pass, nick, user, name})

    if state.auto_logon? and state.handler do
      send(state.handler, :logged_in)
    end

    {:reply, :ok, state}
  end

  def handle_call({:join, channel, key}, _from, state) do
    send(state.test_pid, {:irc_client_join, channel, key})
    {:reply, :ok, state}
  end
end

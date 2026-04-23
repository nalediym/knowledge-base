defmodule Kb.Graph.PubSub do
  @moduledoc """
  Tiny topic-based pubsub built on `Registry`. Subscribers (SSE plugs, tests)
  call `subscribe/1` and receive `{:kb_graph_event, topic, payload}` messages.

  The primary topic is `"kb:graph"`. Payloads are plain maps (usually graph
  deltas).
  """

  @registry Kb.Graph.PubSub.Registry
  @default_topic "kb:graph"

  def child_spec(_opts) do
    Registry.child_spec(keys: :duplicate, name: @registry)
  end

  @spec default_topic() :: String.t()
  def default_topic, do: @default_topic

  @spec subscribe(String.t()) :: :ok
  def subscribe(topic \\ @default_topic) do
    case Registry.register(@registry, topic, nil) do
      {:ok, _} -> :ok
      {:error, {:already_registered, _}} -> :ok
    end
  end

  @spec unsubscribe(String.t()) :: :ok
  def unsubscribe(topic \\ @default_topic) do
    Registry.unregister(@registry, topic)
    :ok
  end

  @spec broadcast(String.t(), map()) :: :ok
  def broadcast(topic \\ @default_topic, payload) when is_map(payload) do
    Registry.dispatch(@registry, topic, fn entries ->
      for {pid, _} <- entries, do: send(pid, {:kb_graph_event, topic, payload})
    end)

    :ok
  end

  @spec subscriber_count(String.t()) :: non_neg_integer()
  def subscriber_count(topic \\ @default_topic) do
    Registry.lookup(@registry, topic) |> length()
  end
end

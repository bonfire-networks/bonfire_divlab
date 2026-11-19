defmodule Bonfire.Divlab.Web.TasksBoardPubsubTest do
  @moduledoc "The Tasks page subscribes its process to its group's topic, so it must do so once however often the group changes in that process."
  use Bonfire.Divlab.ConnCase, async: false

  import Bonfire.Divlab.TasksFixtures

  alias Bonfire.Common.PubSub
  alias Bonfire.Divlab.Web.TasksBoardLive

  test "switching group A to B to A, the page hears A's tasks once" do
    ivan = fake_user!(fake_account!())
    a = tasks_group!(ivan, [])
    b = tasks_group!(ivan, [])

    socket = %Phoenix.LiveView.Socket{
      assigns: %{
        __changed__: %{},
        __context__: %{current_user: ivan},
        view: :lists,
        members_of: nil
      }
    }

    socket =
      for group <- [a, b, a], reduce: socket do
        socket ->
          {:ok, socket} = TasksBoardLive.update(%{id: "board", category: group}, socket)
          socket
      end

    topic = TasksBoardLive.tasks_topic(a.id)
    :ok = PubSub.broadcast(topic, {:probe, topic})
    assert_receive {:probe, ^topic}
    refute_receive {:probe, ^topic}, 100
    assert socket.assigns.members_of == a.id
  end
end

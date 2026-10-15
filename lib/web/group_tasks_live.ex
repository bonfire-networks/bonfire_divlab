defmodule Bonfire.Divlab.Web.GroupTasksLive do
  @moduledoc "The group's Tasks page: the views of its tasks when the group has Tasks on (step 8), and a note when it hasn't. The view is the path segment after `/tasks` (D8a in tasks-v1.md)."
  use Bonfire.UI.Common.Web, :stateless_component

  prop category, :any, required: true
  prop tab_id, :string, default: nil

  def render(assigns) do
    assigns
    |> assign(:enabled?, Bonfire.Divlab.Tasks.enabled_for?(assigns.category, assigns[:__context__]))
    |> render_sface()
  end
end

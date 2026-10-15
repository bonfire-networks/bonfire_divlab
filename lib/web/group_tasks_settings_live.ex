defmodule Bonfire.Divlab.Web.GroupTasksSettingsLive do
  @moduledoc "The group settings page that turns Tasks on or off. `Bonfire.UI.Groups.SettingsLive` only renders it for the group's managers."
  use Bonfire.UI.Common.Web, :stateless_component

  prop category, :any, required: true

  def render(assigns) do
    assigns
    |> assign(:enabled?, Bonfire.Divlab.Tasks.enabled_for?(assigns.category, assigns[:__context__]))
    |> render_sface()
  end
end

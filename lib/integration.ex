defmodule Bonfire.Divlab do
  @moduledoc "./README.md" |> File.stream!() |> Enum.drop(1) |> Enum.join()

  use Bonfire.Common.Config
  use Bonfire.Common.Localise
  import Bonfire.Common.Modularity.DeclareHelpers

  declare_extension(
    l("Bonfire.Divlab"),
    icon: "bi:app",
    description: l("An awesome extension")
    # default_nav: [
    #   Bonfire.Divlab.Web.HomeLive
    # ]
  )

  def repo, do: Config.repo()
end

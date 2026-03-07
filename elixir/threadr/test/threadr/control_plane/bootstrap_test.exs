defmodule Threadr.ControlPlane.BootstrapTest do
  use Threadr.DataCase, async: false

  alias Threadr.ControlPlane.Service

  test "bootstrap_operator_admin creates the first operator admin once" do
    assert {:ok, user, password} =
             Service.bootstrap_operator_admin(%{
               email: "bootstrap@example.com",
               name: "Bootstrap Admin"
             })

    assert user.is_operator_admin
    assert user.must_rotate_password
    assert is_binary(password)
    assert byte_size(password) >= 12

    assert {:error, :operator_admin_already_bootstrapped} =
             Service.bootstrap_operator_admin(%{
               email: "second@example.com"
             })
  end
end

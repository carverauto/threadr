defimpl Ash.ToTenant, for: Threadr.ControlPlane.Tenant do
  def to_tenant(tenant, _resource) do
    tenant.schema_name
  end
end

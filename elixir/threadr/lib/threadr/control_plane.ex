defmodule Threadr.ControlPlane do
  @moduledoc """
  Public-schema Ash domain for SaaS control-plane resources.
  """

  use Ash.Domain

  resources do
    resource Threadr.ControlPlane.SystemLlmConfig do
      define :create_system_llm_config, action: :create
      define :destroy_system_llm_config, action: :destroy
      define :get_system_llm_config, action: :read, get_by: [:scope]
      define :update_system_llm_config, action: :update
    end

    resource Threadr.ControlPlane.Bot do
      define :create_bot, action: :create
      define :destroy_bot, action: :destroy
      define :finalize_bot_delete, action: :finalize_delete
      define :get_bot, action: :read, get_by: [:id]
      define :begin_bot_delete, action: :begin_delete
      define :report_bot_status, action: :report_status
      define :request_bot_reconcile, action: :request_reconcile
      define :update_bot, action: :update
      define :list_bots, action: :read
    end

    resource Threadr.ControlPlane.BotControllerContract do
      define :get_bot_controller_contract, action: :read, get_by: [:bot_id]
      define :list_bot_controller_contracts, action: :read
      define :update_bot_controller_contract, action: :update
      define :upsert_bot_controller_contract, action: :upsert
    end

    resource Threadr.ControlPlane.BotReconcileOperation do
      define :create_bot_reconcile_operation, action: :create
      define :list_bot_reconcile_operations, action: :read
      define :update_bot_reconcile_operation, action: :update
    end

    resource Threadr.ControlPlane.ApiKey do
      define :create_api_key, action: :create
      define :get_api_key, action: :read, get_by: [:id]
      define :list_api_keys, action: :read
      define :update_api_key, action: :update
    end

    resource Threadr.ControlPlane.Tenant do
      define :create_tenant, action: :create
      define :get_tenant, action: :read, get_by: [:id]
      define :update_tenant, action: :update
      define :list_tenants, action: :read
      define :get_tenant_by_subject_name, action: :read, get_by: [:subject_name]
      define :get_tenant_by_schema_name, action: :read, get_by: [:schema_name]
    end

    resource Threadr.ControlPlane.TenantLlmConfig do
      define :create_tenant_llm_config, action: :create
      define :get_tenant_llm_config, action: :read, get_by: [:tenant_id]
      define :update_tenant_llm_config, action: :update
      define :destroy_tenant_llm_config, action: :destroy
    end

    resource Threadr.ControlPlane.TenantMembership do
      define :create_tenant_membership, action: :create
      define :destroy_tenant_membership, action: :destroy
      define :get_tenant_membership, action: :read, get_by: [:id]
      define :list_tenant_memberships, action: :read
      define :update_tenant_membership, action: :update
    end

    resource Threadr.ControlPlane.Token

    resource Threadr.ControlPlane.User do
      define :change_password, action: :change_password
      define :create_bootstrap_user, action: :create_bootstrap_user
      define :get_user_by_email, action: :read, get_by: [:email]
      define :get_user_by_id, action: :read, get_by: [:id]
      define :list_users, action: :read
      define :list_operator_admins, action: :operator_admins
      define :register_user, action: :register_with_password
      define :sign_in_user_with_api_key, action: :sign_in_with_api_key
      define :sign_in_user_with_password, action: :sign_in_with_password
      define :update_user, action: :update
    end
  end
end

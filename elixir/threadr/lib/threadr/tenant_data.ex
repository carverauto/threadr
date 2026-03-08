defmodule Threadr.TenantData do
  @moduledoc """
  Tenant-schema Ash domain for tenant-owned chat and graph data.
  """

  use Ash.Domain

  resources do
    resource Threadr.TenantData.Actor
    resource Threadr.TenantData.Channel
    resource Threadr.TenantData.CommandExecution
    resource Threadr.TenantData.ExtractedEntity
    resource Threadr.TenantData.ExtractedFact
    resource Threadr.TenantData.Message
    resource Threadr.TenantData.MessageEmbedding
    resource Threadr.TenantData.MessageMention
    resource Threadr.TenantData.Relationship
    resource Threadr.TenantData.RelationshipObservation
  end
end

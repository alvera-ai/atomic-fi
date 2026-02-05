defmodule PaymentCompliancePlatform.Watchman.Entity do
  @moduledoc """
  Provides struct and type for a Entity.

  Note: Field names match the actual API response (entityType, sourceList)
  rather than the OpenAPI spec (type, source).
  """

  @type t :: %__MODULE__{
          addresses: [PaymentCompliancePlatform.Watchman.Address.t()] | nil,
          aircraft: PaymentCompliancePlatform.Watchman.Aircraft.t() | nil,
          business: PaymentCompliancePlatform.Watchman.Business.t() | nil,
          contact: PaymentCompliancePlatform.Watchman.Contact.t() | nil,
          cryptoAddresses: [PaymentCompliancePlatform.Watchman.CryptoAddress.t()] | nil,
          entityType: String.t() | nil,
          match: float() | nil,
          name: String.t() | nil,
          organization: PaymentCompliancePlatform.Watchman.Organization.t() | nil,
          person: PaymentCompliancePlatform.Watchman.Person.t() | nil,
          sourceData: map | nil,
          sourceID: String.t() | nil,
          sourceList: String.t() | nil,
          vessel: PaymentCompliancePlatform.Watchman.Vessel.t() | nil
        }

  defstruct [
    :addresses,
    :aircraft,
    :business,
    :contact,
    :cryptoAddresses,
    :entityType,
    :match,
    :name,
    :organization,
    :person,
    :sourceData,
    :sourceID,
    :sourceList,
    :vessel
  ]

  @doc false
  @spec __fields__(atom) :: keyword
  def __fields__(type \\ :t)

  def __fields__(:t) do
    [
      addresses: [{PaymentCompliancePlatform.Watchman.Address, :t}],
      aircraft: {PaymentCompliancePlatform.Watchman.Aircraft, :t},
      business: {PaymentCompliancePlatform.Watchman.Business, :t},
      contact: {PaymentCompliancePlatform.Watchman.Contact, :t},
      cryptoAddresses: [{PaymentCompliancePlatform.Watchman.CryptoAddress, :t}],
      entityType: {:enum, ["person", "business", "organization", "aircraft", "vessel"]},
      match: :number,
      name: :string,
      organization: {PaymentCompliancePlatform.Watchman.Organization, :t},
      person: {PaymentCompliancePlatform.Watchman.Person, :t},
      sourceData: :map,
      sourceID: :string,
      sourceList: :string,
      vessel: {PaymentCompliancePlatform.Watchman.Vessel, :t}
    ]
  end
end

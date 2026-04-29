defmodule AtomicFi.Watchman.Entity do
  @moduledoc """
  Provides struct and type for a Entity.

  Note: Field names match the actual API response (entityType, sourceList)
  rather than the OpenAPI spec (type, source).
  """

  @type t :: %__MODULE__{
          addresses: [AtomicFi.Watchman.Address.t()] | nil,
          aircraft: AtomicFi.Watchman.Aircraft.t() | nil,
          business: AtomicFi.Watchman.Business.t() | nil,
          contact: AtomicFi.Watchman.Contact.t() | nil,
          cryptoAddresses: [AtomicFi.Watchman.CryptoAddress.t()] | nil,
          entityType: String.t() | nil,
          match: float() | nil,
          name: String.t() | nil,
          organization: AtomicFi.Watchman.Organization.t() | nil,
          person: AtomicFi.Watchman.Person.t() | nil,
          sourceData: map | nil,
          sourceID: String.t() | nil,
          sourceList: String.t() | nil,
          vessel: AtomicFi.Watchman.Vessel.t() | nil
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
      addresses: [{AtomicFi.Watchman.Address, :t}],
      aircraft: {AtomicFi.Watchman.Aircraft, :t},
      business: {AtomicFi.Watchman.Business, :t},
      contact: {AtomicFi.Watchman.Contact, :t},
      cryptoAddresses: [{AtomicFi.Watchman.CryptoAddress, :t}],
      entityType: {:enum, ["person", "business", "organization", "aircraft", "vessel"]},
      match: :number,
      name: :string,
      organization: {AtomicFi.Watchman.Organization, :t},
      person: {AtomicFi.Watchman.Person, :t},
      sourceData: :map,
      sourceID: :string,
      sourceList: :string,
      vessel: {AtomicFi.Watchman.Vessel, :t}
    ]
  end
end

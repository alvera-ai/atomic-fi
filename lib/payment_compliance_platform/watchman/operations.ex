defmodule PaymentCompliancePlatform.Watchman.Operations do
  @moduledoc """
  Provides API endpoints related to operations
  """

  @default_client PaymentCompliancePlatform.Watchman.Client

  @doc """
  Import a file as a dataset

  Import a file as an in-memory dataset for use in searches.

  ## Request Body

  **Content Types**: `text/plain`
  """
  @spec v2_ingest_file_type_post(fileType :: String.t(), body :: String.t(), opts :: keyword) ::
          {:ok, PaymentCompliancePlatform.Watchman.IngestFileResponse.t()} | :error
  def v2_ingest_file_type_post(fileType, body, opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [fileType: fileType, body: body],
      call: {PaymentCompliancePlatform.Watchman.Operations, :v2_ingest_file_type_post},
      url: "/v2/ingest/#{fileType}",
      body: body,
      method: :post,
      request: [{"text/plain", :string}],
      response: [{200, {PaymentCompliancePlatform.Watchman.IngestFileResponse, :t}}],
      opts: opts
    })
  end

  @doc """
  Get information about available sanction lists

  Returns information about the lists watchman has prepared and indexed for search
  """
  @spec v2_listinfo_get(opts :: keyword) ::
          {:ok, PaymentCompliancePlatform.Watchman.ListInfoResponse.t()} | :error
  def v2_listinfo_get(opts \\ []) do
    client = opts[:client] || @default_client

    client.request(%{
      args: [],
      call: {PaymentCompliancePlatform.Watchman.Operations, :v2_listinfo_get},
      url: "/v2/listinfo",
      method: :get,
      response: [{200, {PaymentCompliancePlatform.Watchman.ListInfoResponse, :t}}],
      opts: opts
    })
  end

  @doc """
  Search for entities in sanction lists

  Search for entities in the sanction lists based on the provided parameters

  ## Options

    * `name`: Name of the entity to search for
    * `source`: Source list to filter entity
    * `sourceID`: Original list identifier
    * `type`: Type of entity to search for
    * `altNames`: Alternative names for the entity
    * `limit`: Maximum number of results to return (default 10, max 100)
    * `minMatch`: Minimum match threshold for search results
    * `requestID`: Client-provided ID for request tracking
    * `debug`: Enable debug mode for additional information
    * `debugSourceIDs`: Comma-separated list of source IDs to debug
    * `gender`: Gender of the person (for type=person)
    * `birthDate`: Birth date of the person (for type=person) in YYYY-MM-DD, YYYY-MM, or YYYY format
    * `deathDate`: Death date of the person (for type=person) in YYYY-MM-DD, YYYY-MM, or YYYY format
    * `titles`: Titles of the person (for type=person)
    * `created`: Creation date of the business/organization in YYYY-MM-DD, YYYY-MM, or YYYY format
    * `dissolved`: Dissolution date of the business/organization in YYYY-MM-DD, YYYY-MM, or YYYY format
    * `aircraftType`: Type of aircraft (for type=aircraft)
    * `icaoCode`: ICAO code of the aircraft (for type=aircraft)
    * `model`: Model of the aircraft (for type=aircraft)
    * `serialNumber`: Serial number of the aircraft (for type=aircraft)
    * `built`: Build date of the aircraft (for type=aircraft) in YYYY-MM-DD, YYYY-MM, or YYYY format
    * `flag`: Flag/country of the aircraft (for type=aircraft)
    * `imoNumber`: IMO number of the vessel (for type=vessel)
    * `vesselType`: Type of vessel (for type=vessel)
    * `mmsi`: MMSI of the vessel (for type=vessel)
    * `callSign`: Call sign of the vessel (for type=vessel)
    * `owner`: Owner of the vessel (for type=vessel)
    * `tonnage`: Tonnage of the vessel (for type=vessel)
    * `grossRegisteredTonnage`: Gross registered tonnage of the vessel (for type=vessel)
    * `email`: Email address of the entity
    * `emailAddress`: Alternative parameter for email address of the entity
    * `emailAddresses`: Alternative parameter for email addresses of the entity
    * `phone`: Phone number of the entity
    * `phoneNumber`: Alternative parameter for phone number of the entity
    * `phoneNumbers`: Alternative parameter for phone numbers of the entity
    * `fax`: Fax number of the entity
    * `faxNumber`: Alternative parameter for fax number of the entity
    * `faxNumbers`: Alternative parameter for fax numbers of the entity
    * `website`: Website of the entity
    * `websites`: Alternative parameter for websites of the entity
    * `address`: Address of the entity
    * `addresses`: Alternative parameter for addresses of the entity
    * `cryptoAddress`: Cryptocurrency address of the entity in format CURRENCY:ADDRESS (e.g., XBT:x123456)
    * `cryptoAddresses`: Alternative parameter for cryptocurrency addresses of the entity

  """
  @spec v2_search_get(opts :: keyword) ::
          {:ok, PaymentCompliancePlatform.Watchman.SearchResponse.t()}
          | {:error, PaymentCompliancePlatform.Watchman.ErrorResponse.t()}
  def v2_search_get(opts \\ []) do
    client = opts[:client] || @default_client

    query =
      Keyword.take(opts, [
        :address,
        :addresses,
        :aircraftType,
        :altNames,
        :birthDate,
        :built,
        :callSign,
        :created,
        :cryptoAddress,
        :cryptoAddresses,
        :deathDate,
        :debug,
        :debugSourceIDs,
        :dissolved,
        :email,
        :emailAddress,
        :emailAddresses,
        :fax,
        :faxNumber,
        :faxNumbers,
        :flag,
        :gender,
        :grossRegisteredTonnage,
        :icaoCode,
        :imoNumber,
        :limit,
        :minMatch,
        :mmsi,
        :model,
        :name,
        :owner,
        :phone,
        :phoneNumber,
        :phoneNumbers,
        :requestID,
        :serialNumber,
        :source,
        :sourceID,
        :titles,
        :tonnage,
        :type,
        :vesselType,
        :website,
        :websites
      ])

    client.request(%{
      args: [],
      call: {PaymentCompliancePlatform.Watchman.Operations, :v2_search_get},
      url: "/v2/search",
      method: :get,
      query: query,
      response: [
        {200, {PaymentCompliancePlatform.Watchman.SearchResponse, :t}},
        {400, {PaymentCompliancePlatform.Watchman.ErrorResponse, :t}},
        default: :null
      ],
      opts: opts
    })
  end
end

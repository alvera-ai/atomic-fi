defmodule AlveraPhoenixTemplateServer.Extensions.Ecto.Encrypted.Binary do
  @moduledoc """
  An encrypted binary type for Ecto schemas.

  This module uses `Cloak.Ecto.Binary` to provide transparent encryption
  and decryption of binary data in your database. When your application reads
  or writes data using this type, the encryption and decryption happen automatically.

  ## Usage

  Use this type in your Ecto schemas for fields that should be encrypted at rest:

  ```elixir
  defmodule MySchema do
    use Ecto.Schema

    schema "my_table" do
      field :sensitive_data, AlveraPhoenixTemplateServer.Extensions.Ecto.Encrypted.Binary
      # ...
    end
  end
  ```

  When data is written to the database, it will be encrypted as a binary blob.
  When read from the database, it will be automatically decrypted to its original value.

  ## Security Notes

  - Data is only encrypted at rest in the database; it exists as plaintext in your
    application's memory.
  - Encrypted fields are not searchable since Cloak uses random IVs for each ciphertext.
  - The encryption is handled by the AlveraPhoenixTemplateServer.Vault configuration.

  For more information, see the [Cloak.Ecto documentation](https://hexdocs.pm/cloak_ecto).
  """
  use Cloak.Ecto.Binary, vault: AlveraPhoenixTemplateServer.Vault

  @type t :: binary()
end

defmodule ExForce.OAuth do
  @moduledoc """
  Handles OAuth2
  """

  alias ExForce.OAuth.{Config, Response}
  alias ExForce.Client

  @type username :: String.t()
  @type password :: String.t()
  @type code :: String.t()
  @type redirect_uri :: String.t()

  @doc """
  Returns the authorize url based on the configuration.
  """
  @spec authorize_url(Config.t(), String.t()) :: String.t()
  def authorize_url(%Config{endpoint: endpoint, client_id: client_id}, redirect_uri) do
    query = [
      response_type: "code",
      client_id: client_id,
      redirect_uri: redirect_uri
    ]

    endpoint <> "/services/oauth2/authorize?" <> URI.encode_query(query)
  end

  @doc """
  Fetches an `ExForce.OAuth.Response` struct by making a request to the token endpoint.

  - `:password`: [Understanding the Username-Password OAuth Authentication Flow](https://developer.salesforce.com/docs/atlas.en-us.api_rest.meta/api_rest/intro_understanding_username_password_oauth_flow.htm)
  - `:authorization_code`: [Understanding the Web Server OAuth Authentication Flow](https://developer.salesforce.com/docs/atlas.en-us.api_rest.meta/api_rest/intro_understanding_web_server_oauth_flow.htm)
  - `:refresh`: [Understanding the OAuth Refresh Token Process](https://developer.salesforce.com/docs/atlas.en-us.api_rest.meta/api_rest/intro_understanding_refresh_token_oauth.htm)
  """

  def get_token(grant_type, args, config)

  @spec get_token(:password, {username, password}, Config.t()) ::
          {:ok, Response.t()} | {:error, :invalid_signature | term}
  def get_token(:password, {username, password}, config = %Config{}) do
    config
    |> token_form()
    |> Keyword.put(:grant_type, "password")
    |> Keyword.put(:username, username)
    |> Keyword.put(:password, password)
    |> do_get_token(config)
  end

  @spec get_token(:authorization_code, {code, redirect_uri}, Config.t()) ::
          {:ok, Response.t()} | {:error, :invalid_signature | term}
  def get_token(:authorization_code, {code, redirect_uri}, config = %Config{}) do
    config
    |> token_form()
    |> Keyword.put(:grant_type, "authorization_code")
    |> Keyword.put(:redirect_uri, redirect_uri)
    |> Keyword.put(:code, code)
    |> do_get_token(config)
  end

  @spec get_token(:refresh_token, Response.refresh_token(), Config.t()) ::
          {:ok, Response.t()} | {:error, :invalid_signature | term}
  def get_token(:refresh_token, refresh_token, config = %Config{}) do
    config
    |> token_form()
    |> Keyword.put(:grant_type, "refresh_token")
    |> Keyword.put(:refresh_token, refresh_token)
    |> do_get_token(config)
  end

  defp token_form(%Config{client_id: client_id, client_secret: client_secret}),
    do: [client_id: client_id, client_secret: client_secret]

  defp do_get_token(form, %Config{endpoint: endpoint, client_secret: client_secret}) do
    case Client.request!(:post, endpoint <> "/services/oauth2/token", {:form, form}) do
      {
        200,
        map = %{
          "token_type" => token_type,
          "instance_url" => instance_url,
          "id" => id,
          "signature" => signature,
          "issued_at" => issued_at,
          "access_token" => access_token
        }
      } ->
        verify_signature(
          %Response{
            token_type: token_type,
            instance_url: instance_url,
            id: id,
            issued_at: issued_at |> String.to_integer() |> DateTime.from_unix!(:millisecond),
            signature: signature,
            access_token: access_token,
            refresh_token: Map.get(map, "refresh_token"),
            scope: Map.get(map, "scope")
          },
          client_secret
        )

      {400, error} ->
        {:error, error}
    end
  end

  defp verify_signature(
         resp = %Response{id: id, issued_at: issued_at, signature: signature},
         client_secret
       ) do
    issued_at_raw =
      issued_at
      |> DateTime.to_unix(:millisecond)
      |> Integer.to_string()

    calculated =
      :sha256
      |> :crypto.hmac(client_secret, id <> issued_at_raw)
      |> Base.encode64()

    if calculated == signature do
      {:ok, resp}
    else
      {:error, :invalid_signature}
    end
  end
end
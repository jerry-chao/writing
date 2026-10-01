defmodule Writing.Wechat.Drafts do
  @moduledoc false

  @api "https://api.weixin.qq.com"

  def upsert(article, html, cover_path) do
    with {:ok, token} <- access_token(),
         {:ok, draft_id, thumb_id} <- existing_draft(article, token),
         {:ok, thumb_id} <- ensure_cover(article, thumb_id, token, cover_path),
         :ok <- save_draft(article, html, token, draft_id, thumb_id) do
      {:ok, %{draft_media_id: draft_id, thumb_media_id: thumb_id}}
    end
  end

  defp existing_draft(article, token) do
    case article.draft_media_id do
      id when is_binary(id) and id != "" ->
        case get_draft(token, id) do
          {:ok, draft} -> {:ok, id, draft["thumb_media_id"]}
          {:error, _reason} = error -> error
        end

      _ ->
        find_by_title(token, article.title)
    end
  end

  defp find_by_title(token, title) do
    case list_drafts(token, 0, []) do
      {:ok, items} ->
        matches = Enum.filter(items, &(draft_title(&1) == title))

        case matches do
          [] ->
            {:ok, nil, nil}

          [%{"media_id" => media_id} = item] ->
            with {:ok, draft} <- get_draft(token, media_id) do
              {:ok, media_id, draft["thumb_media_id"] || draft_thumb(item)}
            end

          _ ->
            {:error, {:multiple_matching_wechat_drafts, title}}
        end

      {:error, _reason} = error ->
        error
    end
  end

  defp list_drafts(token, offset, acc) do
    with {:ok, response} <-
           post_json("/cgi-bin/draft/batchget", token, %{offset: offset, count: 20}),
         {:ok, items} when is_list(items) <- fetch(response, "item") do
      if items == [] do
        {:ok, Enum.reverse(acc)}
      else
        list_drafts(token, offset + length(items), Enum.reverse(items, acc))
      end
    else
      {:ok, nil} -> {:error, :wechat_draft_list_missing_items}
      {:error, _reason} = error -> error
    end
  end

  defp get_draft(token, media_id) do
    with {:ok, response} <- post_json("/cgi-bin/draft/get", token, %{media_id: media_id}),
         {:ok, [article | _]} when is_map(article) <- fetch(response, "news_item") do
      {:ok, article}
    else
      {:ok, _} -> {:error, {:wechat_draft_not_found, media_id}}
      {:error, _reason} = error -> error
    end
  end

  defp ensure_cover(article, existing_thumb, token, cover_path) do
    thumb_id = article.thumb_media_id || existing_thumb

    if is_binary(thumb_id) and thumb_id != "" do
      {:ok, thumb_id}
    else
      upload_cover(token, cover_path)
    end
  end

  defp upload_cover(token, path) do
    with {:ok, image} <- File.read(path),
         true <- byte_size(image) < 2_000_000,
         {:ok, response} <-
           request(:post, "/cgi-bin/material/add_material",
             params: [access_token: token, type: "image"],
             form_multipart: [media: {image, filename: Path.basename(path)}]
           ),
         :ok <- ensure_success(response),
         media_id when is_binary(media_id) <- Map.get(response, "media_id") do
      {:ok, media_id}
    else
      false -> {:error, {:cover_exceeds_size_limit, path}}
      nil -> {:error, :wechat_cover_upload_missing_media_id}
      {:error, _reason} = error -> error
    end
  end

  defp save_draft(article, html, token, draft_id, thumb_id) do
    article_payload = %{
      article_type: "news",
      title: article.title,
      author: article.author,
      digest: article.digest,
      content: html,
      thumb_media_id: thumb_id,
      need_open_comment: 0,
      only_fans_can_comment: 0
    }

    result =
      if draft_id do
        post_json("/cgi-bin/draft/update", token, %{
          media_id: draft_id,
          index: 0,
          articles: article_payload
        })
      else
        post_json("/cgi-bin/draft/add", token, %{articles: [article_payload]})
      end

    with {:ok, response} <- result,
         :ok <- ensure_success(response),
         {:ok, saved_id} <- saved_media_id(response, draft_id) do
      {:ok, saved_id}
    end
    |> case do
      {:ok, _id} -> :ok
      {:error, _reason} = error -> error
    end
  end

  defp saved_media_id(response, existing_id) do
    case Map.get(response, "media_id") do
      id when is_binary(id) -> {:ok, id}
      nil when is_binary(existing_id) -> {:ok, existing_id}
      _ -> {:error, :wechat_draft_response_missing_media_id}
    end
  end

  defp access_token do
    app_id = Application.get_env(:writing, :wechat_mp_app_id)
    app_secret = Application.get_env(:writing, :wechat_mp_app_secret)

    if is_binary(app_id) and app_id != "" and is_binary(app_secret) and app_secret != "" do
      with {:ok, response} <-
             request(:post, "/cgi-bin/stable_token",
               json: %{
                 grant_type: "client_credential",
                 appid: app_id,
                 secret: app_secret,
                 force_refresh: false
               }
             ),
           :ok <- ensure_success(response),
           {:ok, token} when is_binary(token) <- fetch(response, "access_token") do
        {:ok, token}
      else
        {:ok, nil} -> {:error, :wechat_token_response_missing_access_token}
        {:error, _reason} = error -> error
      end
    else
      {:error, :wechat_credentials_not_configured}
    end
  end

  defp post_json(path, token, payload) do
    request(:post, path, params: [access_token: token], json: payload)
  end

  defp request(method, path, opts) do
    url = @api <> path

    case Req.request([method: method, url: url, receive_timeout: 30_000, retry: false] ++ opts) do
      {:ok, %{status: status, body: body}} when status in 200..299 and is_map(body) ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, {:wechat_http_status, status, path}}

      {:error, reason} ->
        {:error, {:wechat_request_failed, path, error_type(reason)}}
    end
  end

  defp ensure_success(response) do
    case Map.get(response, "errcode") do
      nil -> :ok
      0 -> :ok
      code -> {:error, {:wechat_api_error, code, Map.get(response, "errmsg")}}
    end
  end

  defp draft_title(item) do
    get_in(item, ["content", "news_item", Access.at(0), "title"])
  end

  defp draft_thumb(item) do
    get_in(item, ["content", "news_item", Access.at(0), "thumb_media_id"])
  end

  defp fetch(map, key) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, {:missing_wechat_field, key}}
    end
  end

  defp error_type(%{__struct__: module}), do: module
  defp error_type(_reason), do: :request_failed
end

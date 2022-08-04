defmodule Fracomex.Utilities do

  alias Fracomex.Products

  def get_page_title_tag(request_path, user_id) do
    uid = cond do
      not is_nil(user_id) -> user_id
      true -> ""
    end

    modif_mdp = "/modifier-motdepasse/#{uid}"
    modif_profil = "/modifier-profil/#{uid}"
    modif_adresse = "/modifier-adresse/#{uid}"

    case request_path do

      "/" -> "Eléctricité | Quincaillerie | Sanitaire"
      "/boutique" -> "Boutique"
      "/panier" -> "Panier"
      "/connexion" -> "Connexion"
      "/inscription" -> "Inscription"
      "/verification-confirmation-mail" -> "Vérification"
      "/verification-mdp-oublie" -> "Vérification"
      "/mdp-oublie" -> "Vérification"
      "/renvoi-verification-mail" -> "Vérification"
      "/mon-profil" -> "Mon profil"
      "/mon-adresse" -> "Mon adresse"
      "/valider-connexion" -> "Validation"
      "/valider-inscription" -> "Validation"
      "/envoi-mail-mdp-oublie" -> "Envoi"
      "/renvoi-mail-confirmation" -> "Envoi"
      modif_mdp -> "Modification"
      modif_profil -> "Modification"
      modif_adresse -> "Modification"
      _ -> "Fracomex"

    end

  end


  # Transformer le prix décimal en float
  def price_to_float(id) do
    price = Products.get_item!(id).sale_price_vat_excluded
    |> Decimal.to_float()
  end

  # Récupérer les informations des produits dans le panier
  def product_in_cart(cart, i) do
    Enum.at(cart, i).product_id
    |> Products.get_item!()
  end

  def price_format(price) do
    :erlang.float_to_binary(Decimal.to_float(price), [decimals: 2]) |> String.replace(".", ",")
  end

  def price_format_from_float(price) do
    :erlang.float_to_binary(price, [decimals: 2]) |> String.replace(".", ",")
  end

  # Vérifie si un champ est vide ou seulement remplie par des espaces
  def is_empty?(params) do
    if not is_nil(params) do
      is_empty =
        params
        |> String.trim()
        |> String.length()

      if is_empty == 0, do: true, else: false
    end
  end

end

defmodule Fracomex.SyncLogic do
  alias Fracomex.{EbpRepo, Products}
  alias Fracomex.Products.{Family, SubFamily}
  import Mogrify

  ###########  ITEM SYNC LOGICS ###########

  def insert_missing_items() do
    select_items_to_be_inserted()
    |> Products.insert_items()
  end

  # SELECTION DES ARTICLES A INSÉRER
  def select_items_to_be_inserted do
    ids = get_item_ids_to_be_inserted()
    readable_ids = ids_list_to_sql_readable(ids)

    case EbpRepo.query("SELECT Id, Caption, SalePriceVatExcluded, ItemImage, ImageVersion, RealStock, FamilyId, SubFamilyId
    FROM Item where Id in #{readable_ids}") do
      {:ok, result} ->
        result.rows |> Enum.map(fn row ->
          id = Enum.at(row, 0)
          caption = Enum.at(row, 1)
          sale_price_vat_excluded = Enum.at(row, 2)
          image = Enum.at(row, 3)
          image_version = Enum.at(row, 4)
          real_stock = Enum.at(row, 5)
          family_id = Enum.at(row, 6)
          sub_family_id = Enum.at(row, 7)

          image_file = get_image_file(id, image)

          stock_status = cond do
            Decimal.to_integer(real_stock) > 0 ->
              true
            true ->
              false
          end

          %{id: id, caption: caption, sale_price_vat_excluded: sale_price_vat_excluded, stock_status: stock_status,
            image: image_file, image_version: image_version, real_stock: real_stock, family_id: family_id, sub_family_id: sub_family_id}
        end)
      _ ->
        []
    end

  end

  def get_image_file(id, image) do
    cond do
      not is_nil(image) ->
      File.write(Path.expand("priv/static/images/big-items/#{id}.jpg"), image, [:binary])

      open(Path.expand("priv/static/images/big-items/#{id}.jpg"))
      |> quality(20)
      |> save(path: Path.expand("priv/static/images/small-items/#{id}.jpg"))

      open(Path.expand("priv/static/images/big-items/#{id}.jpg"))
      |> quality(50)
      |> save()

      "#{id}.jpg"

      true ->
        "empty.png"
    end
  end


  # TROUVER LES ID'S D'ARTICLES MANQUANTS SUR POSTGRES
  def get_item_ids_to_be_inserted do
    Enum.filter(select_item_ids_from_ebp(), fn id ->
                            id not in select_item_ids_from_postgres()
                          end)
  end

  # SELECTION DE TOUS LES ID'S D'ARTICLE DE LA BASE LOCALE POSTGRES
  def select_item_ids_from_postgres do
    Products.list_item_ids()
  end

  # SELECTION DE TOUS LES ID'S D'ARTICLE VENANT D'EBP
  def select_item_ids_from_ebp do
    # IO.puts "item ids ebp"
    family_ids = Products.list_family_ids |> ids_list_to_sql_readable
    # IO.inspect family_ids
    sub_family_ids = Products.list_sub_family_ids |> ids_list_to_sql_readable
    # IO.inspect sub_family_ids

    test_query = "SELECT Id
    FROM Item
    WHERE (
        (FamilyId in #{family_ids} OR FamilyId IS NULL)
        AND
        (SubFamilyId in #{sub_family_ids} OR SubFamilyId IS NULL)
        )
    AND AllowPublishOnWeb=1"

    {:ok, result} = EbpRepo.query(test_query)

    Enum.map(result.rows, fn row ->
      Enum.at(row, 0)
    end)

  end

  ###########  ITEM SUBFAMILY SYNC LOGICS ###########

  # SYNCHRONISATION DES SOUS-FAMILLES D'ARTICLES
  def sync_item_sub_families do
    start = NaiveDateTime.local_now()
    IO.puts "ITEMSUBFAMILY SYNC STARTING"
    # SUBFAMILY INSERTIONS NO LONGER NEEDER CAUSE DONE AT PARENT INSERTION AT LINE
    # insert_missing_item_sub_families()
    update_item_sub_families_diffs()
    delete_item_sub_families()
    IO.puts "ITEMSUBFAMILY SYNC STOPPING"
    ending = NaiveDateTime.local_now()
    IO.inspect(NaiveDateTime.diff(ending, start, :millisecond))
  end

  # SUPPRESSION DES SOUS-FAMILLES N'EXISTANT PLUS SUR EBP OU AYANT UNE NOUVELLE FAMILLE NON EXISTANTE SUR POSTGRES
  def delete_item_sub_families() do
    get_item_sub_family_ids_to_be_deleted()
    |> Products.delete_sub_families()
  end

  # SELECTION DES IDS DES SOUS-FAMILLES N'EXISTANT PLUS SUR EBP OU AYANT UNE NOUVELLE FAMILLE NON EXISTANTE SUR POSTGRES
  def get_item_sub_family_ids_to_be_deleted do
    select_all_item_sub_family_ids_from_postgres() |> Enum.filter(fn id ->
      id not in select_all_item_subfamily_ids_from_ebp()
    end)
  end

  # MISE A JOUR DES CHANGEMENTS DE VALEUR DES SOUS-FAMILLES
  def update_item_sub_families_diffs() do
    Enum.each(get_item_sub_families_valid_changesets_from_diffs(), fn changeset ->
      Fracomex.Repo.update(changeset)
    end)
  end

  # PRÉPARATION DES DIFFÉRENCES POUR LES SOUS-FAMILLES QUI DEVRONT ÊTRE MISES À JOUR
  def get_item_sub_families_valid_changesets_from_diffs do
    check_item_sub_families_diffs()
    |> Enum.filter(fn changeset ->
      changeset.changes != %{} and changeset.valid?
    end)
  end

  # CHANGESETS INVALIDES DES SOUS-FAMILLES
      # TOUJOURS VIDE CAR LES IDS SELECTIONNES POUR CETTE REQUÊTE N'INCLUENT QUE CEUX QUI ONT DEJA KEUR FAMILES SUR LA BASE POSTGRES
  def get_item_sub_families_invalid_changesets_from_diffs do
    check_item_sub_families_diffs()
    |> Enum.filter(fn changeset ->
      changeset.changes != %{} and not changeset.valid?
    end)
  end

  # VÉRIFICATION DES DIFFÉRENCES ENTRE LES SOUS-FAMILLES POSTGRES ET EBP
  def check_item_sub_families_diffs do
    ids = get_item_sub_family_ids_already_inserted()

    for id <- ids do
      {:ok, result} = EbpRepo.query("SELECT Caption, ItemFamilyId from ItemSubFamily WHERE Id='#{id}'")

      ebp_caption = result.rows |> Enum.at(0) |> Enum.at(0)
      ebp_item_family_id = result.rows |> Enum.at(0) |> Enum.at(1)

      item_sub_family = Products.get_sub_family!(id)

      SubFamily.update_changeset(item_sub_family, %{"caption" => ebp_caption, "family_id" => ebp_item_family_id})

    end
  end

  # SELECTION DES ID'S DE SOUS FAMILLES DÉJÀ EXISTANTES SUR POSTGRES
  def get_item_sub_family_ids_already_inserted do
    Enum.filter(select_all_item_subfamily_ids_from_ebp(), fn ebp_id ->
      ebp_id in select_all_item_sub_family_ids_from_postgres()
    end)
  end

  #  INSERTION DES SOUS-FAMILLES MANQUANTES
  def insert_missing_item_sub_families() do
    select_missing_item_subfamilies()
    |> Products.insert_sub_families
  end

  # SELECTION DE TOUTES LES SOUS FAMILLES, FILLES DES FAMILLES VENANT D'EBP
  def select_missing_item_subfamilies do

    readable_ids = get_item_sub_family_ids_to_be_inserted()
    |> ids_list_to_sql_readable()

    case EbpRepo.query("select Id, Caption, ItemFamilyId from ItemSubFamily where Id in #{readable_ids}") do
      {:ok, result} ->
        result.rows |> Enum.map(fn row -> %{id: Enum.at(row, 0), caption: Enum.at(row, 1), family_id: Enum.at(row, 2)} end)

      _ ->
        []
    end
  end

  # SELECTION DE TOUS LES IDS DES SOUS FAMILLES MANQUANTES
  def get_item_sub_family_ids_to_be_inserted do
    select_all_item_subfamily_ids_from_ebp()
    |> Enum.filter(fn ebp_id -> ebp_id not in select_all_item_sub_family_ids_from_postgres() end)
  end

  # SELECTION DE TOUS LES ID'S DES SOUS FAMILLES DANS POSTGRES
  def select_all_item_sub_family_ids_from_postgres do
    Products.list_sub_family_ids()
  end

  # SELECTION DE TOUS LES IDS DES SOUS-FAMILLES VENANT D'EBP
  def select_all_item_subfamily_ids_from_ebp  do
    family_ids = select_all_item_family_ids_from_postgres()
    ids = ids_list_to_sql_readable(family_ids)
    case EbpRepo.query("SELECT Id FROM ItemSubFamily WHERE ItemFamilyId IN #{ids}") do
      {:ok, result} ->
        result.rows |> Enum.map(fn row -> Enum.at(row, 0) end)
        _ ->
          []
    end
  end

  ###########  ITEM FAMILY SYNC LOGICS ###########

  # SYNCHRONISATION DES FAMILLES D'ARTICLES
  def sync_item_families do
    start = NaiveDateTime.local_now()
    IO.puts "ITEMFAMILY SYNC STARTING"
    insert_missing_item_families()
    update_item_families_diffs()
    delete_item_families()
    IO.puts "ITEMFAMILY SYNC STOPPING"
    ending = NaiveDateTime.local_now()
    IO.inspect(NaiveDateTime.diff(ending, start, :millisecond))
  end

  # SUPPRESSION DES FAMILLES N'EXISTANT PLUS SUR EBP OU NON PUBLIÉES
  def delete_item_families() do
    select_all_item_family_ids_to_be_deleted()
    |> Products.delete_families()
  end

  # SELECTION DE TOUS LES ID'S DE FAMILLES QUI NE SONT PLUS SUR EBP OU NON PUBLIÉES
  def select_all_item_family_ids_to_be_deleted do
    Enum.filter(select_all_item_family_ids_from_postgres(), fn id ->
      id not in select_all_item_family_ids_from_ebp()
    end)
  end

  # MISE A JOUR DES CHANGEMENTS DE VALEUR DES FAMILLES
  def update_item_families_diffs() do
    Enum.each(get_item_families_valid_changesets_from_diffs(), fn changeset ->
      Fracomex.Repo.update(changeset)
    end)
  end

  # PRÉPARATION DES DIFFÉRENCES POUR LES FAMILLES QUI DEVRONT ÊTRE MISES À JOUR
  def get_item_families_valid_changesets_from_diffs do
    check_item_families_diffs()
    |> Enum.filter(fn changeset ->
      changeset.changes != %{} and changeset.valid?
    end)
  end

  # VÉRIFICATION DES DIFFÉRENCES ENTRE LES FAMILLES POSTGRES ET EBP
  def check_item_families_diffs do
    ids = get_item_family_ids_already_inserted()

    for id <- ids do
      {:ok, result} = EbpRepo.query("SELECT Caption from ItemFamily WHERE Id='#{id}'")

      ebp_caption = result.rows |> Enum.at(0) |> Enum.at(0)
      item_family = Products.get_family!(id)
      Family.update_changeset(item_family, %{"caption" => ebp_caption})

    end
  end

  # TROUVER LES ID'S DE FAMILLES DÉJÀ INSÉRÉES SUR POSTGRES
  def get_item_family_ids_already_inserted do
    Enum.filter(select_all_item_family_ids_from_ebp(), fn id ->
                            id in select_all_item_family_ids_from_postgres()
                          end)
  end

  ### INSERTION DES FAMILLES MANQUANTES
  def insert_missing_item_families() do
    select_item_families_to_be_inserted()
    # |> Products.insert_families
    |> Enum.each(fn family -> Fracomex.Repo.insert(family) end)
  end

  # SELECTION DES FAMILLES A INSÉRER
  def select_item_families_to_be_inserted do
    ids = get_item_family_ids_to_be_inserted()
    readable_ids = ids_list_to_sql_readable(ids)

    case EbpRepo.query("select Id, Caption from ItemFamily where AllowPublishOnWeb=1 and Id in #{readable_ids}") do
      {:ok, result} ->
        result.rows |> Enum.map(fn row ->
          id = Enum.at(row, 0)
          caption = Enum.at(row, 1)

          {:ok, sub_family_result} = EbpRepo.query("select Id, Caption, ItemFamilyId from ItemSubFamily where ItemFamilyId='#{id}'")

          sub_families = sub_family_result.rows
          |> Enum.map(fn row -> %SubFamily{id: Enum.at(row, 0), caption: Enum.at(row, 1), family_id: Enum.at(row, 2)} end )

          %Family{id: id, caption: caption, sub_families: sub_families}
        end)
      _ ->
        []
    end

  end

  # CONVERSION DE LISTE D'ID'S POUR ÉTRE LUE PAR LE SCRIPT SQL
  def ids_list_to_sql_readable(ids_list) do
    ids = Enum.map(ids_list, fn id -> "\'#{id}\'" end)
    "(#{Enum.join(ids, ",")})"
  end

  # TROUVER LES ID'S DE FAMILLE MANQUANTS SUR POSTGRES
  def get_item_family_ids_to_be_inserted do
    Enum.filter(select_all_item_family_ids_from_ebp(), fn id ->
                            id not in select_all_item_family_ids_from_postgres()
                          end)
  end

  # SELECTION DE TOUS LES ID'S DE FAMILLE VENANT DE LA BASE POSTGRES DU SITE
  def select_all_item_family_ids_from_postgres do
    Products.list_family_ids()
  end

  # SELECTION DE TOUS LES ID'S DE FAMILLE VENANT DE LA BASE EBP
  def select_all_item_family_ids_from_ebp do
    {:ok, result} = EbpRepo.query("select Id from ItemFamily where AllowPublishOnWeb=1")
    result.rows |> Enum.map(fn result_row ->
      Enum.at(result_row, 0)
    end)
  end

end

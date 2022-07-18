defmodule FracomexWeb.Router do
  use FracomexWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, {FracomexWeb.LayoutView, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", FracomexWeb do
    pipe_through :browser

    get "/", PageController, :index
    get "/boutique", ProductController, :index

    get "/product-details", SingleProductController, :index

    get "/panier", CartController, :index

    # get "/users", UsersController, :index
    get "/connexion", UsersController, :signin
    get "/inscription", UsersController, :signup
    get "/deconnexion", UsersController, :signout
    get "/verification_confirmation_mai", UsersController, :check_signup_mail
    get "/verification_motdepasse_oublie", UsersController, :check_forgotten_password_mail
    get "/motdepasse_oublie", UsersController, :forgot_password
    get "/renvoi_verification_mail", UsersController, :resend_confirmation_mail
    get "/mon_profil", UsersController, :my_account
    get "/mon_adresse", UsersController, :my_address

    post "/valider_connexion", UsersController, :submit_signin
    post "/valider_inscription", UsersController, :submit_signup
    post "/envoi_mail_motdepasse_oublie", UsersController, :submit_forgotten_password
    post "/renvoi_mail_confirmation", UsersController, :submit_resend_confirmation_mail

    put "/modifier_motdepasse/:id", UsersController, :submit_new_password_forgotten
    put "/modifier_profil/:id", UsersController, :edit_my_account
    put "/modifier_adresse/:id", UsersController, :edit_my_address
  end

  # Other scopes may use custom stacks.
  # scope "/api", FracomexWeb do
  #   pipe_through :api
  # end

  # Enables LiveDashboard only for development
  #
  # If you want to use the LiveDashboard in production, you should put
  # it behind authentication and allow only admins to access it.
  # If your application does not have an admins-only section yet,
  # you can use Plug.BasicAuth to set up some basic authentication
  # as long as you are also using SSL (which you should anyway).
  if Mix.env() in [:dev, :test] do
    import Phoenix.LiveDashboard.Router

    scope "/" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: FracomexWeb.Telemetry
    end
  end

  # Enables the Swoosh mailbox preview in development.
  #
  # Note that preview only shows emails that were sent by the same
  # node running the Phoenix server.
  if Mix.env() == :dev do
    scope "/dev" do
      pipe_through :browser

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end

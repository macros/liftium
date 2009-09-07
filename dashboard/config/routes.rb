ActionController::Routing::Routes.draw do |map|

  map.resources :adformats, :active_scaffold => true
  map.resources :tags
  map.resources :networks
  map.resources :publishers
  map.resources :password_resets

  # Auth logic
  map.resource :user_session
  map.resource :account, :controller => "users"
  map.resources :users


  map.root :controller => "welcome"

  # See how all your routes lay out with "rake routes"

  # Install the default routes as the lowest priority.
  # Note: These default routes make all actions in every controller accessible via GET requests. You should
  # consider removing or commenting them out if you're using named routes and resources.
  map.connect ':controller/:action/:id'
  map.connect ':controller/:action/:id.:format'
end

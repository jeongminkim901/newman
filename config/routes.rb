Rails.application.routes.draw do
  resources :runs, only: [:index, :new, :create, :show] do
    member do
      get "report/:kind", action: :report, as: :report
      get "stream", action: :stream
    end
  end

  root "runs#new"
end

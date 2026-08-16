ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Rails parallelization forks one worker per processor, but Mongoid has no
    # notion of the per-worker databases ActiveRecord sets up. Without this,
    # every worker connects to the same `health_wallet_test` database and the
    # `Mongoid.purge!` below wipes documents other workers are mid-test on.
    # Point each worker at its own database so they stay isolated.
    parallelize_setup do |worker|
      Mongoid.disconnect_clients
      Mongoid::Config.clients["default"]["database"] = "health_wallet_test_#{worker}"
      Mongoid::Clients.clients.clear
    end

    parallelize_teardown do |worker|
      Mongoid.default_client.database.drop
    end

    # Add more helper methods to be used by all tests here...

    # Clean up MongoDB before each test
    setup do
      Mongoid.purge!
    end
  end
end

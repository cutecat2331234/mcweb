# The test environment is used exclusively to run your application's
# test suite. You never need to work with it otherwise. Remember that
# your test database is "scratch space" for the test suite and is wiped
# and recreated between test runs. Don't rely on the data there!

# Rails command-line options such as `rails runner -e test` and `rails test`
# can select this environment after config/boot.rb has already cached the
# local Developer Mode profile. Reparse it here so the ordinary test suite
# always exercises production security semantics.
ENV["MCWEB_DEVELOPER_MODE"] = "0"
Mcweb::DeveloperMode.reload!

require_relative "../developer_mode_runtime"
require_relative "../../lib/mcweb/test_log_path"

Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # While tests run files are not watched, reloading is not necessary.
  config.enable_reloading = false

  # Eager loading loads your entire application. When running a single test locally,
  # this is usually not necessary, and can slow down your test suite. However, it's
  # recommended that you enable it in continuous integration systems to ensure eager
  # loading is working properly before deploying your code.
  config.eager_load = ENV["CI"].present?

  # Configure public file server for tests with cache-control for performance.
  config.public_file_server.headers = { "cache-control" => "public, max-age=3600" }

  # Show full error reports.
  config.consider_all_requests_local = true
  config.cache_store = :null_store

  # Render exception templates for rescuable exceptions and raise for other exceptions.
  config.action_dispatch.show_exceptions = :rescuable

  # Disable request forgery protection in test environment.
  config.action_controller.allow_forgery_protection = false

  # Store uploaded files on the local file system in a temporary directory.
  config.active_storage.service = :test

  config.active_job.queue_adapter = :test

  # Tell Action Mailer not to deliver emails to the real world.
  # The :test delivery method accumulates sent emails in the
  # ActionMailer::Base.deliveries array.
  config.action_mailer.delivery_method = :test

  # Set host to be used by links generated in mailer templates.
  config.action_mailer.default_url_options = { host: "example.com" }

  # Print deprecation notices to the stderr.
  config.active_support.deprecation = :stderr

  # Parallel test processes must never rotate or close another process's log
  # stream on Windows. Keep log/test.log for the normal single-worker run,
  # suffix parallel-worker logs with TEST_ENV_NUMBER, and allow CI to select an
  # explicit path when it orchestrates multiple suites.
  config.logger = ActiveSupport::TaggedLogging.logger(
    Mcweb::TestLogPath.resolve(root: Rails.root)
  )

  # Raises error for missing translations.
  config.i18n.raise_on_missing_translations = true

  # Annotate rendered view with file names.
  # config.action_view.annotate_rendered_view_with_filenames = true

  # Raise error when a before_action's only/except options reference missing actions.
  config.action_controller.raise_on_missing_callback_actions = true

  Mcweb::DeveloperModeRuntime.apply!(config)

  # Developer-mode runtime profiles may use async or inline jobs locally, but
  # the test environment must retain deterministic queue assertions.
  config.active_job.queue_adapter = :test
end

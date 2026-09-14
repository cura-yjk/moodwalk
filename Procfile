# Runs before each release. Without it nothing applies migrations on deploy:
# this is a buildpack app, so the db:prepare in bin/docker-entrypoint never
# executes, and every migration has had to be run by hand. A failing release
# aborts the deploy rather than leaving the app running against a stale schema.
#
# db:prepare also creates the Solid Queue tables from db/queue_schema.rb. Those
# being absent is what crashed production when SOLID_QUEUE_IN_PUMA was set:
# config/puma.rb starts the Solid Queue plugin, it found no tables, and it
# stopped Puma on its way down.
release: bin/rails db:prepare

# Identical to the command Heroku already runs by default for this app, so
# adding this file changes nothing about how the web process starts -- only
# that the release phase above now exists.
web: bin/rails server -p ${PORT:-5000} -e $RAILS_ENV
